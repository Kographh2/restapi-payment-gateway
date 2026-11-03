import {DocsScreen} from '@/components';
import {openapi,operations} from '@/services/openapi';
export default function Docs(){const spec=openapi();return <DocsScreen operations={operations.map(o=>({method:o.method,path:o.path,summary:o.summary,description:o.description??'',body:o.body?(spec.paths[o.path][o.method] as {requestBody?:unknown}).requestBody:undefined}))}/>;}
