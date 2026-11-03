-- Private service runtime: versioned atomic command state, never exposed to clients.
create table public.gateway_runtime (
 id boolean primary key default true check(id), revision bigint not null default 0,
 state jsonb not null default '{"merchants":[],"intents":[],"devices":[],"signals":[],"provider_events":[],"audit":[],"qr_sources":[],"endpoints":[],"deliveries":[],"api_keys":[],"challenges":[],"idempotency":{},"limits":{}}'
);
alter table public.gateway_runtime enable row level security;
revoke all on public.gateway_runtime from anon,authenticated;
grant all on public.gateway_runtime to service_role;
insert into public.gateway_runtime(id) values(true);

alter table public.payment_intents add column environment text not null default 'sandbox' check(environment in ('sandbox','production'));
alter table public.payment_intents add constraint sandbox_never_paid check(not (environment='sandbox' and status='PAID'));
alter table public.payment_intents add constraint production_never_simulated check(not (environment='production' and status='SIMULATED_PAID'));
alter table public.merchant_devices add column expires_at timestamptz;
alter table public.merchant_devices add column allowed_packages text[] not null default '{}';
alter table public.merchant_devices add column consented_at timestamptz;
alter table public.provider_events add column amount_idr bigint not null default 1 check(amount_idr between 1 and 10000000);
alter table public.provider_events add column currency text not null default 'IDR' check(currency='IDR');
alter table public.provider_events add column environment text not null default 'sandbox' check(environment in ('sandbox','production'));
alter table public.provider_events add column transaction_id text;
create unique index provider_transaction_unique on public.provider_events(provider_name,transaction_id);
alter table public.notification_signals add constraint signal_amount_limit check(amount_idr is null or amount_idr between 1 and 10000000);
create unique index signals_tenant_dedup on public.notification_signals(merchant_id,dedup_hash);
alter table public.audit_events add column actor_type text not null default 'server';
alter table public.audit_events add column actor_id text not null default 'server';

-- Composite tenant foreign keys close cross-tenant references, including service writes.
alter table public.merchant_devices add unique(merchant_id,id);
alter table public.merchant_qr_sources add unique(merchant_id,id);
alter table public.payment_intents add unique(merchant_id,id);
alter table public.webhook_endpoints add unique(merchant_id,id);
alter table public.notification_signals add constraint signal_device_tenant foreign key(merchant_id,device_id) references public.merchant_devices(merchant_id,id);
alter table public.payment_intents add constraint intent_qr_tenant foreign key(merchant_id,qr_source_id) references public.merchant_qr_sources(merchant_id,id);
alter table public.provider_events add constraint event_intent_tenant foreign key(merchant_id,payment_intent_id) references public.payment_intents(merchant_id,id);
alter table public.webhook_deliveries add constraint delivery_endpoint_tenant foreign key(merchant_id,endpoint_id) references public.webhook_endpoints(merchant_id,id);
alter table public.webhook_deliveries add constraint delivery_intent_tenant foreign key(merchant_id,payment_intent_id) references public.payment_intents(merchant_id,id);

create function public.guard_candidate_tenant() returns trigger language plpgsql set search_path='' as $$
begin
 if not exists(select 1 from public.notification_signals s join public.payment_intents p on p.merchant_id=s.merchant_id where s.id=new.signal_id and p.id=new.payment_intent_id) then
  raise exception 'cross-tenant candidate';
 end if; return new;
end $$;
create trigger candidate_tenant before insert or update on public.signal_candidates for each row execute function public.guard_candidate_tenant();

create function public.guard_financial_transition() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' and old.status='PAID' and (new.status<>old.status or new.amount_idr<>old.amount_idr or new.merchant_id<>old.merchant_id or new.verification_source is distinct from old.verification_source or new.provider_transaction_id is distinct from old.provider_transaction_id or new.verified_at is distinct from old.verified_at or new.environment<>old.environment) then raise exception 'verified payment is immutable'; end if;
 if new.status='PAID' and not exists(select 1 from public.provider_events e where e.merchant_id=new.merchant_id and e.payment_intent_id=new.id and e.verified_signature and e.provider_name=new.verification_source and e.provider_name<>'mock' and e.environment='production' and e.event_type='settlement' and e.amount_idr=new.amount_idr and e.currency=new.currency and e.transaction_id=new.provider_transaction_id) then raise exception 'verified provider event required'; end if;
 return new;
