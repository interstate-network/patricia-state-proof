import { addHexPrefix, toBuffer, bufferToHex, rlp, BN } from 'ethereumjs-util';

export const isHex = (str: string): boolean => Boolean(/[xabcdef]/g.exec(str));

export interface TransformableToBuffer {
  toBuffer(): Buffer
}

export type BufferLike = string | number | BN | Buffer | TransformableToBuffer

export function isBufferLike(input: any): input is BufferLike {
  return (
    typeof input == 'string' ||
    typeof input == 'number' ||
    Buffer.isBuffer(input) ||
    BN.isBN(input) ||
    "toBuffer" in input
  );
}

export const toHex = (value: BufferLike): string => {
  if (typeof value == 'number') return addHexPrefix(value.toString(16));
  if (typeof value == 'string') {
    if (isHex(value)) return addHexPrefix(value);
    return toHex(toBn(value));
  }
  if (Buffer.isBuffer(value)) return bufferToHex(value);
  if (BN.isBN(value)) return addHexPrefix(value.toString('hex'));
  return bufferToHex(value.toBuffer());
}

export const toBn = (value: BufferLike): BN => {
  if (BN.isBN(value)) return value;
  if (typeof value == 'number') return new BN(value);
  if (typeof value == 'string') return new BN(value, isHex(value) ? 'hex' : undefined);
  if (Buffer.isBuffer(value)) return new BN(value);
  return new BN(value.toBuffer());
}

export const toBuf32 = (value: BufferLike): Buffer => {
  const buf = toBuffer(value);
  if (buf.byteLength == 32) return buf;
  return toBn(buf).toArrayLike(Buffer, 'be', 32);
}