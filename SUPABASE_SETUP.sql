-- MANJI Gateway - paket SQL Supabase untuk instalasi awal.
-- Sumber resmi: ../supabase/migrations/20261102*.sql (5 migrasi, sesuai urutan).
-- Jalankan seluruh file di Supabase SQL Editor sebagai postgres/owner.
-- Gunakan hanya jika schema manji_gateway belum pernah dipasang.
-- Jika sudah terpasang sebagian, jalankan hanya migrasi lanjutan yang belum dipasang.
-- Setiap migrasi menggunakan transaksinya sendiri; blok sebelumnya tetap tersimpan
-- apabila blok berikutnya gagal. Jangan menjalankan ulang semua blok setelah gagal.
-- Paket ini tidak menghapus data dan tidak memuat migrasi historis 0001-0003,
-- auth fixture lokal, akun admin otomatis, password, atau credential aplikasi.
-- Bucket privat manji-app-releases harus belum ada sebelum migrasi 005.
-- Setelah selesai: tambahkan manji_gateway ke Exposed schemas di Supabase Data API.
-- Provisioning admin terpisah: ../scripts/provision-admin.sql (akun terverifikasi).
-- Belum dijalankan pada Supabase hosted oleh proses pembuatan file ini.

-- BEGIN SOURCE: 202611020001_manji_schema.sql
-- SOURCE SHA256: 43b3d831b6fc030e63c3d69314223b681ed627a7fb22588e7a3c1f3d38543a49
begin;

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

commit;
-- END SOURCE: 202611020001_manji_schema.sql

-- BEGIN SOURCE: 202611020002_manji_commands.sql
-- SOURCE SHA256: 3881cfd8f1126a127197e15ba1cd9dcb8ab82f3465b32bdfcec1e55f64fe2970
begin;

create function manji_gateway.audit(p_actor uuid,p_merchant uuid,p_action text,p_resource uuid,p_details jsonb default '{}') returns void language sql security definer set search_path='' as $$insert into manji_gateway.audit_logs(actor_id,merchant_id,action,resource_id,details) values(p_actor,p_merchant,p_action,p_resource,p_details);$$;
create function manji_gateway.emit(p_merchant uuid,p_type text,p_environment text,p_payload jsonb) returns void language sql security definer set search_path='' as $$
 insert into manji_gateway.webhook_deliveries(merchant_id,endpoint_id,event_type,environment,payload) select p_merchant,e.id,p_type,p_environment,p_payload from manji_gateway.webhook_endpoints e where e.merchant_id=p_merchant and e.active and e.revoked_at is null;$$;
create function manji_gateway.rate_check(p_key text,p_limit int) returns void language plpgsql security definer set search_path='' as $$declare n int;begin
 insert into manji_gateway.rate_limits(key,count,expires_at) values(p_key,1,now()+interval '1 minute') on conflict(key) do update set count=case when rate_limits.expires_at<now() then 1 else rate_limits.count+1 end,expires_at=case when rate_limits.expires_at<now() then now()+interval '1 minute' else rate_limits.expires_at end returning count into n;
 if n>p_limit then raise exception 'RATE_LIMITED';end if;end $$;
