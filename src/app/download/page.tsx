import {DownloadCenter} from '@/components';
import {config} from '@/services/config';
import {database} from '@/services/database';
import {appDistribution} from '@/services/app-distribution';
import type {ReleaseCatalog} from '@manji/validation/releases';
import {unsignedArtifactInfo} from '@/services/unsigned-artifact';
import {signedArtifactInfo} from '@/services/signed-artifact';
export const dynamic='force-dynamic';
export const metadata={title:'Unduh Aplikasi Android',description:'Pusat unduhan dan pemasangan resmi MANJI Gateway untuk Android.'};
export default async function Download(){let data:ReleaseCatalog|null=null,error='';try{const c=config();data=await appDistribution(c,await database(c)).catalog('stable');}catch{error='Rilis resmi belum tersedia dari server. Anda dapat memeriksa kembali nanti.';}return <DownloadCenter initial={data} initialError={error} unsignedArtifact={await unsignedArtifactInfo()} signedArtifact={await signedArtifactInfo()}/>;}
