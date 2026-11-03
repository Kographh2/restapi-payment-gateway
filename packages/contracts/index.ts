export * from '@manji/shared-types';
export * from '@manji/validation';
export const idr=(value:number)=>new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0}).format(value);
