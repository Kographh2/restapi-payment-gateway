import {createHmac,timingSafeEqual} from 'node:crypto';
/** Destination SERVER helper. Deduplicate result.id atomically in your own database before fulfillment. */
export function verifyWebhook(rawBody:string,headers:{timestamp:string;signature:string;deliveryId:string},secret:string,nowMs=Date.now()){
 if(!/^[0-9]{10,11}$/.test(headers.timestamp)||!Number.isSafeInteger(Number(headers.timestamp))||Math.abs(nowMs/1000-Number(headers.timestamp))>300||!/^[a-f0-9]{64}$/.test(headers.signature)||!/^[a-f0-9-]{36}$/i.test(headers.deliveryId)||Buffer.byteLength(rawBody)>1000000)throw new Error('INVALID_WEBHOOK');
 const expected=createHmac('sha256',secret).update(headers.timestamp+'.'+rawBody).digest('hex');
 if(!timingSafeEqual(Buffer.from(expected),Buffer.from(headers.signature)))throw new Error('INVALID_WEBHOOK');
 const event=JSON.parse(rawBody) as {id:string;type:string;environment:string;data:Record<string,unknown>};
 if(event.id!==headers.deliveryId||!['sandbox','production'].includes(event.environment)||typeof event.type!=='string'||event.data===null||typeof event.data!=='object'||Array.isArray(event.data))throw new Error('INVALID_WEBHOOK');
 return event;
}
