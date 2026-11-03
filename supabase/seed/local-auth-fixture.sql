-- Local sandbox/PGlite ONLY. Never apply to an existing Supabase project.
create role anon;create role authenticated;create role service_role bypassrls;
create schema auth;
create table auth.users(id uuid primary key,email text not null unique,email_confirmed_at timestamptz,raw_user_meta_data jsonb not null default '{}');
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
grant usage on schema auth,public to anon,authenticated,service_role;
create schema gateway_sandbox;
create table gateway_sandbox.identities(user_id uuid primary key references auth.users(id),password_hash text not null);
create table gateway_sandbox.mail(id uuid primary key,user_id uuid not null references auth.users(id),type text not null,token_hash text not null,token_encrypted text not null,expires_at timestamptz not null,used_at timestamptz,created_at timestamptz not null default now());
create table gateway_sandbox.access_tokens(secret_hash text primary key,user_id uuid not null references auth.users(id),session_id uuid not null,expires_at timestamptz not null);
revoke all on schema gateway_sandbox from public,anon,authenticated;
