import type { NextConfig } from 'next';
import path from 'node:path';
const config: NextConfig = {
  distDir:process.env.NEXT_DIST_DIR??'.next',
  outputFileTracingRoot:path.resolve(__dirname),
  outputFileTracingIncludes:{'/*':['./supabase/migrations/*.sql','./supabase/seed/local-auth-fixture.sql'],'/api/v1/app/unsigned/download':['./aplikasi/manji-gateway-release-unsigned.apk'],'/aplikasi/manji-gateway-release.apk':['./aplikasi/manji-gateway-release.apk','./aplikasi/manji-gateway-release.verification.json'],'/download':['./aplikasi/manji-gateway-release-unsigned.apk','./aplikasi/manji-gateway-release.apk','./aplikasi/manji-gateway-release.verification.json']},
  poweredByHeader:false, transpilePackages:['@merchant/shared','@manji/contracts','@manji/validation','@manji/shared-types'],serverExternalPackages:['@electric-sql/pglite'],experimental:{cpus:1,webpackBuildWorker:false,workerThreads:process.env.NEXT_WORKER_THREADS==='true'},
  async headers(){return [{source:'/:path*',headers:[
    {key:'X-Content-Type-Options',value:'nosniff'}, {key:'Referrer-Policy',value:'same-origin'},
    {key:'X-Frame-Options',value:'DENY'}, {key:'Permissions-Policy',value:'camera=(), microphone=(), geolocation=()'},
    {key:'Content-Security-Policy',value:`default-src 'self'; script-src 'self' 'unsafe-inline'${process.env.NODE_ENV==='development'?" 'unsafe-eval'":''}; style-src 'self' 'unsafe-inline'; font-src 'self' data:; img-src 'self' data: blob:; connect-src 'self' https://*.supabase.co wss://*.supabase.co; frame-ancestors 'none'; base-uri 'none'; form-action 'self'; object-src 'none'`},
  ]}];},
};
export default config;
