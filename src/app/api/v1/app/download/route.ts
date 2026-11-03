/** Keep API clients on the same canonical URL as the website download button. */
export const dynamic='force-dynamic';
export function GET(){return new Response(null,{status:307,headers:{location:'/aplikasi/manji-gateway-release.apk','cache-control':'no-store','referrer-policy':'no-referrer'}});}
export const HEAD=GET;
