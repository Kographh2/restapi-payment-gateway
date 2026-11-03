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