create function manji_gateway.account_command(p_actor uuid,p_session uuid,p_command text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare profile manji_gateway.profiles;app manji_gateway.merchant_applications;merchant manji_gateway.merchants;result jsonb;target uuid;action text;
begin
 if p_command='public.configuration' then return jsonb_build_object('registration_open',(select value->'registration_open' from manji_gateway.system_configuration where id));end if;
 if p_command='rate' then perform manji_gateway.rate_check(p_data->>'key',least((p_data->>'limit')::int,300));return '{"ok":true}';end if;
 if p_command='profile.bootstrap' then
  insert into manji_gateway.profiles(id,email,display_name,email_verified_at) select id,coalesce(email,''),left(coalesce(raw_user_meta_data->>'display_name',''),100),email_confirmed_at from auth.users where id=p_actor on conflict(id) do update set email=excluded.email,email_verified_at=excluded.email_verified_at;
  return (select to_jsonb(p) from manji_gateway.profiles p where id=p_actor);
 end if;
 select * into profile from manji_gateway.profiles where id=p_actor;
 if profile.id is null then raise exception 'UNAUTHENTICATED';end if;
 if p_command='session.open' then
  if exists(select 1 from manji_gateway.account_sessions where id=p_session and revoked_at is not null) then raise exception 'SESSION_REVOKED';end if;
  if profile.email_verified_at is null then raise exception 'EMAIL_UNVERIFIED';end if;
  if profile.status<>'ACTIVE' then raise exception 'ACCOUNT_SUSPENDED';end if;
  insert into manji_gateway.account_sessions(id,user_id,device_name,access_hash,refresh_hash,expires_at) values(p_session,p_actor,left(coalesce(p_data->>'device_name','Sesi pengguna'),80),p_data->>'access_hash',p_data->>'refresh_hash',now()+interval '30 days') on conflict(id) do update set access_hash=excluded.access_hash,refresh_hash=excluded.refresh_hash,last_seen_at=now() where account_sessions.user_id=p_actor and account_sessions.revoked_at is null;
  perform manji_gateway.audit(p_actor,null,'auth.session_opened',p_session);return to_jsonb(profile);
 end if;
 if not exists(select 1 from manji_gateway.account_sessions where id=p_session and user_id=p_actor and revoked_at is null and expires_at>now()) then raise exception 'SESSION_REVOKED';end if;
 if p_command='account.me' then return jsonb_build_object('profile',to_jsonb(profile),'applications',coalesce((select jsonb_agg(to_jsonb(a) order by created_at desc) from manji_gateway.merchant_applications a where user_id=p_actor),'[]'),'merchants',coalesce((select jsonb_agg(jsonb_build_object('merchant_id',m.id,'role',mm.member_role,'merchants',jsonb_build_object('name',m.name),'identifier',m.identifier,'status',m.status)) from manji_gateway.merchant_memberships mm join manji_gateway.merchants m on m.id=mm.merchant_id where mm.user_id=p_actor and profile.role='MERCHANT' and profile.status='ACTIVE'),'[]'));end if;
 if p_command='sessions.list' then return coalesce((select jsonb_agg(to_jsonb(s)-'access_hash'-'refresh_hash' order by created_at desc) from manji_gateway.account_sessions s where user_id=p_actor),'[]');end if;
 if p_command='sessions.revoke' then
  target=coalesce((p_data->>'id')::uuid,p_session);if not exists(select 1 from manji_gateway.account_sessions where id=target and (user_id=p_actor or profile.role='ADMIN')) then raise exception 'NOT_FOUND';end if;
  update manji_gateway.account_sessions set revoked_at=now() where id=target;
  update manji_gateway.merchant_devices set revoked_at=now() where session_id=target;
  update manji_gateway.device_credentials set revoked_at=now() where device_id in(select id from manji_gateway.merchant_devices where session_id=target);
  perform manji_gateway.audit(p_actor,null,'auth.session_revoked',target);return '{"ok":true}';
 end if;
 if profile.status<>'ACTIVE' then raise exception 'ACCOUNT_SUSPENDED';end if;
 if profile.email_verified_at is null then raise exception 'EMAIL_UNVERIFIED';end if;
 if p_command='applications.submit' then
  if profile.role<>'PENDING' then raise exception 'FORBIDDEN';end if;
  if not coalesce((select (value->>'registration_open')::boolean from manji_gateway.system_configuration where id),false) then raise exception 'REGISTRATION_CLOSED';end if;
  if exists(select 1 from manji_gateway.merchant_applications where user_id=p_actor and status='PENDING') then raise exception 'INVALID_STATE';end if;
  insert into manji_gateway.merchant_applications(user_id,business_name,business_description,phone) values(p_actor,p_data->>'business_name',p_data->>'business_description',p_data->>'phone') returning * into app;
  update manji_gateway.profiles set role='PENDING',updated_at=now() where id=p_actor;perform manji_gateway.audit(p_actor,null,'application.submitted',app.id);return to_jsonb(app);
 end if;
 if profile.role<>'ADMIN' then raise exception 'FORBIDDEN';end if;
 if p_command='admin.overview' then
  return jsonb_build_object('profiles',coalesce((select jsonb_agg(to_jsonb(p) order by created_at desc) from manji_gateway.profiles p),'[]'),'applications',coalesce((select jsonb_agg(to_jsonb(a) order by created_at desc) from manji_gateway.merchant_applications a),'[]'),'merchants',coalesce((select jsonb_agg(to_jsonb(m) order by created_at desc) from manji_gateway.merchants m),'[]'),
  'payments',coalesce((select jsonb_agg(to_jsonb(p)) from(select * from manji_gateway.payment_requests order by created_at desc limit 100)p),'[]'),'devices',coalesce((select jsonb_agg(to_jsonb(d)) from manji_gateway.merchant_devices d),'[]'),
  'signals',coalesce((select jsonb_agg(to_jsonb(s)) from(select * from manji_gateway.notification_signals order by received_at desc limit 100)s),'[]'),'audit',coalesce((select jsonb_agg(to_jsonb(a)) from(select * from manji_gateway.audit_logs order by occurred_at desc limit 100)a),'[]'),
  'security_events',coalesce((select jsonb_agg(to_jsonb(s)) from(select * from manji_gateway.security_events order by occurred_at desc limit 100)s),'[]'),'deliveries',coalesce((select jsonb_agg(to_jsonb(d)-'payload'-'lease_token') from(select * from manji_gateway.webhook_deliveries order by created_at desc limit 100)d),'[]'),
  'request_logs',coalesce((select jsonb_agg(to_jsonb(r)) from(select * from manji_gateway.api_request_logs order by occurred_at desc limit 100)r),'[]'),'api_keys',coalesce((select jsonb_agg(to_jsonb(k)-'secret_hash') from manji_gateway.merchant_api_keys k),'[]'),'configuration',(select value from manji_gateway.system_configuration where id));
 end if;
 if p_command='admin.application.review' then
  select * into app from manji_gateway.merchant_applications where id=(p_data->>'id')::uuid for update;if app.id is null then raise exception 'NOT_FOUND';end if;if app.status<>'PENDING' then raise exception 'ALREADY_REVIEWED';end if;
  action=p_data->>'action';if action not in ('approve','reject') then raise exception 'VALIDATION_ERROR';end if;
  if action='approve' then
   if not exists(select 1 from manji_gateway.profiles where id=app.user_id and email_verified_at is not null and status='ACTIVE' and role in ('PENDING','USER')) then raise exception 'INVALID_STATE';end if;
   insert into manji_gateway.merchants(identifier,name,owner_user_id,application_id) values('MG-'||replace(gen_random_uuid()::text,'-',''),app.business_name,app.user_id,app.id) returning * into merchant;
   insert into manji_gateway.merchant_memberships(merchant_id,user_id,member_role) values(merchant.id,app.user_id,'owner');update manji_gateway.profiles set role='MERCHANT',updated_at=now() where id=app.user_id;
  else update manji_gateway.profiles set role='USER',updated_at=now() where id=app.user_id and role='PENDING';end if;
  update manji_gateway.merchant_applications set status=case when action='approve' then 'APPROVED' else 'REJECTED' end,reviewed_by=p_actor,reviewed_at=now(),review_note=p_data->>'note' where id=app.id;
  perform manji_gateway.audit(p_actor,merchant.id,'application.'||action,app.id,jsonb_build_object('user_id',app.user_id));return jsonb_build_object('ok',true,'merchant_id',merchant.id);
 end if;
 if p_command='admin.account.status' then
  target=(p_data->>'id')::uuid;if target=p_actor then raise exception 'FORBIDDEN';end if;
  if p_data->>'status' not in ('ACTIVE','SUSPENDED') then raise exception 'VALIDATION_ERROR';end if;
  if not exists(select 1 from manji_gateway.profiles where id=target and role<>'ADMIN') then raise exception 'NOT_FOUND';end if;
  update manji_gateway.profiles set status=p_data->>'status',updated_at=now() where id=target;
  if p_data->>'status'='SUSPENDED' then update manji_gateway.account_sessions set revoked_at=now() where user_id=target;update manji_gateway.device_credentials set revoked_at=now() where user_id=target;end if;
  perform manji_gateway.audit(p_actor,null,'account.'||lower(p_data->>'status'),target);return '{"ok":true}';
 end if;
 if p_command='admin.merchant.status' then
  update manji_gateway.merchants set status=p_data->>'status' where id=(p_data->>'id')::uuid;if not found then raise exception 'NOT_FOUND';end if;perform manji_gateway.audit(p_actor,(p_data->>'id')::uuid,'merchant.'||lower(p_data->>'status'),(p_data->>'id')::uuid);return '{"ok":true}';
 end if;
 if p_command='admin.configuration' then update manji_gateway.system_configuration set value=p_data,updated_at=now() where id;perform manji_gateway.audit(p_actor,null,'configuration.updated',null);return '{"ok":true}';end if;
 if p_command='admin.key.revoke' then
  update manji_gateway.merchant_api_keys set revoked_at=now() where id=(p_data->>'id')::uuid returning merchant_id into target;if not found then raise exception 'NOT_FOUND';end if;perform manji_gateway.audit(p_actor,target,'admin.api_key.revoked',(p_data->>'id')::uuid);return '{"ok":true}';
 end if;
 if p_command='admin.device.revoke' then
  update manji_gateway.merchant_devices set revoked_at=now() where id=(p_data->>'id')::uuid returning merchant_id into target;if not found then raise exception 'NOT_FOUND';end if;update manji_gateway.device_credentials set revoked_at=now() where device_id=(p_data->>'id')::uuid;perform manji_gateway.audit(p_actor,target,'admin.device.revoked',(p_data->>'id')::uuid);return '{"ok":true}';
 end if;
 if p_command='admin.enrollment.create' then
  select * into merchant from manji_gateway.merchants where id=(p_data->>'merchant_id')::uuid and status='ACTIVE';if merchant.id is null then raise exception 'NOT_FOUND';end if;
  if not exists(select 1 from manji_gateway.profiles where id=merchant.owner_user_id and role='MERCHANT' and status='ACTIVE') then raise exception 'INVALID_STATE';end if;
  target=(p_data->>'id')::uuid;insert into manji_gateway.merchant_api_keys(id,merchant_id,created_by,public_id,name,layer,secret_hash,scopes,expires_at) values(target,merchant.id,merchant.owner_user_id,p_data->>'public_id','Enrollment oleh administrator','ENROLLMENT',p_data->>'secret_hash',array['devices:enroll'],now()+interval '15 minutes');
  perform manji_gateway.audit(p_actor,merchant.id,'admin.enrollment_credential.created',target);return jsonb_build_object('id',target,'public_id',p_data->>'public_id','secret_ciphertext',p_data->>'secret_ciphertext','expires_at',now()+interval '15 minutes');
 end if;
 raise exception 'NOT_FOUND';
end $$;

create function manji_gateway.lookup_credential(p_kind text,p_id uuid,p_hash text) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 if p_kind='api' then select to_jsonb(k)-'secret_hash' into result from manji_gateway.merchant_api_keys k where id=p_id and secret_hash=p_hash and revoked_at is null and expires_at>now();
 elsif p_kind='device' then select to_jsonb(c)-'secret_hash' into result from manji_gateway.device_credentials c join manji_gateway.merchant_devices d on d.id=c.device_id and d.merchant_id=c.merchant_id where c.id=p_id and c.secret_hash=p_hash and c.revoked_at is null and c.expires_at>now() and d.revoked_at is null;end if;
 if result is null then raise exception 'UNAUTHENTICATED';end if;return result;end $$;

create function manji_gateway.payment_json(p manji_gateway.payment_requests) returns jsonb language sql immutable as $$select to_jsonb(p)||jsonb_build_object('qr_display','/v1/qr-sources/'||p.qr_source_id||'/image','requires_manual_amount_entry',p.qr_mode='STATIC_QRIS');$$;
create function manji_gateway.merchant_command(p_actor uuid,p_session uuid,p_merchant uuid,p_kind text,p_subject uuid,p_command text,p_data jsonb,p_idempotency text default null,p_fingerprint text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare profile manji_gateway.profiles;merchant manji_gateway.merchants;keyrow manji_gateway.merchant_api_keys;device manji_gateway.merchant_devices;credential manji_gateway.device_credentials;
 payment manji_gateway.payment_requests;challenge manji_gateway.enrollment_challenges;qr manji_gateway.qr_sources;ep manji_gateway.webhook_endpoints;
 result jsonb;cached manji_gateway.idempotency_records;required_scope text;identifier uuid;old_status text;ids uuid[];n int;current_config jsonb;is_mutation boolean;
begin
 select * into profile from manji_gateway.profiles where id=p_actor;if profile.id is null then raise exception 'UNAUTHENTICATED';end if;
 if profile.status<>'ACTIVE' then raise exception 'ACCOUNT_SUSPENDED';end if;
 if profile.email_verified_at is null then raise exception 'EMAIL_UNVERIFIED';end if;
 if profile.role<>'MERCHANT' then raise exception 'MERCHANT_REQUIRED';end if;
 select * into merchant from manji_gateway.merchants where id=p_merchant for update;
 if merchant.id is null or not exists(select 1 from manji_gateway.merchant_memberships where merchant_id=p_merchant and user_id=p_actor) then raise exception 'NOT_FOUND';end if;
 if merchant.status<>'ACTIVE' then raise exception 'ACCOUNT_SUSPENDED';end if;
 select value into current_config from manji_gateway.system_configuration where id;
 required_scope=case when p_command in ('payments.create','payments.cancel') then 'payments:write' when p_command like 'webhooks.%' then 'webhooks:manage' when p_command in ('devices.enroll','devices.redeem') then 'devices:enroll' else 'payments:read' end;
 if p_kind='user' then
  if not exists(select 1 from manji_gateway.account_sessions where id=p_session and user_id=p_actor and revoked_at is null and expires_at>now()) then raise exception 'SESSION_REVOKED';end if;
 elsif p_kind='api' then
  select * into keyrow from manji_gateway.merchant_api_keys where id=p_subject and merchant_id=p_merchant and created_by=p_actor and revoked_at is null and expires_at>now();
  if keyrow.id is null or not(required_scope=any(keyrow.scopes)) or p_command not in ('payments.create','payments.list','payments.get','payments.status','payments.cancel','webhooks.list','webhooks.create','webhooks.revoke','webhooks.test','webhooks.rotate','devices.enroll','devices.redeem') then raise exception 'FORBIDDEN';end if;
  update manji_gateway.merchant_api_keys set last_used_at=now() where id=p_subject;
 elsif p_kind='device' then
  select * into credential from manji_gateway.device_credentials where id=p_subject and merchant_id=p_merchant and user_id=p_actor and revoked_at is null and expires_at>now();
  select * into device from manji_gateway.merchant_devices where id=credential.device_id and merchant_id=p_merchant and revoked_at is null;
  if credential.id is null or device.id is null then raise exception 'DEVICE_EXPIRED';end if;
  if p_command not in ('signals.create','devices.status','payments.create','payments.get','payments.status','payments.list','qr.image') then raise exception 'FORBIDDEN';end if;
 else raise exception 'FORBIDDEN';end if;
 is_mutation=p_command in ('payments.create','payments.cancel','signals.create','devices.enroll','devices.redeem','devices.revoke','devices.rotate','qr.create','keys.create','keys.revoke','keys.rotate','webhooks.create','webhooks.revoke','webhooks.rotate','webhooks.test','privacy.delete_signals');
 if is_mutation then
  if p_idempotency is null or p_idempotency!~'^[A-Za-z0-9_.-]{8,128}$' then raise exception 'VALIDATION_ERROR';end if;
  select * into cached from manji_gateway.idempotency_records where actor_id=p_actor and subject=coalesce(p_subject::text,p_session::text) and operation=p_command and key=p_idempotency;
  if cached.actor_id is not null then if cached.fingerprint<>p_fingerprint then raise exception 'IDEMPOTENCY_CONFLICT';end if;return cached.response;end if;
 end if;
 -- Expiry cannot erase a late signed-provider reconciliation review.
 for payment in select * from manji_gateway.payment_requests where merchant_id=p_merchant and status in ('CREATED','PENDING','PAYMENT_DETECTED','REVIEW_REQUIRED') and expires_at<=now() and not(status='REVIEW_REQUIRED' and exists(select 1 from manji_gateway.payment_verifications v where v.payment_id=payment_requests.id)) loop
  update manji_gateway.payment_requests set status='EXPIRED',updated_at=now() where id=payment.id;insert into manji_gateway.payment_events(merchant_id,payment_id,from_status,to_status,source) values(p_merchant,payment.id,payment.status,'EXPIRED','server.expiry');
 end loop;
 if p_command='merchant.profile' then result=to_jsonb(merchant)||jsonb_build_object('profile',to_jsonb(profile),'allowed_sources',coalesce(current_config->'notification_sources','[]'),'max_amount_idr',current_config->'max_amount_idr');
 elsif p_command='payments.create' then
  if p_data->>'qr_mode'<>'STATIC_QRIS' then raise exception 'INVALID_STATE';end if;
  if (p_data->>'amount_idr')::bigint not between 1 and least((current_config->>'max_amount_idr')::bigint,10000000) then raise exception 'VALIDATION_ERROR';end if;
  select * into qr from manji_gateway.qr_sources where merchant_id=p_merchant order by created_at desc limit 1;if qr.id is null then raise exception 'QR_REQUIRED';end if;
  if p_data->>'external_reference' is not null and exists(select 1 from manji_gateway.payment_requests where merchant_id=p_merchant and external_reference=p_data->>'external_reference') then raise exception 'DUPLICATE_REFERENCE';end if;
  insert into manji_gateway.payment_requests(merchant_id,public_reference,external_reference,amount_idr,qr_source_id,environment,expires_at) values(p_merchant,'MANJI-'||replace(gen_random_uuid()::text,'-',''),p_data->>'external_reference',(p_data->>'amount_idr')::bigint,qr.id,p_data->>'environment',now()+interval '15 minutes') returning * into payment;
  insert into manji_gateway.payment_events(merchant_id,payment_id,from_status,to_status,source,actor_id) values(p_merchant,payment.id,null,'CREATED','server',p_actor),(p_merchant,payment.id,'CREATED','PENDING','server',p_actor);
  update manji_gateway.payment_requests set status='PENDING' where id=payment.id returning * into payment;perform manji_gateway.audit(p_actor,p_merchant,'payment.created',payment.id);result=manji_gateway.payment_json(payment);
 elsif p_command='payments.list' then
  if p_data->>'cursor' is not null and not exists(select 1 from manji_gateway.payment_requests where id=(p_data->>'cursor')::uuid and merchant_id=p_merchant) then raise exception 'NOT_FOUND';end if;
  select coalesce(jsonb_agg(manji_gateway.payment_json(x) order by x.created_at desc,x.id desc),'[]') into result from(select * from manji_gateway.payment_requests p where merchant_id=p_merchant and (p_data->>'status' is null or status=p_data->>'status') and (coalesce(p_data->>'q','')='' or position(lower(p_data->>'q') in lower(public_reference||coalesce(external_reference,'')))>0) and (p_data->>'cursor' is null or (p.created_at,p.id)<(select c.created_at,c.id from manji_gateway.payment_requests c where c.id=(p_data->>'cursor')::uuid)) order by created_at desc,id desc limit least(coalesce((p_data->>'limit')::int,25),100))x;
  result=jsonb_build_object('data',result,'next_cursor',case when jsonb_array_length(result)=least(coalesce((p_data->>'limit')::int,25),100) then result->-1->>'id' else null end);
 elsif p_command in ('payments.get','payments.status','payments.cancel') then
  select * into payment from manji_gateway.payment_requests where id=(p_data->>'id')::uuid and merchant_id=p_merchant;if payment.id is null then raise exception 'NOT_FOUND';end if;
  if p_command='payments.cancel' then
   if payment.status not in ('PENDING','CREATED','PAYMENT_DETECTED','REVIEW_REQUIRED') then raise exception 'INVALID_STATE';end if;old_status=payment.status;
   update manji_gateway.payment_requests set status='FAILED',failure_reason='merchant_canceled',updated_at=now() where id=payment.id returning * into payment;
   insert into manji_gateway.payment_events(merchant_id,payment_id,from_status,to_status,source,actor_id) values(p_merchant,payment.id,old_status,'FAILED','merchant.cancel',p_actor);perform manji_gateway.audit(p_actor,p_merchant,'payment.canceled',payment.id);
  end if;
  result=manji_gateway.payment_json(payment)||jsonb_build_object('events',coalesce((select jsonb_agg(to_jsonb(e) order by occurred_at) from manji_gateway.payment_events e where payment_id=payment.id),'[]'));
 elsif p_command='qr.create' then
  identifier=(p_data->>'id')::uuid;insert into manji_gateway.qr_sources(id,merchant_id,mime,bytes_base64,sha256) values(identifier,p_merchant,p_data->>'mime',p_data->>'bytes_base64',p_data->>'sha256');perform manji_gateway.audit(p_actor,p_merchant,'qr.registered',identifier);result=jsonb_build_object('id',identifier,'sha256',p_data->>'sha256','image','/v1/qr-sources/'||identifier||'/image');
 elsif p_command='qr.image' then
  select * into qr from manji_gateway.qr_sources where id=(p_data->>'id')::uuid and merchant_id=p_merchant;if qr.id is null then raise exception 'NOT_FOUND';end if;result=to_jsonb(qr);
 elsif p_command='devices.enroll' then
  if exists(select 1 from jsonb_array_elements_text(p_data->'allowed_packages') pkg where not exists(select 1 from jsonb_array_elements(current_config->'notification_sources') src where src->>'package_name'=pkg)) then raise exception 'SOURCE_NOT_ALLOWED';end if;
  identifier=(p_data->>'id')::uuid;insert into manji_gateway.enrollment_challenges(id,merchant_id,actor_id,subject_id,kind,name,allowed_packages,secret_hash,expires_at) values(identifier,p_merchant,p_actor,p_subject,p_kind,p_data->>'name',array(select jsonb_array_elements_text(p_data->'allowed_packages')),p_data->>'secret_hash',now()+interval '5 minutes');
  perform manji_gateway.audit(p_actor,p_merchant,'device.enrollment_started',identifier);result=jsonb_build_object('challenge_id',identifier,'secret_ciphertext',p_data->>'secret_ciphertext','expires_at',now()+interval '5 minutes');
 elsif p_command='devices.redeem' then
  select * into challenge from manji_gateway.enrollment_challenges where id=(p_data->>'challenge_id')::uuid and merchant_id=p_merchant and actor_id=p_actor and kind=p_kind and subject_id is not distinct from p_subject and secret_hash=p_data->>'challenge_hash' and consumed_at is null and expires_at>now() for update;
  if challenge.id is null then raise exception 'INVALID_CHALLENGE';end if;update manji_gateway.enrollment_challenges set consumed_at=now() where id=challenge.id;
  insert into manji_gateway.merchant_devices(merchant_id,user_id,session_id,name,allowed_packages,consented_at) values(p_merchant,p_actor,p_session,challenge.name,challenge.allowed_packages,now()) returning * into device;
  identifier=(p_data->>'id')::uuid;insert into manji_gateway.device_credentials(id,merchant_id,device_id,user_id,secret_hash,expires_at) values(identifier,p_merchant,device.id,p_actor,p_data->>'secret_hash',now()+interval '15 minutes');
  perform manji_gateway.audit(p_actor,p_merchant,'device.enrolled',device.id);result=jsonb_build_object('device_id',device.id,'merchant_id',p_merchant,'credential_id',identifier,'secret_ciphertext',p_data->>'secret_ciphertext','expires_at',now()+interval '15 minutes','allowed_packages',to_jsonb(device.allowed_packages));
 elsif p_command in ('devices.list','devices.status') then
  result=coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('expires_at',(select max(expires_at) from manji_gateway.device_credentials c where c.device_id=d.id and c.revoked_at is null))) from manji_gateway.merchant_devices d where merchant_id=p_merchant and (p_kind<>'device' or d.id=device.id)),'[]');
 elsif p_command in ('devices.revoke','devices.rotate') then
  select * into device from manji_gateway.merchant_devices where id=(p_data->>'id')::uuid and merchant_id=p_merchant and revoked_at is null;if device.id is null then raise exception 'NOT_FOUND';end if;
  update manji_gateway.device_credentials set revoked_at=now() where device_id=device.id and revoked_at is null;
  if p_command='devices.revoke' then update manji_gateway.merchant_devices set revoked_at=now() where id=device.id;result='{"ok":true}';
  else identifier=(p_data->>'credential_id')::uuid;insert into manji_gateway.device_credentials(id,merchant_id,device_id,user_id,secret_hash,expires_at) values(identifier,p_merchant,device.id,p_actor,p_data->>'secret_hash',now()+interval '15 minutes');result=jsonb_build_object('device_id',device.id,'credential_id',identifier,'secret_ciphertext',p_data->>'secret_ciphertext','expires_at',now()+interval '15 minutes','allowed_packages',to_jsonb(device.allowed_packages));end if;
  perform manji_gateway.audit(p_actor,p_merchant,p_command,device.id);
 elsif p_command='signals.create' then
  if p_kind<>'device' or (p_data->>'device_id')::uuid<>device.id then raise exception 'FORBIDDEN';end if;
  if not(p_data->>'source_package'=any(device.allowed_packages)) or not exists(select 1 from jsonb_array_elements(current_config->'notification_sources')src where src->>'package_name'=p_data->>'source_package') then raise exception 'SOURCE_NOT_ALLOWED';end if;
  if (p_data->>'posted_at')::timestamptz<now()-interval '24 hours' or (p_data->>'posted_at')::timestamptz>now()+interval '30 seconds' then raise exception 'VALIDATION_ERROR';end if;
  select jsonb_build_object('accepted',true,'classification','UNTRUSTED','candidate_payment_intent_ids',to_jsonb(s.candidates),'ambiguous',s.ambiguous) into result from manji_gateway.notification_signals s where merchant_id=p_merchant and dedup_hash=p_data->>'dedup_hash';
  if result is null then
   select coalesce(array_agg(id),'{}') into ids from manji_gateway.payment_requests where merchant_id=p_merchant and status in ('PENDING','PAYMENT_DETECTED','REVIEW_REQUIRED') and amount_idr=(p_data->>'amount_idr')::bigint and created_at<=(p_data->>'posted_at')::timestamptz+interval '30 seconds' and expires_at>=(p_data->>'posted_at')::timestamptz;
   n=cardinality(ids);insert into manji_gateway.notification_signals(id,merchant_id,device_id,source_package,amount_idr,posted_at,dedup_hash,candidates,ambiguous) values((p_data->>'signal_id')::uuid,p_merchant,device.id,p_data->>'source_package',(p_data->>'amount_idr')::bigint,(p_data->>'posted_at')::timestamptz,p_data->>'dedup_hash',ids,n>1);
   for payment in select * from manji_gateway.payment_requests where id=any(ids) loop
    old_status=case when n>1 or payment.status='REVIEW_REQUIRED' then 'REVIEW_REQUIRED' else 'PAYMENT_DETECTED' end;
    update manji_gateway.payment_requests set status=old_status,updated_at=now() where id=payment.id;insert into manji_gateway.payment_events(merchant_id,payment_id,from_status,to_status,source,actor_id) values(p_merchant,payment.id,payment.status,old_status,'UNTRUSTED_NOTIFICATION',p_actor);
   end loop;
   update manji_gateway.merchant_devices set last_seen_at=now() where id=device.id;perform manji_gateway.audit(p_actor,p_merchant,'notification.untrusted',(p_data->>'signal_id')::uuid);
   result=jsonb_build_object('accepted',true,'classification','UNTRUSTED','candidate_payment_intent_ids',to_jsonb(ids),'ambiguous',n>1);perform manji_gateway.emit(p_merchant,case when n>1 then 'payment.review_required' else 'payment.detected' end,p_data->>'environment',result);
  end if;
 elsif p_command='keys.create' then
  identifier=(p_data->>'id')::uuid;insert into manji_gateway.merchant_api_keys(id,merchant_id,created_by,public_id,name,layer,secret_hash,scopes,expires_at) values(identifier,p_merchant,p_actor,p_data->>'public_id',p_data->>'name',p_data->>'layer',p_data->>'secret_hash',array(select jsonb_array_elements_text(p_data->'scopes')),now()+make_interval(days=>(p_data->>'expires_in_days')::int));
  perform manji_gateway.audit(p_actor,p_merchant,'api_key.created',identifier);result=jsonb_build_object('id',identifier,'public_id',p_data->>'public_id','secret_ciphertext',p_data->>'secret_ciphertext');
 elsif p_command='keys.list' then result=coalesce((select jsonb_agg(to_jsonb(k)-'secret_hash' order by created_at desc) from manji_gateway.merchant_api_keys k where merchant_id=p_merchant),'[]');
 elsif p_command in ('keys.revoke','keys.rotate') then
  select * into keyrow from manji_gateway.merchant_api_keys where id=(p_data->>'id')::uuid and merchant_id=p_merchant;if keyrow.id is null then raise exception 'NOT_FOUND';end if;update manji_gateway.merchant_api_keys set revoked_at=now() where id=keyrow.id;
  result='{"ok":true}';if p_command='keys.rotate' then
   identifier=(p_data->>'new_id')::uuid;insert into manji_gateway.merchant_api_keys(id,merchant_id,created_by,public_id,name,layer,secret_hash,scopes,expires_at) values(identifier,p_merchant,p_actor,p_data->>'public_id',keyrow.name,keyrow.layer,p_data->>'secret_hash',keyrow.scopes,now()+interval '30 days');result=jsonb_build_object('id',identifier,'public_id',p_data->>'public_id','secret_ciphertext',p_data->>'secret_ciphertext');
  end if;perform manji_gateway.audit(p_actor,p_merchant,p_command,keyrow.id);
 elsif p_command in ('webhooks.create','webhooks.rotate') then
  identifier=(p_data->>'id')::uuid;
  if p_command='webhooks.create' then insert into manji_gateway.webhook_endpoints(id,merchant_id,url,secret_encrypted,challenge) values(identifier,p_merchant,p_data->>'url',p_data->>'secret_ciphertext',p_data->>'challenge');
  else update manji_gateway.webhook_endpoints set active=false,revoked_at=null,secret_encrypted=p_data->>'secret_ciphertext',challenge=p_data->>'challenge' where id=identifier and merchant_id=p_merchant;if not found then raise exception 'NOT_FOUND';end if;update manji_gateway.webhook_deliveries set dead=true where endpoint_id=identifier and delivered_at is null;end if;
  insert into manji_gateway.webhook_deliveries(merchant_id,endpoint_id,event_type,environment,payload) values(p_merchant,identifier,'endpoint.verification',p_data->>'environment',jsonb_build_object('challenge',p_data->>'challenge'));
  perform manji_gateway.audit(p_actor,p_merchant,p_command,identifier);result=jsonb_build_object('id',identifier,'active',false,'secret_ciphertext',p_data->>'secret_ciphertext');
 elsif p_command='webhooks.list' then result=coalesce((select jsonb_agg(to_jsonb(e)-'secret_encrypted'-'challenge' order by created_at desc) from manji_gateway.webhook_endpoints e where merchant_id=p_merchant),'[]');
 elsif p_command in ('webhooks.revoke','webhooks.test') then
  select * into ep from manji_gateway.webhook_endpoints where id=(p_data->>'id')::uuid and merchant_id=p_merchant;if ep.id is null then raise exception 'NOT_FOUND';end if;
  if p_command='webhooks.revoke' then update manji_gateway.webhook_endpoints set active=false,revoked_at=now() where id=ep.id;update manji_gateway.webhook_deliveries set dead=true where endpoint_id=ep.id and delivered_at is null;
  else if not ep.active or ep.revoked_at is not null then raise exception 'INVALID_STATE';end if;insert into manji_gateway.webhook_deliveries(merchant_id,endpoint_id,event_type,environment,payload) values(p_merchant,ep.id,'endpoint.test',p_data->>'environment','{"test":true,"financial":false}');end if;
  perform manji_gateway.audit(p_actor,p_merchant,p_command,ep.id);result='{"ok":true}';
 elsif p_command='privacy.delete_signals' then delete from manji_gateway.notification_signals where merchant_id=p_merchant;perform manji_gateway.audit(p_actor,p_merchant,'privacy.signals_deleted',p_merchant);result='{"ok":true}';
 elsif p_command='dashboard' then
  result=jsonb_build_object('merchant',to_jsonb(merchant),'role',profile.role,'environment',p_data->>'environment','provider_enabled',false,
  'intents',coalesce((select jsonb_agg(manji_gateway.payment_json(p)) from(select * from manji_gateway.payment_requests where merchant_id=p_merchant order by created_at desc limit 100)p),'[]'),
  'signals',coalesce((select jsonb_agg(to_jsonb(s)) from(select * from manji_gateway.notification_signals where merchant_id=p_merchant order by received_at desc limit 100)s),'[]'),
  'devices',coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('expires_at',(select max(expires_at) from manji_gateway.device_credentials c where c.device_id=d.id and c.revoked_at is null))) from manji_gateway.merchant_devices d where merchant_id=p_merchant),'[]'),
  'qr_sources',coalesce((select jsonb_agg(to_jsonb(q)-'bytes_base64'||jsonb_build_object('image','/v1/qr-sources/'||q.id||'/image') order by created_at) from manji_gateway.qr_sources q where merchant_id=p_merchant),'[]'),
  'verified_total_idr',coalesce((select sum(amount_idr) from manji_gateway.payment_requests where merchant_id=p_merchant and status='PAID'),0),
  'api_keys',coalesce((select jsonb_agg(to_jsonb(k)-'secret_hash') from manji_gateway.merchant_api_keys k where merchant_id=p_merchant),'[]'),
  'endpoints',coalesce((select jsonb_agg(to_jsonb(e)-'secret_encrypted'-'challenge') from manji_gateway.webhook_endpoints e where merchant_id=p_merchant),'[]'),
  'audit',coalesce((select jsonb_agg(to_jsonb(a)) from(select * from manji_gateway.audit_logs where merchant_id=p_merchant order by occurred_at desc limit 100)a),'[]'),
  'deliveries',coalesce((select jsonb_agg(to_jsonb(d)-'payload'-'lease_token') from(select * from manji_gateway.webhook_deliveries where merchant_id=p_merchant order by created_at desc limit 100)d),'[]'),
  'request_logs',coalesce((select jsonb_agg(to_jsonb(l)) from(select * from manji_gateway.api_request_logs where merchant_id=p_merchant order by occurred_at desc limit 100)l),'[]'));
 else raise exception 'NOT_FOUND';end if;
 if is_mutation then insert into manji_gateway.idempotency_records(actor_id,subject,operation,key,fingerprint,response) values(p_actor,coalesce(p_subject::text,p_session::text),p_command,p_idempotency,p_fingerprint,case when result?'secret_ciphertext' then (result-'secret_ciphertext')||'{"secret_already_issued":true}'::jsonb else result end);end if;
 return result;
