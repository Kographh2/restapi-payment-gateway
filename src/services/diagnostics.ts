import {AsyncLocalStorage} from 'node:async_hooks';
import {ApiError} from './security';

export const requestDiagnostics=new AsyncLocalStorage<{request_id:string;operation:string;method:string}>();
export type Subsystem='configuration'|'database.supabase'|'database.local'|'auth.supabase'|'payments.provider'|'http';
export class DependencyError extends ApiError{
 constructor(public subsystem:Subsystem,public failure:string,code='DATABASE_UNAVAILABLE',message='Database belum tersedia'){super(503,code,message);}
}
const commands=new Set(['rate','public.configuration','profile.bootstrap','session.open','account.me','applications.submit','admin.application.review','request.log']);
const rpcs=new Set(['account_command','account_mutation','merchant_command','lookup_credential','provider_event','worker_command','app_release_command']);
const fields=new Set(['PAYMENT_ENV','PROVIDER_MODE','STORE_DRIVER','APP_BASE_URL','API_BASE_URL','WEBSITE_URL','APP_ENCRYPTION_KEY','SANDBOX_LOGIN_SECRET','MOCK_PROVIDER_SECRET','SUPABASE_SERVICE_ROLE_KEY','NEXT_PUBLIC_SUPABASE_URL','NEXT_PUBLIC_SUPABASE_ANON_KEY','OUTBOX_CRON_SECRET','WEBHOOK_ALLOWED_HOSTS','APP_RELEASE_CERT_SHA256','APP_DOWNLOAD_TOKEN_SECRET','APP_RELEASE_BUCKET','APP_RELEASE_TEST_MODE','APP_RELEASE_LOCAL_DIR']);
const authCodes=new Set(['unexpected_failure','request_timeout','signup_disabled','email_exists','user_already_exists','email_address_invalid','email_address_not_authorized','weak_password','over_email_send_rate_limit','over_request_rate_limit','email_not_confirmed','validation_failed']);
export function safeUpstreamCode(value:unknown){return typeof value==='string'&&(/^(?:PGRST\d{3}|[0-9A-Z]{5})$/.test(value)||authCodes.has(value))?value:'UNKNOWN';}
type Diagnostic={event:'dependency_failure'|'request_failed'|'capability_status';subsystem:Subsystem;failure:string;rpc?:string;command?:unknown;upstream_code?:unknown;upstream_status?:number;configuration_fields?:string[]};
/** Explicit fields only: never serialize an Error, request, URL, headers or payload. */
export function logDiagnostic(level:'error'|'warn'|'info',entry:Diagnostic){
 const context=requestDiagnostics.getStore();
 const status=entry.upstream_status;
 const record={timestamp:new Date().toISOString(),level,event:entry.event,subsystem:entry.subsystem,failure:entry.failure,
  ...context?{request_id:context.request_id,operation:context.operation,method:context.method}:{},
  ...entry.rpc?{rpc:rpcs.has(entry.rpc)?entry.rpc:'unknown'}:{},
  ...entry.command!==undefined?{command:typeof entry.command==='string'&&commands.has(entry.command)?entry.command:'unknown'}:{},
  ...entry.upstream_code!==undefined?{upstream_code:safeUpstreamCode(entry.upstream_code)}:{},
  ...typeof status==='number'&&Number.isInteger(status)&&status>=0&&status<=599?{upstream_status:status}:{},
  ...entry.configuration_fields?{configuration_fields:entry.configuration_fields.filter(key=>fields.has(key))}:{},
 };
 console[level](JSON.stringify(record));
}
