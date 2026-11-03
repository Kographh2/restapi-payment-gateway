-- MANJI Gateway is isolated from the existing Manji Food public schema.
-- Apply this and the following MANJI migration only after the compatibility review.
create schema if not exists manji_gateway;
revoke all on schema manji_gateway from public;
grant usage on schema manji_gateway to anon,authenticated,service_role;

create table manji_gateway.profiles(
 id uuid primary key references auth.users(id),email text not null,display_name text not null default '',
 role text not null default 'PENDING' check(role in ('PENDING','USER','MERCHANT','ADMIN')),
 status text not null default 'ACTIVE' check(status in ('ACTIVE','SUSPENDED','REJECTED')),
 email_verified_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table manji_gateway.merchant_applications(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references manji_gateway.profiles(id),
 business_name text not null check(length(business_name) between 2 and 120),business_description text not null,phone text not null,
 status text not null default 'PENDING' check(status in ('PENDING','APPROVED','REJECTED','SUSPENDED')),
 reviewed_by uuid references manji_gateway.profiles(id),review_note text,reviewed_at timestamptz,created_at timestamptz not null default now()
);
create unique index one_open_application on manji_gateway.merchant_applications(user_id) where status='PENDING';
create table manji_gateway.merchants(
 id uuid primary key default gen_random_uuid(),identifier text not null unique,name text not null,
 owner_user_id uuid not null references manji_gateway.profiles(id),status text not null default 'ACTIVE' check(status in ('ACTIVE','SUSPENDED')),
 application_id uuid unique references manji_gateway.merchant_applications(id),created_at timestamptz not null default now()
);
create table manji_gateway.merchant_memberships(
 merchant_id uuid not null references manji_gateway.merchants(id),user_id uuid not null references manji_gateway.profiles(id),
 member_role text not null default 'owner' check(member_role in ('owner','manager','staff')),created_at timestamptz not null default now(),primary key(merchant_id,user_id)
);
create table manji_gateway.account_sessions(
 id uuid primary key,user_id uuid not null references manji_gateway.profiles(id),device_name text not null default 'Sesi pengguna',
 access_hash text,refresh_hash text,expires_at timestamptz not null,revoked_at timestamptz,last_seen_at timestamptz not null default now(),created_at timestamptz not null default now()
);
create table manji_gateway.merchant_devices(
 id uuid primary key default gen_random_uuid(),merchant_id uuid not null references manji_gateway.merchants(id),
 user_id uuid not null references manji_gateway.profiles(id),session_id uuid references manji_gateway.account_sessions(id),name text not null,
 allowed_packages text[] not null default '{}',consented_at timestamptz not null,revoked_at timestamptz,last_seen_at timestamptz,
 created_at timestamptz not null default now(),unique(merchant_id,id)
);
create table manji_gateway.device_credentials(
 id uuid primary key,merchant_id uuid not null,device_id uuid not null,user_id uuid not null references manji_gateway.profiles(id),
 secret_hash text not null check(length(secret_hash)=64),expires_at timestamptz not null,revoked_at timestamptz,created_at timestamptz not null default now(),
 foreign key(merchant_id,device_id) references manji_gateway.merchant_devices(merchant_id,id)
);
create table manji_gateway.enrollment_challenges(
 id uuid primary key,merchant_id uuid not null references manji_gateway.merchants(id),actor_id uuid not null references manji_gateway.profiles(id),
 subject_id uuid,kind text not null,name text not null,allowed_packages text[] not null,secret_hash text not null,expires_at timestamptz not null,consumed_at timestamptz
);
create table manji_gateway.merchant_api_keys(
 id uuid primary key,merchant_id uuid not null references manji_gateway.merchants(id),created_by uuid not null references manji_gateway.profiles(id),
 public_id text not null unique,name text not null,layer text not null check(layer in ('ENROLLMENT','INTEGRATION')),
 secret_hash text not null check(length(secret_hash)=64),scopes text[] not null,expires_at timestamptz not null,revoked_at timestamptz,last_used_at timestamptz,
 created_at timestamptz not null default now(),check((layer='ENROLLMENT' and scopes=array['devices:enroll']) or (layer='INTEGRATION' and not('devices:enroll'=any(scopes))))
);
create table manji_gateway.qr_sources(
 id uuid primary key,merchant_id uuid not null references manji_gateway.merchants(id),mime text not null check(mime in ('image/png','image/jpeg')),
 bytes_base64 text not null check(length(bytes_base64)<=950000),sha256 text not null check(length(sha256)=64),created_at timestamptz not null default now(),unique(merchant_id,id)
);
create table manji_gateway.payment_requests(
 id uuid primary key default gen_random_uuid(),merchant_id uuid not null references manji_gateway.merchants(id),public_reference text not null unique,external_reference text,
 amount_idr bigint not null check(amount_idr between 1 and 10000000),currency text not null default 'IDR' check(currency='IDR'),
 qr_mode text not null default 'STATIC_QRIS' check(qr_mode in ('STATIC_QRIS','PROVIDER_DYNAMIC_QRIS')),qr_source_id uuid,
 status text not null default 'CREATED' check(status in ('CREATED','PENDING','PAYMENT_DETECTED','VERIFYING','PAID','EXPIRED','FAILED','REVIEW_REQUIRED','REFUNDED','SIMULATED_PAID')),
 environment text not null check(environment in ('sandbox','production')),verification_source text,verified_at timestamptz,provider_transaction_id text,failure_reason text,
 expires_at timestamptz not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(merchant_id,id),unique(merchant_id,external_reference),foreign key(merchant_id,qr_source_id) references manji_gateway.qr_sources(merchant_id,id),
 check(not(environment='sandbox' and status in ('PAID','REFUNDED'))),check(not(environment='production' and status='SIMULATED_PAID')),
 check((status in ('PAID','REFUNDED') and verified_at is not null and verification_source is not null) or (status not in ('PAID','REFUNDED') and verified_at is null))
);
create index payment_cursor on manji_gateway.payment_requests(merchant_id,created_at desc,id desc);
create table manji_gateway.payment_events(
 id uuid primary key default gen_random_uuid(),merchant_id uuid not null,payment_id uuid not null,from_status text,to_status text not null,source text not null,
 actor_id uuid,occurred_at timestamptz not null default now(),foreign key(merchant_id,payment_id) references manji_gateway.payment_requests(merchant_id,id)
);
create table manji_gateway.notification_signals(
 id uuid primary key,merchant_id uuid not null,device_id uuid not null,source_package text not null,amount_idr bigint check(amount_idr between 1 and 10000000),
 posted_at timestamptz not null,dedup_hash text not null check(dedup_hash~'^[a-f0-9]{64}$'),classification text not null default 'UNTRUSTED' check(classification='UNTRUSTED'),
 candidates uuid[] not null default '{}',ambiguous boolean not null default false,received_at timestamptz not null default now(),unique(merchant_id,dedup_hash),
 foreign key(merchant_id,device_id) references manji_gateway.merchant_devices(merchant_id,id)
);
create table manji_gateway.payment_verifications(
 id uuid primary key default gen_random_uuid(),merchant_id uuid not null,payment_id uuid not null,provider text not null,event_id text not null,transaction_id text not null,
 amount_idr bigint not null check(amount_idr between 1 and 10000000),currency text not null check(currency='IDR'),environment text not null check(environment in ('sandbox','production')),
 event_type text not null check(event_type in ('settlement','refund')),signature_verified boolean not null check(signature_verified),fingerprint text not null,
 received_at timestamptz not null default now(),unique(provider,event_id),unique(provider,transaction_id,event_type),
 foreign key(merchant_id,payment_id) references manji_gateway.payment_requests(merchant_id,id)
);
create table manji_gateway.webhook_endpoints(
 id uuid primary key,merchant_id uuid not null references manji_gateway.merchants(id),url text not null check(url like 'https://%'),secret_encrypted text not null,
 active boolean not null default false,revoked_at timestamptz,challenge text not null,created_at timestamptz not null default now(),unique(merchant_id,id)
);
create table manji_gateway.webhook_deliveries(
 id uuid primary key default gen_random_uuid(),merchant_id uuid not null,endpoint_id uuid not null,event_type text not null,environment text not null,payload jsonb not null,
 attempt_count int not null default 0,next_attempt_at timestamptz not null default now(),lease_token uuid,lease_until timestamptz,delivered_at timestamptz,dead boolean not null default false,last_status int,
 created_at timestamptz not null default now(),foreign key(merchant_id,endpoint_id) references manji_gateway.webhook_endpoints(merchant_id,id)
);
create table manji_gateway.audit_logs(
 id uuid primary key default gen_random_uuid(),merchant_id uuid references manji_gateway.merchants(id),actor_id uuid,action text not null,resource_id uuid,details jsonb not null default '{}',occurred_at timestamptz not null default now()
);
create table manji_gateway.security_events(
 id uuid primary key default gen_random_uuid(),merchant_id uuid references manji_gateway.merchants(id),actor_id uuid,code text not null,request_id uuid,occurred_at timestamptz not null default now()
);
create table manji_gateway.api_request_logs(
 id uuid primary key default gen_random_uuid(),merchant_id uuid references manji_gateway.merchants(id),actor_id uuid,credential_id uuid,request_id uuid not null,operation text not null,
 method text not null,status_code int not null,duration_ms int not null,occurred_at timestamptz not null default now()
);
create table manji_gateway.system_configuration(id boolean primary key default true check(id),value jsonb not null,updated_at timestamptz not null default now());
insert into manji_gateway.system_configuration(value) values('{"registration_open":true,"max_amount_idr":10000000,"signal_retention_days":7,"notification_sources":[]}');
create table manji_gateway.idempotency_records(actor_id uuid not null,subject text not null,operation text not null,key text not null,fingerprint text not null,response jsonb not null,created_at timestamptz not null default now(),primary key(actor_id,subject,operation,key));
create table manji_gateway.rate_limits(key text primary key,count int not null,expires_at timestamptz not null);

create function manji_gateway.bootstrap_profile() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into manji_gateway.profiles(id,email,display_name,email_verified_at) values(new.id,coalesce(new.email,''),left(coalesce(new.raw_user_meta_data->>'display_name',''),100),new.email_confirmed_at) on conflict(id) do nothing;
 return new;end $$;
create trigger manji_gateway_signup after insert on auth.users for each row execute function manji_gateway.bootstrap_profile();
create function manji_gateway.current_account_active() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from manji_gateway.profiles p join manji_gateway.account_sessions s on s.user_id=p.id where p.id=auth.uid() and p.status='ACTIVE' and p.email_verified_at is not null and s.id=nullif(auth.jwt()->>'session_id','')::uuid and s.revoked_at is null and s.expires_at>now());$$;
create function manji_gateway.is_admin() returns boolean language sql stable security definer set search_path='' as $$select manji_gateway.current_account_active() and exists(select 1 from manji_gateway.profiles where id=auth.uid() and role='ADMIN');$$;
create function manji_gateway.can_access_merchant(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select manji_gateway.current_account_active() and exists(select 1 from manji_gateway.profiles p join manji_gateway.merchant_memberships mm on mm.user_id=p.id join manji_gateway.merchants m on m.id=mm.merchant_id where p.id=auth.uid() and p.role='MERCHANT' and m.id=target and m.status='ACTIVE');$$;

create function manji_gateway.immutable_ledger() returns trigger language plpgsql set search_path='' as $$begin raise exception 'IMMUTABLE_LEDGER';end $$;
create trigger immutable_payment_events before update or delete on manji_gateway.payment_events for each row execute function manji_gateway.immutable_ledger();
create trigger immutable_verifications before update or delete on manji_gateway.payment_verifications for each row execute function manji_gateway.immutable_ledger();
create trigger immutable_audit before update or delete on manji_gateway.audit_logs for each row execute function manji_gateway.immutable_ledger();
create trigger immutable_qr before update or delete on manji_gateway.qr_sources for each row execute function manji_gateway.immutable_ledger();
create function manji_gateway.guard_payment() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='UPDATE' and new.status<>old.status and not(case old.status
  when 'CREATED' then new.status in ('PENDING','FAILED','EXPIRED')
  when 'PENDING' then new.status in ('PAYMENT_DETECTED','VERIFYING','FAILED','EXPIRED','REVIEW_REQUIRED','SIMULATED_PAID')
  when 'PAYMENT_DETECTED' then new.status in ('VERIFYING','FAILED','EXPIRED','REVIEW_REQUIRED','SIMULATED_PAID')
  when 'VERIFYING' then new.status in ('PAID','FAILED','REVIEW_REQUIRED')
  when 'REVIEW_REQUIRED' then new.status in ('VERIFYING','FAILED','EXPIRED','SIMULATED_PAID')
  when 'EXPIRED' then new.status='REVIEW_REQUIRED'
  when 'FAILED' then new.status='REVIEW_REQUIRED'
  when 'SIMULATED_PAID' then new.status='REVIEW_REQUIRED'
  when 'PAID' then new.status='REFUNDED'
  else false end) then raise exception 'INVALID_STATE';end if;
 if tg_op='UPDATE' and (new.amount_idr<>old.amount_idr or new.merchant_id<>old.merchant_id or new.currency<>old.currency or new.environment<>old.environment or new.public_reference<>old.public_reference or new.qr_source_id is distinct from old.qr_source_id) then raise exception 'IMMUTABLE_PAYMENT_FACTS';end if;
 if tg_op='UPDATE' and old.status='REFUNDED' and new is distinct from old then raise exception 'IMMUTABLE_REFUND';end if;
 if tg_op='UPDATE' and old.status='PAID' and (new.status not in ('PAID','REFUNDED') or new.verification_source is distinct from old.verification_source or new.verified_at is distinct from old.verified_at or new.provider_transaction_id is distinct from old.provider_transaction_id) then raise exception 'IMMUTABLE_SETTLEMENT';end if;
 if new.status in ('PAID','REFUNDED') and not exists(select 1 from manji_gateway.payment_verifications v where v.merchant_id=new.merchant_id and v.payment_id=new.id and v.signature_verified and v.environment='production' and v.provider<>'mock' and v.provider=new.verification_source and v.transaction_id=new.provider_transaction_id and v.amount_idr=new.amount_idr and v.currency=new.currency and v.event_type=case when new.status='REFUNDED' then 'refund' else 'settlement' end) then raise exception 'VERIFIED_PROVIDER_EVENT_REQUIRED';end if;
 return new;end $$;
create trigger verified_payment_guard before insert or update on manji_gateway.payment_requests for each row execute function manji_gateway.guard_payment();

do $$declare t record;begin for t in select tablename from pg_tables where schemaname='manji_gateway' loop execute format('alter table manji_gateway.%I enable row level security',t.tablename);end loop;end $$;
revoke all on all tables in schema manji_gateway from public,anon,authenticated;
grant all on all tables in schema manji_gateway to service_role;
grant select on manji_gateway.profiles,manji_gateway.merchant_applications,manji_gateway.merchants,manji_gateway.merchant_memberships,manji_gateway.merchant_devices,manji_gateway.payment_requests,manji_gateway.payment_events,manji_gateway.notification_signals,manji_gateway.payment_verifications,manji_gateway.audit_logs,manji_gateway.security_events,manji_gateway.api_request_logs to authenticated;
grant select(id,user_id,device_name,expires_at,revoked_at,last_seen_at,created_at) on manji_gateway.account_sessions to authenticated;
grant select(id,merchant_id,public_id,name,layer,scopes,expires_at,revoked_at,last_used_at,created_at) on manji_gateway.merchant_api_keys to authenticated;
grant select(id,merchant_id,url,active,revoked_at,created_at) on manji_gateway.webhook_endpoints to authenticated;
grant select(id,merchant_id,endpoint_id,event_type,environment,attempt_count,next_attempt_at,delivered_at,dead,last_status,created_at) on manji_gateway.webhook_deliveries to authenticated;
create policy profile_self on manji_gateway.profiles for select to authenticated using(id=auth.uid() or manji_gateway.is_admin());
create policy application_self on manji_gateway.merchant_applications for select to authenticated using(user_id=auth.uid() or manji_gateway.is_admin());
create policy session_self on manji_gateway.account_sessions for select to authenticated using(user_id=auth.uid() or manji_gateway.is_admin());
create policy merchant_member on manji_gateway.merchants for select to authenticated using(manji_gateway.can_access_merchant(id) or manji_gateway.is_admin());
do $$declare t text;begin foreach t in array array['merchant_memberships','merchant_devices','merchant_api_keys','payment_requests','payment_events','notification_signals','payment_verifications','webhook_endpoints','webhook_deliveries','audit_logs','security_events','api_request_logs'] loop execute format('create policy tenant_read on manji_gateway.%I for select to authenticated using(manji_gateway.can_access_merchant(merchant_id) or manji_gateway.is_admin())',t);end loop;end $$;
revoke all on all functions in schema manji_gateway from public,anon,authenticated;
grant execute on function manji_gateway.current_account_active(),manji_gateway.is_admin(),manji_gateway.can_access_merchant(uuid) to authenticated;

-- Realtime exposes only normalized status rows, never secrets/runtime blobs.
do $$begin if exists(select 1 from pg_publication where pubname='supabase_realtime') then alter publication supabase_realtime add table manji_gateway.payment_requests;end if;end $$;