end $$;

revoke all on all functions in schema manji_gateway from public,anon,authenticated;
grant execute on function manji_gateway.current_account_active(),manji_gateway.is_admin(),manji_gateway.can_access_merchant(uuid) to authenticated;
grant execute on all functions in schema manji_gateway to service_role;

commit;
-- END SOURCE: 202611020002_manji_commands.sql

-- BEGIN SOURCE: 202611020003_manji_provider_worker.sql
-- SOURCE SHA256: 00392ed23f8fbd380abef7d9f27e8032468f501a3f4790a7a48a8124e806e726
begin;

create function manji_gateway.provider_event(p_event jsonb,p_fingerprint text,p_environment text) returns jsonb language plpgsql security definer set search_path='' as $$
declare payment manji_gateway.payment_requests;previous manji_gateway.payment_verifications;next_status text;late boolean;event_name text;
begin
 if p_event->>'environment'<>p_environment or (p_event->>'provider'='mock')<>(p_environment='sandbox') then raise exception 'PAYMENT_MISMATCH';end if;
 perform 1 from manji_gateway.merchants where id=(p_event->>'merchant_id')::uuid for update;
 select * into previous from manji_gateway.payment_verifications where provider=p_event->>'provider' and event_id=p_event->>'event_id';
 if previous.id is not null then if previous.fingerprint<>p_fingerprint then raise exception 'EVENT_CONFLICT';end if;return '{"accepted":true,"duplicate":true}';end if;
 select * into payment from manji_gateway.payment_requests where id=(p_event->>'payment_id')::uuid and merchant_id=(p_event->>'merchant_id')::uuid for update;
 if payment.id is null or payment.environment<>p_environment or payment.amount_idr<>(p_event->>'amount_idr')::bigint or payment.currency<>p_event->>'currency' then raise exception 'PAYMENT_MISMATCH';end if;
 select * into previous from manji_gateway.payment_verifications where provider=p_event->>'provider' and transaction_id=p_event->>'transaction_id' and event_type=p_event->>'event_type';
 if previous.id is not null then if previous.payment_id<>payment.id or previous.amount_idr<>payment.amount_idr then raise exception 'EVENT_CONFLICT';end if;return '{"accepted":true,"duplicate":true}';end if;
 if p_event->>'event_type'='settlement' and payment.status in ('PAID','REFUNDED','SIMULATED_PAID') then raise exception 'INVALID_STATE';end if;
 if p_event->>'event_type'='refund' and (payment.status not in ('PAID','SIMULATED_PAID') or payment.provider_transaction_id<>p_event->>'transaction_id') then raise exception 'INVALID_STATE';end if;
 insert into manji_gateway.payment_verifications(merchant_id,payment_id,provider,event_id,transaction_id,amount_idr,currency,environment,event_type,signature_verified,fingerprint) values(payment.merchant_id,payment.id,p_event->>'provider',p_event->>'event_id',p_event->>'transaction_id',payment.amount_idr,payment.currency,p_environment,p_event->>'event_type',true,p_fingerprint);
 late=p_event->>'event_type'='settlement' and (payment.status in ('FAILED','EXPIRED') or payment.expires_at<=now());
 if late then next_status='REVIEW_REQUIRED';event_name='payment.review_required';
 elsif p_environment='sandbox' then next_status=case when p_event->>'event_type'='refund' then 'REVIEW_REQUIRED' else 'SIMULATED_PAID' end;event_name=case when p_event->>'event_type'='refund' then 'payment.simulated_refund' else 'payment.simulated' end;
 elsif p_event->>'event_type'='refund' then next_status='REFUNDED';event_name='payment.refunded';
 else
  insert into manji_gateway.payment_events(merchant_id,payment_id,from_status,to_status,source) values(payment.merchant_id,payment.id,payment.status,'VERIFYING','verified_provider');
  update manji_gateway.payment_requests set status='VERIFYING',updated_at=now() where id=payment.id;
  next_status='PAID';event_name='payment.verified';
 end if;
 update manji_gateway.payment_requests set status=next_status,updated_at=now(),provider_transaction_id=case when not late then p_event->>'transaction_id' else provider_transaction_id end,
 verification_source=case when next_status='PAID' then p_event->>'provider' else verification_source end,verified_at=case when next_status='PAID' then now() else verified_at end,failure_reason=case when late then 'late_provider_confirmation' else failure_reason end where id=payment.id;
 insert into manji_gateway.payment_events(merchant_id,payment_id,from_status,to_status,source) values(payment.merchant_id,payment.id,case when next_status='PAID' then 'VERIFYING' else payment.status end,next_status,case when p_environment='sandbox' then 'sandbox_provider' else 'verified_provider' end);
 perform manji_gateway.audit(null,payment.merchant_id,event_name,payment.id);perform manji_gateway.emit(payment.merchant_id,event_name,p_environment,jsonb_build_object('payment_id',payment.id,'status',next_status,'amount_idr',payment.amount_idr,'environment',p_environment));
 return jsonb_build_object('accepted',true,'duplicate',false,'status',next_status);
