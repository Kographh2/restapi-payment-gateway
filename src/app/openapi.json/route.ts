import {openapi} from '@/services/openapi';
export const dynamic='force-dynamic';export const GET=()=>Response.json(openapi(),{headers:{'cache-control':'no-store'}});
