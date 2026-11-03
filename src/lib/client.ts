'use client';
let refreshing:Promise<boolean>|undefined;
export async function api<T=unknown>(path:string,body?:unknown,method=body===undefined?'GET':'POST',idempotency=crypto.randomUUID()):Promise<T>{
  const run=()=>fetch(path,{method,credentials:'same-origin',headers:{'content-type':'application/json',...(method!=='GET'?{'idempotency-key':idempotency}:{})},body:body===undefined?undefined:JSON.stringify(body)});
  let response=await run();
  const authEntry=/^\/v1\/auth\/(login|register|verify|refresh|reset-password|resend-verification)$/.test(path);
  if(response.status===401&&!authEntry){
    refreshing??=fetch('/v1/auth/refresh',{method:'POST',headers:{'content-type':'application/json'},body:'{}'}).then(r=>r.ok).finally(()=>{refreshing=undefined;});
    if(await refreshing)response=await run();
  }
  const value=await response.json();if(!response.ok){const error=new Error(value.error?.message??'Permintaan gagal') as Error&{status:number;code:string};error.status=response.status;error.code=value.error?.code;if(response.status===401&&!authEntry)window.location.assign('/login');throw error;}return value as T;
}