end $$;

create function manji_gateway.worker_command(p_command text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare delivery manji_gateway.webhook_deliveries;endpoint manji_gateway.webhook_endpoints;lease uuid;retention int;
begin
 if p_command='outbox.claim' then
  select * into delivery from manji_gateway.webhook_deliveries where delivered_at is null and not dead and next_attempt_at<=now() and (lease_until is null or lease_until<=now()) order by created_at for update skip locked limit 1;
  if delivery.id is null then return null;end if;
  select * into endpoint from manji_gateway.webhook_endpoints where id=delivery.endpoint_id;
  if endpoint.revoked_at is not null or (not endpoint.active and delivery.event_type<>'endpoint.verification') then update manji_gateway.webhook_deliveries set dead=true where id=delivery.id;return null;end if;
  lease=gen_random_uuid();update manji_gateway.webhook_deliveries set lease_token=lease,lease_until=now()+interval '1 minute',attempt_count=attempt_count+1 where id=delivery.id returning * into delivery;
  return jsonb_build_object('delivery',to_jsonb(delivery),'endpoint',to_jsonb(endpoint));
 elsif p_command='outbox.finish' then
  select * into delivery from manji_gateway.webhook_deliveries where id=(p_data->>'id')::uuid and lease_token=(p_data->>'lease_token')::uuid and not dead and delivered_at is null and lease_until>now() for update;if delivery.id is null then return '{"ok":false}';end if;
  update manji_gateway.webhook_deliveries set lease_until=null,lease_token=null,last_status=(p_data->>'status')::int,delivered_at=case when (p_data->>'ok')::boolean then now() else null end,dead=not(p_data->>'ok')::boolean and attempt_count>=8,next_attempt_at=now()+make_interval(secs=>least(3600,power(2,attempt_count)::int*10)) where id=delivery.id;
  if (p_data->>'ok')::boolean and delivery.event_type='endpoint.verification' then update manji_gateway.webhook_endpoints set active=true where id=delivery.endpoint_id and revoked_at is null;end if;
  perform manji_gateway.audit(null,delivery.merchant_id,case when (p_data->>'ok')::boolean then 'webhook.delivered' when delivery.attempt_count>=8 then 'webhook.dead_letter' else 'webhook.retry' end,delivery.id);return '{"ok":true}';
 elsif p_command='retention' then
  select (value->>'signal_retention_days')::int into retention from manji_gateway.system_configuration where id;
  delete from manji_gateway.notification_signals where received_at<now()-make_interval(days=>retention);
  delete from manji_gateway.idempotency_records where created_at<now()-interval '1 day';delete from manji_gateway.enrollment_challenges where expires_at<now()-interval '1 day';delete from manji_gateway.rate_limits where expires_at<now()-interval '1 day';return '{"ok":true}';
 elsif p_command='request.log' then
  insert into manji_gateway.api_request_logs(merchant_id,actor_id,credential_id,request_id,operation,method,status_code,duration_ms) values((p_data->>'merchant_id')::uuid,(p_data->>'actor_id')::uuid,(p_data->>'credential_id')::uuid,(p_data->>'request_id')::uuid,left(p_data->>'operation',100),p_data->>'method',(p_data->>'status_code')::int,(p_data->>'duration_ms')::int);
  if (p_data->>'status_code')::int in (401,403,409,429) then insert into manji_gateway.security_events(merchant_id,actor_id,code,request_id) values((p_data->>'merchant_id')::uuid,(p_data->>'actor_id')::uuid,p_data->>'code',(p_data->>'request_id')::uuid);end if;return '{"ok":true}';
 end if;raise exception 'NOT_FOUND';
end $$;
revoke all on function manji_gateway.provider_event(jsonb,text,text),manji_gateway.worker_command(text,jsonb) from public,anon,authenticated;
grant execute on function manji_gateway.provider_event(jsonb,text,text),manji_gateway.worker_command(text,jsonb) to service_role;

commit;
-- END SOURCE: 202611020003_manji_provider_worker.sql

-- BEGIN SOURCE: 202611020004_manji_account_idempotency.sql
-- SOURCE SHA256: 810488431e3c92f604852ebe333ca768a93e8d6b92690fd3ce8b733984547fae
begin;

create function manji_gateway.account_mutation(p_actor uuid,p_session uuid,p_command text,p_data jsonb,p_idempotency text,p_fingerprint text) returns jsonb language plpgsql security definer set search_path='' as $$declare previous manji_gateway.idempotency_records;result jsonb;begin
 if p_idempotency is null or p_idempotency!~'^[A-Za-z0-9_.-]{8,128}$' then raise exception 'VALIDATION_ERROR';end if;
 if not exists(select 1 from manji_gateway.account_sessions where id=p_session and user_id=p_actor and revoked_at is null and expires_at>now()) then raise exception 'SESSION_REVOKED';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_actor::text||p_session::text||p_command||p_idempotency,0));
 select * into previous from manji_gateway.idempotency_records where actor_id=p_actor and subject=p_session::text and operation=p_command and key=p_idempotency;
 if previous.actor_id is not null then if previous.fingerprint<>p_fingerprint then raise exception 'IDEMPOTENCY_CONFLICT';end if;return previous.response;end if;
 result=manji_gateway.account_command(p_actor,p_session,p_command,p_data);
 insert into manji_gateway.idempotency_records(actor_id,subject,operation,key,fingerprint,response) values(p_actor,p_session::text,p_command,p_idempotency,p_fingerprint,case when result?'secret_ciphertext' then (result-'secret_ciphertext')||'{"secret_already_issued":true}'::jsonb else result end);return result;
