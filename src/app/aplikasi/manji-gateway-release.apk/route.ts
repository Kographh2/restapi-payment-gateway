import {signedArtifactResponse} from '@/services/signed-artifact';
export const runtime='nodejs';
export const dynamic='force-dynamic';
export const GET=()=>signedArtifactResponse();
export const HEAD=()=>signedArtifactResponse(true);
