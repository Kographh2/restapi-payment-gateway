-- Protected operator SQL only. Run with psql -v admin_user_id='<verified-auth-uuid>'.
-- No public registration or application role promotion can call this process.
begin;
select set_config('manji.provision_admin_id', :'admin_user_id', true);
do $$
declare target uuid:=current_setting('manji.provision_admin_id')::uuid;
begin
 if not exists(select 1 from auth.users where id=target and email_confirmed_at is not null) then raise exception 'Verified auth account required';end if;
 insert into manji_gateway.profiles(id,email,display_name,email_verified_at)
 select id,email,left(coalesce(raw_user_meta_data->>'display_name','Administrator'),100),email_confirmed_at from auth.users where id=target on conflict(id) do nothing;
 update manji_gateway.profiles set role='ADMIN',status='ACTIVE',updated_at=now() where id=target;
 insert into manji_gateway.audit_logs(actor_id,action,resource_id,details) values(target,'operator.admin.provisioned',target,'{"process":"protected-owner-connection"}');
end $$;
commit;
