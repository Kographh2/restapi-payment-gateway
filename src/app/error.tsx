'use client';
export default function Error({reset}:{reset:()=>void}){return <main className="error-page" id="main"><h1>Halaman belum dapat dimuat.</h1><p>Periksa koneksi lalu coba kembali.</p><button onClick={reset}>Coba lagi</button><a href="/login">Masuk ulang</a></main>;}
