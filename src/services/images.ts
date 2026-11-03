import {ensure} from './security';
export function validateImage(base64:string,mime:string){
  ensure(/^[A-Za-z0-9+/]+={0,2}$/.test(base64)&&base64.length<=950000,400,'INVALID_IMAGE');const bytes=Buffer.from(base64,'base64');let width=0,height=0;
  if(mime==='image/png'){ensure(bytes.length>24&&bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))&&bytes.toString('ascii',12,16)==='IHDR',400,'INVALID_IMAGE');width=bytes.readUInt32BE(16);height=bytes.readUInt32BE(20);}
  else if(mime==='image/jpeg'){ensure(bytes[0]===255&&bytes[1]===216,400,'INVALID_IMAGE');let at=2;while(at+9<bytes.length){if(bytes[at]!==255)break;const marker=bytes[at+1],length=bytes.readUInt16BE(at+2);if([192,193,194].includes(marker)){height=bytes.readUInt16BE(at+5);width=bytes.readUInt16BE(at+7);break;}if(length<2)break;at+=2+length;}}
  ensure(width>0&&height>0&&width<=4096&&height<=4096&&width*height<=12000000,400,'IMAGE_DIMENSIONS','Gunakan PNG/JPEG maksimal 4096 piksel dan 12 megapiksel');return bytes;
}
