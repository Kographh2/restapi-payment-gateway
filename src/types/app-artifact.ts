/** A development archive, deliberately excluded from the signed release catalog. */
export type UnsignedArtifact={filename:'manji-gateway-release-unsigned.apk';size_bytes:number;sha256:string;unsigned:true;download_path:'/api/v1/app/unsigned/download'};

/** Existing APK signed in place as a separate file, without rebuilding Android. */
export type SignedArtifact={filename:'manji-gateway-release.apk';size_bytes:number;sha256:string;signer_sha256:string;version_name:string;version_code:number;min_sdk:number;download_path:'/aplikasi/manji-gateway-release.apk'};
