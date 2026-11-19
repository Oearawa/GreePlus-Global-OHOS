import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DEFAULT_COUNTRY_CODE } from '../constants/GreeCountryConfig';
import {
  KEY_BOUND_DEVICES,
  KEY_CLOUD_SESSION,
  KEY_CUSTOM_SERVER_OVERRIDE,
  KEY_FORM_DEVICE_MAP,
  KEY_FORM_DIMENSIONS,
  KEY_FORM_IDS,
  KEY_LAST_SELECTED_MAC,
  KEY_SELECTED_COUNTRY_CODE,
  PREFERENCES_NAME
} from '../constants/StorageKeys';
import {
  GreeCloudSessionInfo,
  GreeCustomServerOverride,
  PersistedDeviceInfo
} from '../../model/GreeProtocolTypes';

export interface FormDimensionRecord {
  formId: string;
  dimension: number;
}

const DOMAIN: number = 0x4752;
const TAG: string = 'StorageUtil';

/**
 * Persistent storage wrapper using @kit.ArkData preferences for device keys,
 * country route, custom server override, and cloud session.
 */
export class StorageUtil {
  private static instance: StorageUtil | null = null;
  private store: preferences.Preferences | null = null;
  private initPromise: Promise<void> | null = null;

  static getInstance(): StorageUtil {
    if (StorageUtil.instance === null) {
      StorageUtil.instance = new StorageUtil();
    }
    return StorageUtil.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.store !== null) {
      return;
    }
    if (this.initPromise !== null) {
      await this.initPromise;
      return;
    }
    this.initPromise = this.openStore(context);
    await this.initPromise;
  }

  async reloadFromDisk(context: common.Context): Promise<void> {
    try {
      await preferences.removePreferencesFromCache(context, PREFERENCES_NAME);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'removePreferencesFromCache ignored: %{public}s', String(err));
    }
    this.store = null;
    this.initPromise = null;
    await this.init(context);
  }

  private async openStore(context: common.Context): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, PREFERENCES_NAME);
      hilog.info(DOMAIN, TAG, 'Preferences initialized');
    } catch (err) {
      this.initPromise = null;
      hilog.error(DOMAIN, TAG, 'Failed to open Preferences: %{public}s', String(err));
    }
  }

  async loadDevices(): Promise<PersistedDeviceInfo[]> {
    if (this.store === null) {
      return [];
    }
    try {
      const raw: preferences.ValueType = await this.store.get(KEY_BOUND_DEVICES, '[]');
      const jsonStr: string = typeof raw === 'string' ? raw : '[]';
      if (jsonStr.trim().length === 0) {
        return [];
      }
      const parsed: PersistedDeviceInfo[] = JSON.parse(jsonStr) as PersistedDeviceInfo[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadDevices parse error: %{public}s', String(err));
      return [];
    }
  }

  async saveDevices(devices: PersistedDeviceInfo[]): Promise<void> {
    if (this.store === null) {
      return;
    }
    try {
      const serialized: string = JSON.stringify(devices);
      await this.store.put(KEY_BOUND_DEVICES, serialized);
      await this.store.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveDevices failed: %{public}s', String(err));
    }
  }

  async upsertDevice(device: PersistedDeviceInfo): Promise<void> {
    const existing: PersistedDeviceInfo[] = await this.loadDevices();
    let updated: boolean = false;
    const nextList: PersistedDeviceInfo[] = [];
    for (let i: number = 0; i < existing.length; i++) {
      if (existing[i].mac.toLowerCase() === device.mac.toLowerCase()) {
        nextList.push(device);
        updated = true;
      } else {
        nextList.push(existing[i]);
      }
    }
    if (!updated) {
      nextList.push(device);
    }
    await this.saveDevices(nextList);
  }

  async removeDevice(mac: string): Promise<void> {
    const existing: PersistedDeviceInfo[] = await this.loadDevices();
    const filtered: PersistedDeviceInfo[] = [];
    for (let i: number = 0; i < existing.length; i++) {
      if (existing[i].mac.toLowerCase() !== mac.toLowerCase()) {
        filtered.push(existing[i]);
      }
    }
    await this.saveDevices(filtered);
  }

  async loadCloudSession(): Promise<GreeCloudSessionInfo | null> {
    if (this.store === null) {
      return null;
    }
    try {
      const raw: preferences.ValueType = await this.store.get(KEY_CLOUD_SESSION, '');
      const jsonStr: string = typeof raw === 'string' ? raw : '';
      if (jsonStr.trim().length === 0) {
        return null;
      }
      const parsed: GreeCloudSessionInfo = JSON.parse(jsonStr) as GreeCloudSessionInfo;
      if (parsed === null || typeof parsed.token !== 'string' || parsed.token.length === 0) {
        return null;
      }
      return parsed;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadCloudSession error: %{public}s', String(err));
      return null;
    }
  }

  async saveCloudSession(session: GreeCloudSessionInfo | null): Promise<void> {
    if (this.store === null) {
      return;
    }
    try {
      if (session === null) {
        await this.store.delete(KEY_CLOUD_SESSION);
      } else {
        await this.store.put(KEY_CLOUD_SESSION, JSON.stringify(session));
      }
      await this.store.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveCloudSession failed: %{public}s', String(err));
    }
  }

  async getSelectedCountryCode(): Promise<string> {
    if (this.store === null) {
      return '';
    }
    try {
      const raw: preferences.ValueType = await this.store.get(KEY_SELECTED_COUNTRY_CODE, '');
      return typeof raw === 'string' && raw.trim().length > 0 ? raw.trim().toUpperCase() : '';
    } catch (err) {
      return '';
    }
  }

  async saveSelectedCountryCode(countryCode: string): Promise<void> {
    if (this.store === null) {
      return;
    }
    try {
      await this.store.put(KEY_SELECTED_COUNTRY_CODE, countryCode.toUpperCase());
      await this.store.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveSelectedCountryCode failed: %{public}s', String(err));
    }
  }

  async loadCustomServerOverride(): Promise<GreeCustomServerOverride | null> {
    if (this.store === null) {
      return null;
    }
    try {
      const raw: preferences.ValueType = await this.store.get(KEY_CUSTOM_SERVER_OVERRIDE, '');
      const jsonStr: string = typeof raw === 'string' ? raw : '';
      if (jsonStr.trim().length === 0) {
        return null;
      }
      const parsed: GreeCustomServerOverride = JSON.parse(jsonStr) as GreeCustomServerOverride;
      if (parsed === null || typeof parsed.apiBaseUrl !== 'string') {
        return null;
      }
      return parsed;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadCustomServerOverride error: %{public}s', String(err));
      return null;
    }
  }

  async saveCustomServerOverride(override: GreeCustomServerOverride | null): Promise<void> {
    if (this.store === null) {
      return;
    }
    try {
      if (override === null) {
        await this.store.delete(KEY_CUSTOM_SERVER_OVERRIDE);
      } else {
        await this.store.put(KEY_CUSTOM_SERVER_OVERRIDE, JSON.stringify(override));
      }
      await this.store.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveCustomServerOverride failed: %{public}s', String(err));
    }
  }

  async getLastSelectedMac(): Promise<string> {
    if (this.store === null) {
      return '';
    }
    try {
      const raw: preferences.ValueType = await this.store.get(KEY_LAST_SELECTED_MAC, '');
      return typeof raw === 'string' ? raw : '';
    } catch (err) {
      return '';
    }
  }

  async saveLastSelectedMac(mac: string): Promise<void> {
    if (this.store === null) {
      return;
    }
    try {
      await this.store.put(KEY_LAST_SELECTED_MAC, mac);
      await this.store.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveLastSelectedMac failed: %{public}s', String(err));
    }
  }

  async loadFormIds(): Promise<string[]> {
    if (this.store === null) {
      return [];
    }
    try {
      const raw: preferences.ValueType = await this.store.get(KEY_FORM_IDS, '[]');
      const jsonStr: string = typeof raw === 'string' ? raw : '[]';
      const parsed: string[] = JSON.parse(jsonStr) as string[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed.filter((id: string) => typeof id === 'string' && id.length > 0);
    } catch (err) {
      return [];
    }
  }

  async addFormId(formId: string): Promise<void> {
    if (this.store === null || formId.length === 0) {
      return;
    }
    const ids: string[] = await this.loadFormIds();
    if (!ids.includes(formId)) {
      ids.push(formId);
      try {
        await this.store.put(KEY_FORM_IDS, JSON.stringify(ids));
        await this.store.flush();
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'addFormId failed: %{public}s', String(err));
      }
    }
  }

  async removeFormId(formId: string): Promise<void> {
    if (this.store === null || formId.length === 0) {
      return;
    }
    const ids: string[] = await this.loadFormIds();
    const filtered: string[] = ids.filter((id: string) => id !== formId);
    try {
      await this.store.put(KEY_FORM_IDS, JSON.stringify(filtered));
      await this.store.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'removeFormId failed: %{public}s', String(err));
    }
    await this.removeFormDimension(formId);
    await this.removeFormBoundMac(formId);
  }

  async loadFormDeviceMap(): Promise<Record<string, string>> {
    if (this.store === null) {
      return {};
    }
    try {
      const raw: preferences.ValueType = await this.store.get(KEY_FORM_DEVICE_MAP, '{}');
      const jsonStr: string = typeof raw === 'string' ? raw : '{}';
      const parsed: Record<string, string> = JSON.parse(jsonStr) as Record<string, string>;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return {};
      }
      return parsed;
    } catch (err) {
      return {};
    }
  }

  async getFormBoundMac(formId: string): Promise<string> {
    if (formId.length === 0) {
      return '';
    }
    const map: Record<string, string> = await this.loadFormDeviceMap();
    const bound: string | undefined = map[formId];
    return typeof bound === 'string' ? bound : '';
  }

  async setFormBoundMac(formId: string, mac: string): Promise<void> {
    if (this.store === null || formId.length === 0 || mac.length === 0) {
      return;
    }
    const map: Record<string, string> = await this.loadFormDeviceMap();
    map[formId] = mac;
    try {
      await this.store.put(KEY_FORM_DEVICE_MAP, JSON.stringify(map));
      await this.store.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setFormBoundMac failed: %{public}s', String(err));
    }
  }

  async removeFormBoundMac(formId: string): Promise<void> {
    if (this.store === null || formId.length === 0) {
      return;
    }
    const map: Record<string, string> = await this.loadFormDeviceMap();
    if (map[formId] === undefined) {
      return;
    }
    const nextMap: Record<string, string> = {};
    const keys: string[] = Object.keys(map);
    for (let i: number = 0; i < keys.length; i++) {
      const k: string = keys[i];
      if (k !== formId) {
        nextMap[k] = map[k];
      }
    }
    try {
      await this.store.put(KEY_FORM_DEVICE_MAP, JSON.stringify(nextMap));
      await this.store.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'removeFormBoundMac failed: %{public}s', String(err));
    }
  }

  async assignNextAvailableMacForForm(formId: string, devices: PersistedDeviceInfo[]): Promise<string> {
    if (devices.length === 0) {
      return '';
    }
    const existingMac: string = await this.getFormBoundMac(formId);
    if (existingMac.length > 0) {
      for (let i: number = 0; i < devices.length; i++) {
        if (devices[i].mac.toLowerCase() === existingMac.toLowerCase()) {
          return devices[i].mac;
        }
      }
    }

    const activeIds: string[] = await this.loadFormIds();
    const map: Record<string, string> = await this.loadFormDeviceMap();
    const usedMacs: string[] = [];
    for (let i: number = 0; i < activeIds.length; i++) {
      const id: string = activeIds[i];
      if (id !== formId && typeof map[id] === 'string' && map[id].length > 0) {
        usedMacs.push(map[id].toLowerCase());
      }
    }

    let chosenMac: string = devices[0].mac;
    for (let i: number = 0; i < devices.length; i++) {
      if (!usedMacs.includes(devices[i].mac.toLowerCase())) {
        chosenMac = devices[i].mac;
        break;
      }
    }
    if (formId.length > 0) {
      await this.setFormBoundMac(formId, chosenMac);
    }
    return chosenMac;
  }

  async loadFormDimensions(): Promise<FormDimensionRecord[]> {
    if (this.store === null) {
      return [];
    }
    try {
      const raw: preferences.ValueType = await this.store.get(KEY_FORM_DIMENSIONS, '[]');
      const jsonStr: string = typeof raw === 'string' ? raw : '[]';
      const parsed: FormDimensionRecord[] = JSON.parse(jsonStr) as FormDimensionRecord[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (err) {
      return [];
    }
  }

  async setFormDimension(formId: string, dimension: number): Promise<void> {
    if (this.store === null || formId.length === 0 || dimension <= 0) {
      return;
    }
    const list: FormDimensionRecord[] = await this.loadFormDimensions();
    const next: FormDimensionRecord[] = list.filter((item: FormDimensionRecord) => item.formId !== formId);
    next.push({ formId: formId, dimension: dimension });
    try {
      await this.store.put(KEY_FORM_DIMENSIONS, JSON.stringify(next));
      await this.store.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setFormDimension failed: %{public}s', String(err));
    }
  }

  async getFormDimension(formId: string): Promise<number> {
    const list: FormDimensionRecord[] = await this.loadFormDimensions();
    for (let i: number = 0; i < list.length; i++) {
      if (list[i].formId === formId) {
        return list[i].dimension;
      }
    }
    return 2;
  }

  private async removeFormDimension(formId: string): Promise<void> {
    if (this.store === null) {
      return;
    }
    const list: FormDimensionRecord[] = await this.loadFormDimensions();
    const filtered: FormDimensionRecord[] = list.filter((item: FormDimensionRecord) => item.formId !== formId);
    try {
      await this.store.put(KEY_FORM_DIMENSIONS, JSON.stringify(filtered));
      await this.store.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'removeFormDimension failed: %{public}s', String(err));
    }
  }
}
