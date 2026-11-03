-- Initial schema baseline, review with Supabase migration tools before production.
create extension if not exists pgcrypto;

create type public.member_role as enum ('owner','admin','staff');
create type public.payment_status as enum ('PENDING','DETECTED','PAID','EXPIRED','CANCELED','REVIEW');
create type public.qr_mode as enum ('STATIC_QRIS','PROVIDER_DYNAMIC');

create table public.merchants (
 id uuid primary key default gen_random_uuid(),
 name text not null check (length(name) between 1 and 120),
 created_at timestamptz not null default now()
);
create table public.merchant_members (
 merchant_id uuid not null references public.merchants(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role public.member_role not null default 'staff',
 created_at timestamptz not null default now(),
 primary key(merchant_id,user_id)
);
create table public.merchant_qr_sources (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchants(id) on delete cascade,
 qr_mode public.qr_mode not null default 'STATIC_QRIS',
 -- private storage object key, not an arbitrary QR payload copied into browser clients
 storage_path text,
 provider_source_id text,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 check ((qr_mode='STATIC_QRIS' and storage_path is not null) or
        (qr_mode='PROVIDER_DYNAMIC' and provider_source_id is not null))
);
create table public.merchant_devices (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchants(id) on delete cascade,
 name text not null,
 device_public_id text not null unique,
 token_hash text,
 revoked_at timestamptz,
 last_seen_at timestamptz,
 created_at timestamptz not null default now()
);
create table public.payment_intents (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchants(id) on delete cascade,
 public_reference text not null unique,
 external_reference text,
 qr_source_id uuid references public.merchant_qr_sources(id),
 qr_mode public.qr_mode not null default 'STATIC_QRIS',
 amount_idr bigint not null check (amount_idr between 1 and 10000000),
 currency text not null default 'IDR' check(currency='IDR'),
 status public.payment_status not null default 'PENDING',
 provider_transaction_id text,
 verification_source text,
 verified_at timestamptz,
 expires_at timestamptz not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(merchant_id,external_reference),
 check ((status='PAID' and verification_source is not null and verified_at is not null)
    or (status<>'PAID' and verified_at is null))
);
create index payment_intents_merchant_created_idx on public.payment_intents (merchant_id,created_at desc);
create table public.notification_signals (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchants(id) on delete cascade,
 device_id uuid not null references public.merchant_devices(id) on delete cascade,
 source_package text not null,
 amount_idr bigint check (amount_idr > 0),
 posted_at timestamptz not null,
 dedup_hash text not null check(length(dedup_hash)=64),
 classification text not null default 'UNTRUSTED' check(classification='UNTRUSTED'),
 received_at timestamptz not null default now(),
 unique(merchant_id,device_id,dedup_hash)
);
create table public.signal_candidates (
 signal_id uuid not null references public.notification_signals(id) on delete cascade,
 payment_intent_id uuid not null references public.payment_intents(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(signal_id,payment_intent_id)
);
create table public.provider_events (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchants(id) on delete cascade,
 payment_intent_id uuid references public.payment_intents(id),
 provider_name text not null,
 provider_event_id text not null,
 verified_signature boolean not null default false,
 event_type text not null,
 received_at timestamptz not null default now(),
 unique(provider_name,provider_event_id)
);
create table public.api_keys (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchants(id) on delete cascade,
 key_prefix text not null,
 secret_hash text not null,
 scopes text[] not null default '{}',
 expires_at timestamptz,
 revoked_at timestamptz,
 created_at timestamptz not null default now()
);
create table public.webhook_endpoints (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchants(id) on delete cascade,
 url text not null check(url like 'https://%'),
 signing_secret_encrypted text not null,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.webhook_deliveries (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchants(id) on delete cascade,
 endpoint_id uuid not null references public.webhook_endpoints(id) on delete cascade,
 payment_intent_id uuid references public.payment_intents(id),
 event_type text not null,
 attempt_count int not null default 0,
 delivered_at timestamptz,
 next_attempt_at timestamptz,
 created_at timestamptz not null default now()
);
create table public.audit_events (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchants(id) on delete cascade,
 actor_user_id uuid references auth.users(id),
 action text not null,
 resource_id uuid,
 occurred_at timestamptz not null default now()
);

-- Deny by default: enforce through audited server routes or carefully reviewed RLS.
alter table public.merchants enable row level security;
alter table public.merchant_members enable row level security;
alter table public.merchant_qr_sources enable row level security;
alter table public.merchant_devices enable row level security;
alter table public.payment_intents enable row level security;
alter table public.notification_signals enable row level security;
alter table public.signal_candidates enable row level security;
alter table public.provider_events enable row level security;
alter table public.api_keys enable row level security;
alter table public.webhook_endpoints enable row level security;
alter table public.webhook_deliveries enable row level security;
alter table public.audit_events enable row level security;

-- Initial **read-only** tenant views through authenticated client. No direct client writes.
-- Harden server-side role and membership checks before adding write policies.
create function public.is_member(target_merchant_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$ select exists (select 1 from public.merchant_members mm
  where mm.merchant_id = target_merchant_id and mm.user_id = (select auth.uid())); $$;
revoke all on function public.is_member(uuid) from public;
grant execute on function public.is_member(uuid) to authenticated;

create policy merchants_select_members on public.merchants
 for select to authenticated using (public.is_member(id));
create policy memberships_select_self on public.merchant_members
 for select to authenticated using (user_id=(select auth.uid()));
create policy qr_sources_select_members on public.merchant_qr_sources
 for select to authenticated using (public.is_member(merchant_id));
create policy devices_select_members on public.merchant_devices
 for select to authenticated using (public.is_member(merchant_id));
create policy intents_select_members on public.payment_intents
 for select to authenticated using (public.is_member(merchant_id));
create policy signal_select_members on public.notification_signals
 for select to authenticated using (public.is_member(merchant_id));
create policy provider_events_select_members on public.provider_events
 for select to authenticated using (public.is_member(merchant_id));
-- No direct client policies on API keys, webhooks or audit by default.
-- IMPORTANT: all writes use backend with independently validated authorization.
-- Review Postgres grants/functions/triggers and tenant-consistency constraints;
-- references across tenant IDs need server-side or trigger validation before launch.
