import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  GREE_CLOUD_API_AES_KEY,
  GREE_GCM_AAD,
  GREE_GCM_NONCE_BYTES,
  GREE_GENERIC_KEY,
  GREE_LOCAL_GCM_KEY
} from '../constants/GreeConstants';

const DOMAIN: number = 0x4752;
const TAG: string = 'GreeCryptoUtil';
const AES_BLOCK_KEY_BYTES: number = 16;
const GCM_TAG_BYTES: number = 16;

export interface GcmCipherResult {
  pack: string;
  tag: string;
}

/**
 * AES-128-ECB (CipherV1 & Cloud REST/MQTT), AES-128-GCM (CipherV2),
 * MD5 digest, and Base64 crypto helper built on @kit.CryptoArchitectureKit.
 */
export class GreeCryptoUtil {
  private static readonly base64Helper: util.Base64Helper = new util.Base64Helper();
  private static readonly textEncoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private static readonly textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  private static normalizeKeyBytes(rawKey: string): Uint8Array {
    const effectiveKey: string = rawKey.length > 0 ? rawKey : GREE_GENERIC_KEY;
    const encoded: Uint8Array = GreeCryptoUtil.textEncoder.encodeInto(effectiveKey);
    if (encoded.length === AES_BLOCK_KEY_BYTES) {
      return encoded;
    }
    const normalized: Uint8Array = new Uint8Array(AES_BLOCK_KEY_BYTES);
    const copyLen: number = Math.min(encoded.length, AES_BLOCK_KEY_BYTES);
    for (let i: number = 0; i < copyLen; i++) {
      normalized[i] = encoded[i];
    }
    return normalized;
  }

