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
