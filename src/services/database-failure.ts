import {ApiError,databaseError} from './security';
import {DependencyError,logDiagnostic,safeUpstreamCode} from './diagnostics';

export function databaseFailure(error:unknown,driver:'supabase'|'local',rpc:string,args:Record<string,unknown>,status?:number):never{
 const source=error&&typeof error==='object'?error as {code?:unknown;message?:unknown}:{};
 const code=safeUpstreamCode(source.code),message=typeof source.message==='string'?source.message:'';
 // Preserve existing application exceptions, role/session checks and rate limits.
 if(code==='P0001'||driver==='local')try{databaseError(message);}catch(mapped){if(mapped instanceof ApiError&&mapped.status<500)throw mapped;}
 const failure=code==='PGRST106'?'schema_not_exposed':code==='PGRST202'||code==='42883'?'rpc_missing_or_schema_cache_stale':code==='42P01'||code==='3F000'?'migration_missing':code==='42501'?'database_permission_denied':code==='PGRST301'||code==='PGRST303'||status===401?'server_credentials_rejected':code==='PGRST000'||code==='PGRST001'||code==='PGRST002'?'database_connection_unavailable':status===0||/fetch failed|network|timeout|ECONN|ENOTFOUND/i.test(message)?'database_transport_unavailable':'database_rpc_failed';
 const subsystem=driver==='supabase'?'database.supabase':'database.local';
 logDiagnostic('error',{event:'dependency_failure',subsystem,failure,rpc,command:args.p_command,upstream_code:code,upstream_status:status});
 throw new DependencyError(subsystem,failure);
}
