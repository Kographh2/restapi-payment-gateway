// Next runs register before serving requests, including direct Next/Docker starts.
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    const {config} = await import('./services/config');
    const c = config();
    if (c.PAYMENT_ENV === 'production') console.warn('MANJI: official provider verification is not onboarded. Verified payments and dynamic QRIS remain unavailable.');
  }
}
