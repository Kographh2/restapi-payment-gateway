-- Targeted PGRST106 repair. Run as postgres/owner in Supabase SQL Editor.
-- Preferred UI equivalent: Data API -> Exposed schemas -> ADD manji_gateway.
-- Does not grant table/function access, change RLS, or enable any provider.
-- Preserves an existing explicit schema allowlist. If none is visible to SQL,
-- add manji_gateway in the dashboard, or copy its COMPLETE current Exposed
-- schemas list into dashboard_schemas below and rerun this script.
-- Never guess that list: a role override replaces the dashboard configuration.
begin;
do $repair$
declare
 -- Optional fallback ONLY when no explicit role allowlist exists.
 -- Replace NULL with the exact comma-separated list from your own dashboard.
 dashboard_schemas text := null;
 previous_schemas text;
 next_schemas text;
 database_scoped boolean;
 schema_names text[];
begin
 if to_regnamespace('manji_gateway') is null
    or to_regprocedure('manji_gateway.account_command(uuid,uuid,text,jsonb)') is null then
  raise exception 'MANJI_MIGRATIONS_MISSING: install the dated gateway migrations before exposing the schema';
 end if;
 select substring(item from length('pgrst.db_schemas=')+1),s.setdatabase<>0
 into previous_schemas,database_scoped
 from pg_db_role_setting s
 join pg_roles r on r.oid=s.setrole
 cross join lateral unnest(s.setconfig) item
 where r.rolname='authenticator'
   and s.setdatabase in (0,(select oid from pg_database where datname=current_database()))
   and item like 'pgrst.db_schemas=%'
 order by s.setdatabase desc limit 1;
 if previous_schemas is null or btrim(previous_schemas)='' then
  previous_schemas:=nullif(btrim(dashboard_schemas),'');
  if previous_schemas is null then
   raise warning 'EXPOSE_WITH_DASHBOARD: no configuration changed. Add manji_gateway to Data API -> Exposed schemas and save, keeping all existing entries. Alternatively, copy the COMPLETE current list into dashboard_schemas in this script and rerun. SQL cannot discover the dashboard-managed allowlist.';
   return;
  end if;
 end if;
 schema_names:=regexp_split_to_array(btrim(previous_schemas),'\s*,\s*');
 if exists(select 1 from unnest(schema_names) n where n!~'^[A-Za-z_][A-Za-z0-9_]*$') then
  raise exception 'EXPOSE_WITH_DASHBOARD: existing schema names require dashboard-managed configuration';
 end if;
 if 'manji_gateway'=any(schema_names) then
  next_schemas:=previous_schemas;
 else
  next_schemas:=previous_schemas||',manji_gateway';
 end if;
 if database_scoped then
  execute format('alter role authenticator in database %I set pgrst.db_schemas = %L',current_database(),next_schemas);
 else
  execute format('alter role authenticator set pgrst.db_schemas = %L',next_schemas);
 end if;
 perform pg_notify('pgrst','reload config');
 perform pg_notify('pgrst','reload schema');
 raise notice 'MANJI_SCHEMA_CONFIGURED: authenticator allowlist is now %. PostgREST reload requested; verify Data API access separately.',next_schemas;
end $repair$;
commit;
