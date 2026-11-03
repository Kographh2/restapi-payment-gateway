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
