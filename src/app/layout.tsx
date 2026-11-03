import type {Metadata,Viewport} from 'next';
import '@/components/style.css';
import '@/components/download.css';
export const metadata:Metadata={title:{default:'MANJI Gateway',template:'%s · MANJI Gateway'},description:'Pemantauan QRIS merchant dengan deteksi dan verifikasi yang terpisah',robots:{index:false,follow:false}};
export const viewport:Viewport={width:'device-width',initialScale:1,viewportFit:'cover',themeColor:'#FCFAF9'};
export const dynamic='force-dynamic';
export default function Layout({children}:{children:React.ReactNode}){return <html lang="id"><body><a href="#main" className="skip-link">Lewati ke konten</a>{children}</body></html>;}
