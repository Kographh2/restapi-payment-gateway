-- Baca metadata saja; tidak membaca data pengguna atau mengubah database.
begin read only;

select current_database() as database_name,
       to_regnamespace('manji_gateway') is not null as gateway_schema_installed;

select to_regprocedure('manji_gateway.account_command(uuid,uuid,text,jsonb)') is not null as account_rpc_installed,
       to_regprocedure('manji_gateway.account_mutation(uuid,uuid,text,jsonb,text,text)') is not null as account_mutation_installed;

-- Only inspect the schema allowlist, never unrelated role settings/secrets.
select r.rolname,case when s.setdatabase=0 then 'role' else d.datname end as setting_scope,
       substring(item from length('pgrst.db_schemas=')+1) as explicitly_exposed_schemas
from pg_db_role_setting s join pg_roles r on r.oid=s.setrole
left join pg_database d on d.oid=s.setdatabase
cross join lateral unnest(s.setconfig) item
where r.rolname='authenticator' and item like 'pgrst.db_schemas=%';

select t.tgname,t.tgenabled
from pg_trigger t
where t.tgrelid='auth.users'::regclass and t.tgname='manji_gateway_signup';

-- Paket aktif saat dibuat berisi 23 tabel aplikasi; semua harus mengaktifkan RLS.
select count(*) as application_tables,
       count(*) filter (where rowsecurity) as tables_with_rls,
       count(*) filter (where not rowsecurity) as tables_without_rls
from pg_tables where schemaname='manji_gateway';

select tablename, rowsecurity
from pg_tables where schemaname='manji_gateway'
order by tablename;

-- Fungsi privileged harus hanya dapat dijalankan oleh service_role/server.
select p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       p.prosecdef as security_definer,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') as service_role_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='manji_gateway'
  and p.proname in ('account_command','account_mutation','merchant_command',
                   'lookup_credential','provider_event','worker_command','app_release_command')
order by p.proname;

select tablename,policyname,roles,cmd
from pg_policies where schemaname='manji_gateway'
order by tablename,policyname;

-- Di Supabase hosted bucket ini harus ada dan public=false setelah migrasi 005.
select id,name,public,file_size_limit,allowed_mime_types
from storage.buckets where id='manji-app-releases';

select policyname,permissive,roles,cmd
from pg_policies
where schemaname='storage' and tablename='objects'
  and policyname='manji_private_release_artifacts';

-- Hosted Supabase: payment_requests harus masuk publikasi supabase_realtime.
select pubname,schemaname,tablename
from pg_publication_tables
where pubname='supabase_realtime' and schemaname='manji_gateway';

commit;
