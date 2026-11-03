import { z } from 'zod';

export const amount = z.number().int().min(1).max(10_000_000);
export const statuses = ['PENDING', 'DETECTED', 'REVIEW', 'EXPIRED', 'CANCELED', 'PAID', 'SIMULATED_PAID'] as const;
export type Status = typeof statuses[number];
export type Role = 'owner' | 'admin' | 'staff';
export const labels: Record<Status, string> = {
  PENDING: 'Menunggu pembayaran', DETECTED: 'Notifikasi terdeteksi — belum terverifikasi',
  REVIEW: 'Perlu pengecekan — bukti ambigu', EXPIRED: 'Kedaluwarsa', CANCELED: 'Dibatalkan',
  PAID: 'Pembayaran terverifikasi', SIMULATED_PAID: 'Simulasi selesai — bukan uang nyata',
};
export const createIntent = z.object({amount_idr: amount, currency: z.literal('IDR').default('IDR'),
  qr_mode: z.literal('STATIC_QRIS').default('STATIC_QRIS'), external_reference: z.string().trim().min(1).max(120).optional()}).strict();
export const signalInput = z.object({signal_id:z.string().uuid(), device_id:z.string().uuid(),
  source_package:z.string().regex(/^[A-Za-z][\w]*(?:\.[A-Za-z][\w]*)+$/).max(180), amount_idr:amount.nullable(),
  posted_at:z.string().datetime(), dedup_hash:z.string().regex(/^[a-f0-9]{64}$/), source_type:z.literal('ANDROID_NOTIFICATION')}).strict();
export const packages = z.array(signalInput.shape.source_package).max(5);
export const enrollmentInput = z.object({name:z.string().trim().min(1).max(80), allowed_packages:packages,
  consent:z.literal(true), empirically_verified:z.literal(true)}).strict();
export const mockEvent = z.object({event_id:z.string().uuid(), merchant_id:z.string().uuid(), intent_id:z.string().uuid(),
  transaction_id:z.string().uuid(), amount_idr:amount,currency:z.literal('IDR'),status:z.literal('settlement'),
  environment:z.literal('sandbox'),timestamp:z.number().int()}).strict();
export const idr = (value:number) => new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0}).format(value);
