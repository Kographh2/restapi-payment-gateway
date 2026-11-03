import {handle} from '@/services/http';
export const runtime='nodejs';export const dynamic='force-dynamic';
export const GET=(req:Request)=>{const url=new URL(req.url);url.pathname='/health';return handle(new Request(url,req));};