end $$;
revoke all on function manji_gateway.account_mutation(uuid,uuid,text,jsonb,text,text) from public,anon,authenticated;
grant execute on function manji_gateway.account_mutation(uuid,uuid,text,jsonb,text,text) to service_role;

commit;
-- END SOURCE: 202611020004_manji_account_idempotency.sql

-- BEGIN SOURCE: 202611020005_app_distribution.sql
-- SOURCE SHA256: 1a2d6512c7d818aa426ed7f8fa1f2ac30695ca3f70538a429e3aacb45c069f1c
begin;

-- Additive Android distribution only. No changes to payment authorization or existing buckets.
create table manji_gateway.app_releases (
 id uuid primary key,channel text not null check(channel in ('stable','beta')),profile text not null check(profile in ('production','test')),
 version_code integer not null check(version_code between 1 and 2100000000),sha256 text not null check(sha256~'^[a-f0-9]{64}$'),
 manifest jsonb not null,published_at timestamptz not null default now(),revoked_at timestamptz,
 unique(channel,profile,version_code),check((manifest->>'id')::uuid=id),check((manifest->>'version_code')::int=version_code),check(manifest->>'sha256'=sha256),check(manifest->>'application_id'='id.biz.manjifood.gateway'),
 check(manifest->>'profile'=profile),check(manifest->>'channel'=channel),
 check(coalesce(profile<>'production' or (manifest->'checks'='{"build":true,"unit_tests":true,"lint":true,"signature":true,"integrity":true,"installation":true}'::jsonb and jsonb_array_length(manifest->'screenshots')>0),false))
);
alter table manji_gateway.app_releases enable row level security;
revoke all on manji_gateway.app_releases from public,anon,authenticated;
grant select,insert,update on manji_gateway.app_releases to service_role;
create function manji_gateway.guard_app_release() returns trigger language plpgsql set search_path='' as $$begin
 if new.id<>old.id or new.manifest<>old.manifest or new.channel<>old.channel or new.profile<>old.profile or new.version_code<>old.version_code or new.sha256<>old.sha256 or new.published_at<>old.published_at or old.revoked_at is not null then raise exception 'IMMUTABLE_RELEASE';end if;return new;end $$;
