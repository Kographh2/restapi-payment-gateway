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