end $$;
create trigger financial_transition before insert or update on public.payment_intents for each row execute function public.guard_financial_transition();
create function public.reject_ledger_mutation() returns trigger language plpgsql set search_path='' as $$ begin raise exception 'immutable ledger'; end $$;
create trigger immutable_provider_events before update or delete on public.provider_events for each row execute function public.reject_ledger_mutation();
create trigger immutable_audit before update or delete on public.audit_events for each row execute function public.reject_ledger_mutation();

-- Explicit privilege surface. No direct authenticated mutations, even with forged JWT metadata.
revoke all on all tables in schema public from anon,authenticated;
grant select on public.merchants,public.merchant_members,public.payment_intents,public.notification_signals,public.provider_events to authenticated;
grant select(id,merchant_id,name,device_public_id,revoked_at,last_seen_at,created_at,expires_at,allowed_packages,consented_at) on public.merchant_devices to authenticated;
-- QR is served through authenticated API; no public bucket, payload or secret hash exposure.
grant all on all tables in schema public to service_role;
create policy candidates_read_tenant on public.signal_candidates for select to authenticated using(exists(select 1 from public.notification_signals s where s.id=signal_id and public.is_member(s.merchant_id)));

create function public.gateway_commit(expected_revision bigint,next_state jsonb)
returns boolean language plpgsql security invoker set search_path='' as $$
declare old_state jsonb; current_revision bigint; v jsonb; candidate jsonb;
begin
 select revision,state into current_revision,old_state from public.gateway_runtime where id=true for update;
 if current_revision<>expected_revision then return false; end if;
 if not ((next_state->'audit') @> (old_state->'audit')) or not((next_state->'provider_events') @> (old_state->'provider_events')) or not((next_state->'qr_sources') @> (old_state->'qr_sources')) then raise exception 'ledger truncation or alteration'; end if;
 for v in select value from jsonb_array_elements(next_state->'merchants') loop
  insert into public.merchants(id,name) values((v->>'id')::uuid,v->>'name') on conflict(id) do nothing;
 end loop;
 for v in select value from jsonb_array_elements(next_state->'qr_sources') loop
  insert into public.merchant_qr_sources(id,merchant_id,storage_path) values((v->>'id')::uuid,(v->>'merchant_id')::uuid,'runtime/'||(v->>'id')) on conflict(id) do nothing;
 end loop;
 for v in select value from jsonb_array_elements(next_state->'devices') loop
  insert into public.merchant_devices(id,merchant_id,name,device_public_id,token_hash,expires_at,allowed_packages,consented_at,revoked_at,last_seen_at)
  values((v->>'id')::uuid,(v->>'merchant_id')::uuid,v->>'name',v->>'id',v->>'token_hash',(v->>'expires_at')::timestamptz,array(select jsonb_array_elements_text(v->'allowed_packages')),(v->>'consented_at')::timestamptz,(v->>'revoked_at')::timestamptz,(v->>'last_seen_at')::timestamptz)
  on conflict(id) do update set token_hash=excluded.token_hash,expires_at=excluded.expires_at,revoked_at=excluded.revoked_at,last_seen_at=excluded.last_seen_at;
 end loop;
 for v in select value from jsonb_array_elements(next_state->'intents') loop
  insert into public.payment_intents(id,merchant_id,public_reference,external_reference,qr_source_id,amount_idr,expires_at,created_at,environment)
  values((v->>'id')::uuid,(v->>'merchant_id')::uuid,v->>'public_reference',v->>'external_reference',(v->>'qr_source_id')::uuid,(v->>'amount_idr')::bigint,(v->>'expires_at')::timestamptz,(v->>'created_at')::timestamptz,v->>'environment') on conflict(id) do nothing;
 end loop;
 for v in select value from jsonb_array_elements(next_state->'provider_events') loop
  insert into public.provider_events(id,merchant_id,payment_intent_id,provider_name,provider_event_id,verified_signature,event_type,amount_idr,currency,environment,transaction_id)
  values((v->>'id')::uuid,(v->>'merchant_id')::uuid,(v->>'intent_id')::uuid,v->>'provider',v->>'event_id',true,v->>'event_type',(v->>'amount_idr')::bigint,v->>'currency',v->>'environment',v->>'transaction_id') on conflict(provider_name,provider_event_id) do nothing;
 end loop;
 for v in select value from jsonb_array_elements(next_state->'intents') loop
  update public.payment_intents set status=(v->>'status')::public.payment_status,verification_source=v->>'verification_source',verified_at=(v->>'verified_at')::timestamptz,provider_transaction_id=v->>'provider_transaction_id',updated_at=now() where id=(v->>'id')::uuid and merchant_id=(v->>'merchant_id')::uuid;
 end loop;
 delete from public.notification_signals where not exists(select 1 from jsonb_array_elements(next_state->'signals') s where (s->>'id')::uuid=notification_signals.id);
 for v in select value from jsonb_array_elements(next_state->'signals') loop
  insert into public.notification_signals(id,merchant_id,device_id,source_package,amount_idr,posted_at,dedup_hash)
  values((v->>'id')::uuid,(v->>'merchant_id')::uuid,(v->>'device_id')::uuid,v->>'source_package',(v->>'amount_idr')::bigint,(v->>'posted_at')::timestamptz,v->>'dedup_hash') on conflict(id) do nothing;
  for candidate in select value from jsonb_array_elements(v->'candidate_payment_intent_ids') loop
   insert into public.signal_candidates(signal_id,payment_intent_id) values((v->>'id')::uuid,(candidate#>>'{}')::uuid) on conflict do nothing;
  end loop;
 end loop;
 for v in select value from jsonb_array_elements(next_state->'api_keys') loop
  insert into public.api_keys(id,merchant_id,key_prefix,secret_hash,scopes,expires_at,revoked_at)
  values((v->>'id')::uuid,(v->>'merchant_id')::uuid,v->>'key_prefix',v->>'secret_hash',array(select jsonb_array_elements_text(v->'scopes')),(v->>'expires_at')::timestamptz,(v->>'revoked_at')::timestamptz)
  on conflict(id) do update set revoked_at=excluded.revoked_at;
 end loop;
 for v in select value from jsonb_array_elements(next_state->'endpoints') loop
  insert into public.webhook_endpoints(id,merchant_id,url,signing_secret_encrypted,active)
  values((v->>'id')::uuid,(v->>'merchant_id')::uuid,v->>'url',v->>'secret_encrypted',(v->>'active')::boolean)
  on conflict(id) do update set signing_secret_encrypted=excluded.signing_secret_encrypted,active=excluded.active;
 end loop;
 for v in select value from jsonb_array_elements(next_state->'deliveries') loop
  insert into public.webhook_deliveries(id,merchant_id,endpoint_id,event_type,attempt_count,delivered_at,next_attempt_at)
  values((v->>'id')::uuid,(v->>'merchant_id')::uuid,(v->>'endpoint_id')::uuid,v->>'event_type',(v->>'attempt_count')::int,(v->>'delivered_at')::timestamptz,(v->>'next_attempt_at')::timestamptz)
  on conflict(id) do update set attempt_count=excluded.attempt_count,delivered_at=excluded.delivered_at,next_attempt_at=excluded.next_attempt_at;
 end loop;
 for v in select value from jsonb_array_elements(next_state->'audit') loop
  insert into public.audit_events(id,merchant_id,action,resource_id,occurred_at,actor_type,actor_id)
  values((v->>'id')::uuid,(v->>'merchant_id')::uuid,v->>'action',(v->>'resource_id')::uuid,(v->>'occurred_at')::timestamptz,v->>'actor_type',v->>'actor_id') on conflict(id) do nothing;
 end loop;
 update public.gateway_runtime set state=next_state,revision=revision+1 where id=true;
 return true;
end $$;
revoke all on function public.gateway_commit(bigint,jsonb) from public,anon,authenticated;
grant execute on function public.gateway_commit(bigint,jsonb) to service_role;
revoke all on function public.guard_candidate_tenant(),public.guard_financial_transition(),public.reject_ledger_mutation() from public;