create trigger immutable_app_release before update on manji_gateway.app_releases for each row execute function manji_gateway.guard_app_release();
create function manji_gateway.app_release_command(p_command text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare existing manji_gateway.app_releases;item jsonb;begin
 if p_command='list' then return coalesce((select jsonb_agg(x.manifest order by x.version_code desc) from(select manifest,version_code from manji_gateway.app_releases where channel=p_data->>'channel' and profile=coalesce(p_data->>'profile','production') and revoked_at is null order by version_code desc limit 30)x),'[]');
 elsif p_command='get' then return (select manifest from manji_gateway.app_releases where id=(p_data->>'id')::uuid and profile=coalesce(p_data->>'profile','production') and revoked_at is null);
 elsif p_command='publish' then
  item=p_data->'manifest';if item->>'application_id'<>'id.biz.manjifood.gateway' or (item->>'size_bytes')::bigint not between 1 and 83886080 or item->>'profile' not in ('production','test') then raise exception 'INVALID_RELEASE';end if;
  perform pg_advisory_xact_lock(hashtextextended('manji-app-release:'||(item->>'channel')||':'||(item->>'profile'),0));
  select * into existing from manji_gateway.app_releases where channel=item->>'channel' and profile=item->>'profile' and version_code=(item->>'version_code')::int;
  if existing.id is not null then if existing.manifest<>item or existing.revoked_at is not null then raise exception 'RELEASE_CONFLICT';end if;return existing.manifest;end if;
  if exists(select 1 from manji_gateway.app_releases where channel=item->>'channel' and profile=item->>'profile' and version_code>=(item->>'version_code')::int) then raise exception 'RELEASE_DOWNGRADE';end if;
  insert into manji_gateway.app_releases(id,channel,profile,version_code,sha256,manifest) values((item->>'id')::uuid,item->>'channel',item->>'profile',(item->>'version_code')::int,item->>'sha256',item);
  insert into manji_gateway.audit_logs(action,resource_id,details) values('app.release.published',(item->>'id')::uuid,jsonb_build_object('channel',item->>'channel','version_code',item->'version_code','sha256',item->>'sha256','profile',item->>'profile'));return item;
 elsif p_command='revoke' then
  update manji_gateway.app_releases set revoked_at=now() where id=(p_data->>'id')::uuid and revoked_at is null returning * into existing;if existing.id is null then raise exception 'NOT_FOUND';end if;
  insert into manji_gateway.audit_logs(action,resource_id) values('app.release.revoked',existing.id);return '{"ok":true}';
 end if;raise exception 'NOT_FOUND';end $$;
revoke all on function manji_gateway.guard_app_release(),manji_gateway.app_release_command(text,jsonb) from public,anon,authenticated;
grant execute on function manji_gateway.app_release_command(text,jsonb) to service_role;
do $$begin
 if to_regclass('storage.buckets') is not null then
  if exists(select 1 from storage.buckets where id='manji-app-releases') then raise exception 'RELEASE_BUCKET_NAME_ALREADY_EXISTS_REVIEW_REQUIRED';end if;
  insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('manji-app-releases','manji-app-releases',false,83886080,array['application/vnd.android.package-archive','image/png','image/jpeg']) on conflict(id) do nothing;
  execute 'create policy manji_private_release_artifacts on storage.objects as restrictive for all to anon,authenticated using (bucket_id<>''manji-app-releases'') with check (bucket_id<>''manji-app-releases'')';
 end if;
end $$;

commit;
-- END SOURCE: 202611020005_app_distribution.sql