  private static async buildSymKey(rawKey: string): Promise<cryptoFramework.SymKey | null> {
    try {
      const keyBytes: Uint8Array = GreeCryptoUtil.normalizeKeyBytes(rawKey);
      const keyBlob: cryptoFramework.DataBlob = { data: keyBytes };
      const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
      return await generator.convertKey(keyBlob);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'buildSymKey failed: %{public}s', String(err));
      return null;
    }
  }

  /**
   * Encrypts a UTF-8 JSON string using AES-128-ECB/PKCS7 and returns standard Base64 text.
   */
  static async encryptPack(plainJson: string, key: string): Promise<string> {
    if (plainJson.length === 0) {
      return '';
    }
    try {
      const symKey: cryptoFramework.SymKey | null = await GreeCryptoUtil.buildSymKey(key);
      if (symKey === null) {
        return '';
      }
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|ECB|PKCS7');
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, null);
      const plainBytes: Uint8Array = GreeCryptoUtil.textEncoder.encodeInto(plainJson);
      const plainBlob: cryptoFramework.DataBlob = { data: plainBytes };
      const encryptedBlob: cryptoFramework.DataBlob = await cipher.doFinal(plainBlob);
      if (encryptedBlob === null || encryptedBlob.data.length === 0) {
        return '';
      }
      return GreeCryptoUtil.base64Helper.encodeToStringSync(encryptedBlob.data);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'encryptPack failed: %{public}s', String(err));
      return '';
    }
  }

  /**
   * Decrypts a Base64-encoded AES-128-ECB/PKCS7 pack string into UTF-8 JSON.
   */
  static async decryptPack(base64Cipher: string, key: string): Promise<string> {
    if (base64Cipher.length === 0) {
      return '';
    }
    try {
      const cipherBytes: Uint8Array = GreeCryptoUtil.base64Helper.decodeSync(base64Cipher.trim());
      if (cipherBytes.length === 0) {
        return '';
      }
      const symKey: cryptoFramework.SymKey | null = await GreeCryptoUtil.buildSymKey(key);
      if (symKey === null) {
        return '';
      }
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|ECB|PKCS7');
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, null);
      const cipherBlob: cryptoFramework.DataBlob = { data: cipherBytes };
      const plainBlob: cryptoFramework.DataBlob = await cipher.doFinal(cipherBlob);
      if (plainBlob === null || plainBlob.data.length === 0) {
        return '';
      }
      return GreeCryptoUtil.textDecoder.decodeToString(plainBlob.data);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'decryptPack failed with provided key: %{public}s', String(err));
      return '';
    }
  }

  private static buildGcmParams(tagBytes: Uint8Array): cryptoFramework.GcmParamsSpec {
    const nonce: Uint8Array = new Uint8Array(GREE_GCM_NONCE_BYTES);
    const aad: Uint8Array = GreeCryptoUtil.textEncoder.encodeInto(GREE_GCM_AAD);
    return {
      algName: 'GcmParamsSpec',
      iv: { data: nonce },
      aad: { data: aad },
      authTag: { data: tagBytes }
    };
  }

  /**
   * Encrypts a UTF-8 JSON string using AES-128-GCM (CipherV2 LAN protocol).
   */
  static async encryptPackGcm(plainJson: string, key?: string): Promise<GcmCipherResult> {
    if (plainJson.length === 0) {
      return { pack: '', tag: '' };
    }
    try {
      const effectiveKey: string = key !== undefined && key.length > 0 ? key : GREE_LOCAL_GCM_KEY;
      const symKey: cryptoFramework.SymKey | null = await GreeCryptoUtil.buildSymKey(effectiveKey);
      if (symKey === null) {
        return { pack: '', tag: '' };
      }
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|GCM|NoPadding');
      const params: cryptoFramework.GcmParamsSpec = GreeCryptoUtil.buildGcmParams(new Uint8Array(GCM_TAG_BYTES));
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
      const plainBytes: Uint8Array = GreeCryptoUtil.textEncoder.encodeInto(plainJson);
      const encryptedBlob: cryptoFramework.DataBlob = await cipher.doFinal({ data: plainBytes });
      if (encryptedBlob === null || encryptedBlob.data.length <= GCM_TAG_BYTES) {
        return { pack: '', tag: '' };
      }
      const splitAt: number = encryptedBlob.data.length - GCM_TAG_BYTES;
      const cipherBytes: Uint8Array = encryptedBlob.data.slice(0, splitAt);
      const tagBytes: Uint8Array = encryptedBlob.data.slice(splitAt);
      return {
        pack: GreeCryptoUtil.base64Helper.encodeToStringSync(cipherBytes),
        tag: GreeCryptoUtil.base64Helper.encodeToStringSync(tagBytes)
      };
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'encryptPackGcm failed: %{public}s', String(err));
      return { pack: '', tag: '' };
    }
  }

  /**
   * Decrypts a Base64-encoded AES-128-GCM CipherV2 packet with its authentication tag.
   */
  static async decryptPackGcm(base64Cipher: string, base64Tag: string, key?: string): Promise<string> {
    if (base64Cipher.length === 0 || base64Tag.length === 0) {
      return '';
    }
    try {
      const cipherBytes: Uint8Array = GreeCryptoUtil.base64Helper.decodeSync(base64Cipher.trim());
      const tagBytes: Uint8Array = GreeCryptoUtil.base64Helper.decodeSync(base64Tag.trim());
      if (cipherBytes.length === 0 || tagBytes.length === 0) {
        return '';
      }
      const effectiveKey: string = key !== undefined && key.length > 0 ? key : GREE_LOCAL_GCM_KEY;
      const symKey: cryptoFramework.SymKey | null = await GreeCryptoUtil.buildSymKey(effectiveKey);
      if (symKey === null) {
        return '';
      }
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|GCM|NoPadding');
      const params: cryptoFramework.GcmParamsSpec = GreeCryptoUtil.buildGcmParams(tagBytes);
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
      const plainBlob: cryptoFramework.DataBlob = await cipher.doFinal({ data: cipherBytes });
      if (plainBlob === null || plainBlob.data.length === 0) {
        return '';
      }
      return GreeCryptoUtil.textDecoder.decodeToString(plainBlob.data);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'decryptPackGcm failed: %{public}s', String(err));
      return '';
    }
  }

  /**
   * Encrypts full Cloud REST request JSON with `#G$&^jgfujy6ujxt` (AES-128-ECB + Base64).
   */
  static async encryptCloudRequestBody(bodyJson: string, apiAesKey?: string): Promise<string> {
    const effectiveKey: string = apiAesKey !== undefined && apiAesKey.length > 0
      ? apiAesKey
      : GREE_CLOUD_API_AES_KEY;
    return await GreeCryptoUtil.encryptPack(bodyJson, effectiveKey);
  }

  /**
   * Decrypts `enRes` Base64 response field from Cloud REST endpoints with `#G$&^jgfujy6ujxt`.
   */
  static async decryptCloudEnRes(enResBase64: string, apiAesKey?: string): Promise<string> {
    const effectiveKey: string = apiAesKey !== undefined && apiAesKey.length > 0
      ? apiAesKey
      : GREE_CLOUD_API_AES_KEY;
    return await GreeCryptoUtil.decryptPack(enResBase64, effectiveKey);
  }

  static utf8ToBytes(text: string): Uint8Array {
    return GreeCryptoUtil.textEncoder.encodeInto(text);
  }

  static bytesToUtf8(bytes: Uint8Array): string {
    return GreeCryptoUtil.textDecoder.decodeToString(bytes);
  }

  private static bytesToHex(bytes: Uint8Array): string {
    const hexChars: string = '0123456789abcdef';
    let out: string = '';
    for (let i: number = 0; i < bytes.length; i++) {
      const b: number = bytes[i] & 0xff;
      out += hexChars.charAt((b >>> 4) & 0x0f) + hexChars.charAt(b & 0x0f);
    }
    return out;
  }

  /**
   * Computes lowercase 32-char hexadecimal MD5 digest via @kit.CryptoArchitectureKit.
   */
  static async md5Hex(plainText: string): Promise<string> {
    try {
      const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
      if (plainText.length > 0) {
        const inputBytes: Uint8Array = GreeCryptoUtil.textEncoder.encodeInto(plainText);
        const blob: cryptoFramework.DataBlob = { data: inputBytes };
        await md.update(blob);
      }
      const digestBlob: cryptoFramework.DataBlob = await md.digest();
      if (digestBlob === null || digestBlob.data.length === 0) {
        return '';
      }
      return GreeCryptoUtil.bytesToHex(digestBlob.data);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'md5Hex failed: %{public}s', String(err));
      return '';
    }
  }

  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  /**
   * Formats UTC time strictly as `YYYY-MM-DD HH:mm:ss` (space-separated).
   */
  static formatUtcClientTime(now?: Date): string {
    const dt: Date = now !== undefined ? now : new Date();
    const year: number = dt.getUTCFullYear();
    const month: string = GreeCryptoUtil.pad2(dt.getUTCMonth() + 1);
    const day: string = GreeCryptoUtil.pad2(dt.getUTCDate());
    const hour: string = GreeCryptoUtil.pad2(dt.getUTCHours());
    const minute: string = GreeCryptoUtil.pad2(dt.getUTCMinutes());
    const second: string = GreeCryptoUtil.pad2(dt.getUTCSeconds());
    return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
  }

  /**
   * Official Gree+ triple-MD5 login password hash:
   * `md5(md5(md5(password) + password) + stamp)`
   */
  static async computeLoginPasswordHash(password: string, stamp: string): Promise<string> {
    const m1: string = await GreeCryptoUtil.md5Hex(password);
    if (m1.length === 0) {
      return '';
    }
    const m2: string = await GreeCryptoUtil.md5Hex(`${m1}${password}`);
    if (m2.length === 0) {
      return '';
    }
    return await GreeCryptoUtil.md5Hex(`${m2}${stamp}`);
  }

  /**
   * Official `api.vc` digest: `md5("${appId}_${appHash}_${stamp}_${ts}")`
   */
  static async computeApiVc(
    appId: string,
    appHash: string,
    stamp: string,
    ts: number
  ): Promise<string> {
    return await GreeCryptoUtil.md5Hex(`${appId}_${appHash}_${stamp}_${ts}`);
  }

  /**
   * Official `datVc` digest: `md5("${appHash}_${values.join('_')}")`
   */
  static async computeDatVc(appHash: string, signedFieldValues: string[]): Promise<string> {
    return await GreeCryptoUtil.md5Hex(`${appHash}_${signedFieldValues.join('_')}`);
  }
}
