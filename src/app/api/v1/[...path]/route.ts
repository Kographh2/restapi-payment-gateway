import {handle} from '@/services/http';
export const runtime='nodejs';export const dynamic='force-dynamic';
export const GET=(req:Request)=>handle(req);export const POST=(req:Request)=>handle(req);export const DELETE=(req:Request)=>handle(req);
