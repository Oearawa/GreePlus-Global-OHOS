import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  GREE_MQTT_TLS_PORT,
  GreeAcMode,
  GreeFanSpeed,
  GreeOnlineChannel,
  GreePowerState,
  GreeSwingUpDown,
  GreeTempUnit,
  MAX_TEMP_C,
  MAX_TEMP_F,
  MIN_TEMP_C,
  MIN_TEMP_F,
  TEMP_DEBOUNCE_MS
} from '../common/constants/GreeConstants';
import { DEFAULT_COUNTRY_CODE, getCountryByCode, GreeCountryItem } from '../common/constants/GreeCountryConfig';
import { CardRefreshUtil } from '../common/utils/CardRefreshUtil';
import { NetworkUtil, WifiSubnetInfo } from '../common/utils/NetworkUtil';
import { StorageUtil } from '../common/utils/StorageUtil';
import {
  AcStateSnapshot,
  fahrenheitToCelsius,
  GreeDeviceModel
} from '../model/GreeDeviceModel';
import {
  GreeCloudControlResult,
  GreeCloudSessionInfo,
  GreeCloudSyncResult,
  GreeCountryServerRoute,
  GreeCustomServerOverride
} from '../model/GreeProtocolTypes';
import { GreeCloudService } from '../service/GreeCloudService';
import { DevicePoolChangeListener, GreeLocalService, ManualIpProbeResult } from '../service/GreeLocalService';

const DOMAIN: number = 0x4752;
const TAG: string = 'AcControlViewModel';

/**
 * Page-shared reactive ViewModel handling country routing, official Gree+ login/sync,
 * LAN/Cloud dual-mode switching, 300ms temperature debounce, and Optimistic UI rollback.
 */
@ObservedV2
export class AcControlViewModel {
  private static instance: AcControlViewModel | null = null;

  @Trace devices: GreeDeviceModel[] = [];
  @Trace selectedMac: string = '';
  @Trace isScanning: boolean = false;
  @Trace isSyncingCloud: boolean = false;
  @Trace isResolvingRoute: boolean = false;
  @Trace needRelogin: boolean = false;
  @Trace statusBanner: string = '';
  @Trace localIp: string = '';
  @Trace broadcastIp: string = '';
  @Trace cloudSession: GreeCloudSessionInfo | null = null;
  @Trace selectedCountryCode: string = '';
  @Trace currentRoute: GreeCountryServerRoute | null = null;
  @Trace customOverride: GreeCustomServerOverride | null = null;

  private initialized: boolean = false;
  private initPromise: Promise<void> | null = null;
  private appContext: common.Context | null = null;
  private bannerTimerId: number = -1;
  private tempDebounceTimerId: number = -1;
  private pendingTempMac: string = '';
  private pendingTempSnapshot: AcStateSnapshot | null = null;

  private readonly poolListener: DevicePoolChangeListener = (): void => {
    this.devices = GreeLocalService.getInstance().getDevicesSnapshot();
    this.refreshDesktopCards();
  };

  private setTransientErrorBanner(msg: string): void {
    if (this.bannerTimerId >= 0) {
      clearTimeout(this.bannerTimerId);
      this.bannerTimerId = -1;
    }
    this.statusBanner = msg;
    if (msg.length > 0) {
      this.bannerTimerId = setTimeout(() => {
        this.statusBanner = '';
        this.bannerTimerId = -1;
      }, 3000);
    }
  }

  private clearStatusBanner(): void {
    if (this.bannerTimerId >= 0) {
      clearTimeout(this.bannerTimerId);
      this.bannerTimerId = -1;
    }
    this.statusBanner = '';
  }

  private refreshDesktopCards(): void {
    if (this.appContext === null) {
      return;
    }
    const persisted = this.devices.map((d: GreeDeviceModel) => d.toPersistedInfo());
    CardRefreshUtil.refreshAllCards(this.appContext, persisted).catch(() => {});
  }

  findDeviceByNameOrFirst(deviceName?: string): GreeDeviceModel | null {
    if (this.devices.length === 0) {
      return null;
    }
    const target: string = (deviceName ?? '').trim().toLowerCase();
    if (target.length > 0) {
      for (let i: number = 0; i < this.devices.length; i++) {
        if (this.devices[i].name.toLowerCase().includes(target) ||
          this.devices[i].mac.toLowerCase().includes(target)) {
          return this.devices[i];
        }
      }
    }
    return this.devices[0];
  }

  static getInstance(): AcControlViewModel {
    if (AcControlViewModel.instance === null) {
      AcControlViewModel.instance = new AcControlViewModel();
    }
    return AcControlViewModel.instance;
  }

  getAppContext(): common.Context | null {
    return this.appContext;
  }

  async init(context?: common.Context): Promise<void> {
    if (context !== undefined) {
      this.appContext = context;
    }
    if (this.initialized) {
      this.refreshNetworkInfo();
      return;
    }
    if (this.initPromise !== null) {
      await this.initPromise;
      this.refreshNetworkInfo();
      return;
    }
    const effectiveContext: common.Context | null = context !== undefined ? context : this.appContext;
    if (effectiveContext === null) {
      return;
    }
    this.initPromise = this.performInit(effectiveContext);
    await this.initPromise;
  }

  private async performInit(effectiveContext: common.Context): Promise<void> {
    try {
      await StorageUtil.getInstance().init(effectiveContext);

      this.selectedCountryCode = await StorageUtil.getInstance().getSelectedCountryCode();
      this.customOverride = await StorageUtil.getInstance().loadCustomServerOverride();
      this.cloudSession = await StorageUtil.getInstance().loadCloudSession();
      this.selectedMac = await StorageUtil.getInstance().getLastSelectedMac();

      GreeLocalService.getInstance().addListener(this.poolListener);
      await GreeLocalService.getInstance().init();
      this.devices = GreeLocalService.getInstance().getDevicesSnapshot();
      this.refreshNetworkInfo();

      await this.refreshCountryRoute(this.selectedCountryCode);

      if (this.cloudSession !== null) {
        GreeLocalService.getInstance().scanLanDevices().catch(() => {});
      }
      this.initialized = true;
      this.refreshDesktopCards();

      hilog.info(DOMAIN, TAG, 'ViewModel initialized with %{public}d cached devices, country=%{public}s',
        this.devices.length, this.selectedCountryCode);
    } finally {
      this.initPromise = null;
    }
  }

  refreshNetworkInfo(): void {
    const info: WifiSubnetInfo = NetworkUtil.getWifiSubnetInfo();
    this.localIp = info.localIp;
    this.broadcastIp = info.subnetBroadcast;
  }

  getSelectedCountry(): GreeCountryItem | null {
    if (this.selectedCountryCode.trim().length === 0) {
      return null;
    }
    return getCountryByCode(this.selectedCountryCode);
  }

  needsInitialLoginGuide(): boolean {
    return this.cloudSession === null && this.devices.length === 0;
  }

  async selectCountry(countryCode: string): Promise<GreeCountryServerRoute | null> {
    const country: GreeCountryItem | null = getCountryByCode(countryCode);
    if (country === null) {
      this.selectedCountryCode = '';
      this.currentRoute = null;
      return null;
    }
    this.selectedCountryCode = country.code;
    await StorageUtil.getInstance().saveSelectedCountryCode(country.code);
    return await this.refreshCountryRoute(country.code);
  }

  async refreshCountryRoute(countryCode: string): Promise<GreeCountryServerRoute | null> {
    if (countryCode.trim().length === 0) {
      this.currentRoute = null;
      return null;
    }
    this.isResolvingRoute = true;
    try {
      const route: GreeCountryServerRoute = await GreeCloudService.getInstance().resolveCountryServer(countryCode);
      this.currentRoute = route;
      return route;
    } finally {
      this.isResolvingRoute = false;
    }
  }

  async saveCustomServerOverride(
    enabled: boolean,
    apiBaseUrl: string,
    mqttHost: string,
    mqttPort: number,
    appId?: string,
    appKey?: string
  ): Promise<GreeCountryServerRoute | null> {
    const override: GreeCustomServerOverride = {
      enabled: enabled,
      apiBaseUrl: apiBaseUrl.trim(),
      mqttHost: mqttHost.trim(),
      mqttPort: mqttPort > 0 ? mqttPort : GREE_MQTT_TLS_PORT,
      appId: appId !== undefined ? appId.trim() : '',
      appKey: appKey !== undefined ? appKey.trim() : ''
    };
    this.customOverride = override;
    await StorageUtil.getInstance().saveCustomServerOverride(override);
    return await this.refreshCountryRoute(this.selectedCountryCode);
  }

  async clearCustomServerOverride(): Promise<GreeCountryServerRoute | null> {
    this.customOverride = null;
    await StorageUtil.getInstance().saveCustomServerOverride(null);
    return await this.refreshCountryRoute(this.selectedCountryCode);
  }

  getSelectedDevice(): GreeDeviceModel | null {
    return this.getDevice(this.selectedMac);
  }

  getDevice(mac: string): GreeDeviceModel | null {
    for (let i: number = 0; i < this.devices.length; i++) {
      if (this.devices[i].mac.toLowerCase() === mac.toLowerCase()) {
        return this.devices[i];
      }
    }
    return null;
  }

  async selectDevice(mac: string): Promise<void> {
    this.selectedMac = mac;
    await StorageUtil.getInstance().saveLastSelectedMac(mac);
  }

  async scanLan(): Promise<void> {
    if (this.isScanning) {
      return;
    }
    this.isScanning = true;
    this.refreshNetworkInfo();
    this.clearStatusBanner();
    try {
      await GreeLocalService.getInstance().scanLanDevices();
    } finally {
      setTimeout(() => {
        this.isScanning = false;
      }, 900);
    }
  }

  async addManualIp(ip: string, customName?: string): Promise<ManualIpProbeResult> {
    this.clearStatusBanner();
    const result: ManualIpProbeResult = await GreeLocalService.getInstance().addOrProbeDeviceByIp(ip, customName);
    if (!result.responded) {
      this.setTransientErrorBanner(result.message);
    }
    return result;
  }

  async renameDevice(mac: string, newName: string): Promise<void> {
    const cleanName: string = newName.trim();
    if (cleanName.length === 0) {
      return;
    }
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }
    device.name = cleanName;
    await GreeLocalService.getInstance().upsertLocalDevice(device);
    this.refreshDesktopCards();
  }

  async removeDevice(mac: string): Promise<void> {
    await GreeLocalService.getInstance().removeDevice(mac);
    if (this.selectedMac.toLowerCase() === mac.toLowerCase()) {
      this.selectedMac = '';
    }
    this.clearStatusBanner();
    this.refreshDesktopCards();
  }

  async refreshSingleDevice(mac: string): Promise<void> {
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }
    const wifiInfo: WifiSubnetInfo = NetworkUtil.getWifiSubnetInfo();
    const hasWifiIp: boolean = wifiInfo.localIp.length > 0;
    this.localIp = wifiInfo.localIp;
    this.broadcastIp = wifiInfo.subnetBroadcast;

    if (hasWifiIp && device.ip.length > 0 && device.isBound && device.onlineChannel !== GreeOnlineChannel.CLOUD) {
      await GreeLocalService.getInstance().requestDeviceStatus(device);
      this.clearStatusBanner();
      this.refreshDesktopCards();
      return;
    }

    if (device.homeId.length > 0 || this.cloudSession !== null) {
      const cloudRes: GreeCloudControlResult = await GreeCloudService.getInstance().fetchRemoteDeviceStatus(device);
      if (cloudRes.tokenExpired) {
        this.needRelogin = true;
      }
      if (cloudRes.success) {
        this.clearStatusBanner();
        this.refreshDesktopCards();
      } else {
        this.setTransientErrorBanner(cloudRes.message);
      }
      return;
    }

    if (device.ip.length > 0) {
      await GreeLocalService.getInstance().addOrProbeDeviceByIp(device.ip, device.name);
      this.refreshDesktopCards();
    }
  }

  async loginCloudAndSync(account: string, password: string, countryCode: string): Promise<GreeCloudSyncResult> {
    this.isSyncingCloud = true;
    const matched: GreeCountryItem | null = getCountryByCode(countryCode);
    this.selectedCountryCode = matched !== null ? matched.code : '';
    try {
      const res: GreeCloudSyncResult = await GreeCloudService.getInstance().loginAndSync(
        account,
        password,
        this.selectedCountryCode
      );
      if (res.success && res.session !== null) {
        this.cloudSession = res.session;
        this.needRelogin = false;
        this.clearStatusBanner();
        this.refreshDesktopCards();
      } else {
        this.setTransientErrorBanner(res.message);
      }
      return res;
    } finally {
      this.isSyncingCloud = false;
    }
  }

  async syncCloudDevicesNow(): Promise<GreeCloudSyncResult> {
    if (this.cloudSession === null) {
      return {
        success: false,
        tokenExpired: true,
        message: '尚未登录 Gree+ 账号，请先登录',
        syncedCount: 0,
        session: null
      };
    }
    this.isSyncingCloud = true;
    try {
      const res: GreeCloudSyncResult = await GreeCloudService.getInstance().syncDevicesForSession(this.cloudSession);
      if (res.tokenExpired) {
        this.needRelogin = true;
      } else if (res.success) {
        this.needRelogin = false;
        this.cloudSession = await StorageUtil.getInstance().loadCloudSession();
      }
      if (res.success) {
        this.clearStatusBanner();
        this.refreshDesktopCards();
      } else {
        this.setTransientErrorBanner(res.message);
      }
      return res;
    } finally {
      this.isSyncingCloud = false;
    }
  }

  async logoutCloud(): Promise<void> {
    await GreeCloudService.getInstance().logout();
    this.cloudSession = null;
    this.needRelogin = false;
    this.clearStatusBanner();
  }

  /**
   * Temperature adjustment with Optimistic UI + 300ms Debounce to prevent flooding
   * UDP/Cloud packets during rapid +/- taps.
   */
  stepTargetTemperature(mac: string, deltaDisplayUnit: number): void {
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }
    const currentDisplay: number = device.getDisplayTargetTemp();
    this.setTargetTemperatureDebounced(mac, currentDisplay + deltaDisplayUnit);
  }

  setTargetTemperatureDebounced(mac: string, targetDisplayTemp: number): void {
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }

    if (this.pendingTempMac !== mac || this.pendingTempSnapshot === null) {
      this.pendingTempMac = mac;
      this.pendingTempSnapshot = device.snapshotState();
    }

    let nextCelsius: number = targetDisplayTemp;
    if (device.temUn === GreeTempUnit.FAHRENHEIT) {
      const clampedF: number = Math.min(MAX_TEMP_F, Math.max(MIN_TEMP_F, Math.round(targetDisplayTemp)));
      nextCelsius = fahrenheitToCelsius(clampedF);
    }
    device.setTem = Math.min(MAX_TEMP_C, Math.max(MIN_TEMP_C, Math.round(nextCelsius)));

    if (this.tempDebounceTimerId !== -1) {
      clearTimeout(this.tempDebounceTimerId);
    }
    this.tempDebounceTimerId = setTimeout(() => {
      this.tempDebounceTimerId = -1;
      const snapToRestore: AcStateSnapshot | null = this.pendingTempSnapshot;
      this.pendingTempSnapshot = null;
      this.pendingTempMac = '';
      this.commitDebouncedTemperature(mac, snapToRestore).catch((err: Object) => {
        hilog.error(DOMAIN, TAG, 'commitDebouncedTemperature error: %{public}s', String(err));
      });
    }, TEMP_DEBOUNCE_MS);
  }

  private async commitDebouncedTemperature(mac: string, rollbackSnap: AcStateSnapshot | null): Promise<void> {
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }
    const ok: boolean = await this.dispatchWithDualChannel(device, ['TemUn', 'SetTem'], [device.temUn, device.setTem]);
    if (!ok && rollbackSnap !== null) {
      device.restoreSnapshot(rollbackSnap);
      return;
    }
    await StorageUtil.getInstance().upsertDevice(device.toPersistedInfo());
  }

  async togglePower(mac: string): Promise<void> {
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }
    const nextPow: number = device.pow === GreePowerState.ON ? GreePowerState.OFF : GreePowerState.ON;
    await this.applyOptimisticAndSend(device, ['Pow'], [nextPow], () => {
      device.pow = nextPow;
    });
  }

  async setMode(mac: string, mode: GreeAcMode): Promise<void> {
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }
    if (device.pow === GreePowerState.OFF) {
      await this.applyOptimisticAndSend(device, ['Pow', 'Mod'], [GreePowerState.ON, mode], () => {
        device.pow = GreePowerState.ON;
        device.mod = mode;
      });
    } else {
      await this.applyOptimisticAndSend(device, ['Mod'], [mode], () => {
        device.mod = mode;
      });
    }
  }

  async setFanSpeed(mac: string, speed: GreeFanSpeed): Promise<void> {
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }
    await this.applyOptimisticAndSend(device, ['WdSpd', 'Quiet', 'Tur'], [speed, 0, 0], () => {
      device.wdSpd = speed;
      device.quiet = 0;
      device.tur = 0;
    });
  }

  async setSwingUpDown(target: string | GreeDeviceModel, level: number): Promise<void> {
    const device: GreeDeviceModel | null = typeof target === 'string'
      ? this.getDevice(target)
      : target;
    if (device === null) {
      return;
    }
    const clamped: number = Math.max(0, Math.min(6, Math.round(level)));
    await this.applyOptimisticAndSend(device, ['SwUpDn'], [clamped], () => {
      device.swUpDn = clamped;
    });
  }

  async setSwingLfRig(target: string | GreeDeviceModel, level: number): Promise<void> {
    const device: GreeDeviceModel | null = typeof target === 'string'
      ? this.getDevice(target)
      : target;
    if (device === null) {
      return;
    }
    const clamped: number = Math.max(0, Math.min(6, Math.round(level)));
    await this.applyOptimisticAndSend(device, ['SwingLfRig'], [clamped], () => {
      device.swingLfRig = clamped;
    });
  }

  async cycleMode(mac: string): Promise<void> {
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }
    const order: GreeAcMode[] = [
      GreeAcMode.COOL,
      GreeAcMode.HEAT,
      GreeAcMode.DRY,
      GreeAcMode.FAN,
      GreeAcMode.AUTO
    ];
    const idx: number = order.indexOf(device.mod as GreeAcMode);
    const nextMode: GreeAcMode = order[(idx + 1) % order.length];
    await this.setMode(device.mac, nextMode);
  }

  async cycleFanSpeed(mac: string): Promise<void> {
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }
    let nextSpeed: GreeFanSpeed = GreeFanSpeed.LOW;
    if (device.wdSpd === GreeFanSpeed.LOW) {
      nextSpeed = GreeFanSpeed.MEDIUM;
    } else if (device.wdSpd === GreeFanSpeed.MEDIUM_LOW || device.wdSpd === GreeFanSpeed.MEDIUM) {
      nextSpeed = GreeFanSpeed.HIGH;
    } else if (device.wdSpd === GreeFanSpeed.MEDIUM_HIGH || device.wdSpd === GreeFanSpeed.HIGH) {
      nextSpeed = GreeFanSpeed.AUTO;
    } else {
      nextSpeed = GreeFanSpeed.LOW;
    }
    await this.setFanSpeed(device.mac, nextSpeed);
  }

  async toggleSwingFull(mac: string): Promise<void> {
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }
    const nextLevel: number = device.swUpDn === GreeSwingUpDown.FULL
      ? GreeSwingUpDown.DEFAULT
      : GreeSwingUpDown.FULL;
    await this.setSwingUpDown(device, nextLevel);
  }

  async bindDeviceToCards(mac: string): Promise<void> {
    if (this.appContext === null || mac.length === 0) {
      return;
    }
    await CardRefreshUtil.bindAllFormsToMac(this.appContext, mac);
  }

  async toggleTempUnit(mac: string): Promise<void> {
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }
    const nextUnit: number = device.temUn === GreeTempUnit.CELSIUS
      ? GreeTempUnit.FAHRENHEIT
      : GreeTempUnit.CELSIUS;
    await this.applyOptimisticAndSend(device, ['TemUn', 'SetTem'], [nextUnit, device.setTem], () => {
      device.temUn = nextUnit;
    });
  }

  async toggleFeature(mac: string, col: string): Promise<void> {
    const device: GreeDeviceModel | null = this.getDevice(mac);
    if (device === null) {
      return;
    }
    let nextVal: number = 1;
    switch (col) {
      case 'Lig':
        nextVal = device.lig === 1 ? 0 : 1;
        await this.applyOptimisticAndSend(device, ['Lig'], [nextVal], () => {
          device.lig = nextVal;
        });
        break;
      case 'SwhSlp':
        nextVal = device.swhSlp === 1 ? 0 : 1;
        await this.applyOptimisticAndSend(device, ['SwhSlp'], [nextVal], () => {
          device.swhSlp = nextVal;
        });
        break;
      case 'Tur':
        nextVal = device.tur === 1 ? 0 : 1;
        await this.applyOptimisticAndSend(device, ['Tur', 'Quiet'], [nextVal, nextVal === 1 ? 0 : device.quiet], () => {
          device.tur = nextVal;
          if (nextVal === 1) {
            device.quiet = 0;
          }
        });
        break;
      case 'Quiet':
        nextVal = device.quiet === 1 ? 0 : 1;
        await this.applyOptimisticAndSend(device, ['Quiet', 'Tur'], [nextVal, nextVal === 1 ? 0 : device.tur], () => {
          device.quiet = nextVal;
          if (nextVal === 1) {
            device.tur = 0;
          }
        });
        break;
      case 'StHt':
        nextVal = device.stHt === 1 ? 0 : 1;
        await this.applyOptimisticAndSend(device, ['StHt'], [nextVal], () => {
          device.stHt = nextVal;
        });
        break;
      case 'Health':
        nextVal = device.health === 1 ? 0 : 1;
        await this.applyOptimisticAndSend(device, ['Health'], [nextVal], () => {
          device.health = nextVal;
        });
        break;
      case 'Blo':
        nextVal = device.blo === 1 ? 0 : 1;
        await this.applyOptimisticAndSend(device, ['Blo'], [nextVal], () => {
          device.blo = nextVal;
        });
        break;
      case 'Air':
        nextVal = device.air === 1 ? 0 : 1;
        await this.applyOptimisticAndSend(device, ['Air'], [nextVal], () => {
          device.air = nextVal;
        });
        break;
      default:
        break;
    }
  }

  private async applyOptimisticAndSend(
    device: GreeDeviceModel,
    opt: string[],
    p: number[],
    mutateOptimistic: () => void
  ): Promise<void> {
    const snap: AcStateSnapshot = device.snapshotState();
    mutateOptimistic();

    const ok: boolean = await this.dispatchWithDualChannel(device, opt, p);
    if (!ok) {
      device.restoreSnapshot(snap);
      return;
    }
    await StorageUtil.getInstance().upsertDevice(device.toPersistedInfo());
  }

  /**
   * Dual-mode router:
   * 1) When Wi-Fi is connected and device is bound on LAN, try zero-latency UDP first.
   * 2) On cellular (no Wi-Fi IPv4) or if LAN fails, immediately route via Cloud MQTT/TLS :1984.
   */
  private async dispatchWithDualChannel(device: GreeDeviceModel, opt: string[], p: number[]): Promise<boolean> {
    const wifiInfo: WifiSubnetInfo = NetworkUtil.getWifiSubnetInfo();
    const hasWifiIp: boolean = wifiInfo.localIp.length > 0;
    this.localIp = wifiInfo.localIp;
    this.broadcastIp = wifiInfo.subnetBroadcast;

    if (hasWifiIp && device.ip.length > 0 && device.key.length > 0 && device.onlineChannel !== GreeOnlineChannel.CLOUD) {
      const lanOk: boolean = await GreeLocalService.getInstance().sendCommand(device, opt, p);
      if (lanOk) {
        device.onlineChannel = GreeOnlineChannel.LAN;
        this.clearStatusBanner();
        this.refreshDesktopCards();
        return true;
      }
      hilog.warn(DOMAIN, TAG, 'LAN UDP failed for %{public}s, falling back to Cloud MQTT', device.mac);
    }

    if (device.homeId.length > 0 || this.cloudSession !== null) {
      const cloudRes: GreeCloudControlResult = await GreeCloudService.getInstance().sendRemoteCommand(device, opt, p);
      if (cloudRes.success) {
        device.onlineChannel = GreeOnlineChannel.CLOUD;
        this.needRelogin = false;
        this.clearStatusBanner();
        this.refreshDesktopCards();
        return true;
      }
      if (cloudRes.tokenExpired) {
        this.needRelogin = true;
      }
      this.setTransientErrorBanner(cloudRes.message);
      return false;
    }

    this.setTransientErrorBanner('设备未响应，请检查网络或登录云端账号');
    return false;
  }

  async destroy(): Promise<void> {
    if (this.tempDebounceTimerId !== -1) {
      clearTimeout(this.tempDebounceTimerId);
      this.tempDebounceTimerId = -1;
    }
    GreeLocalService.getInstance().removeListener(this.poolListener);
    await GreeCloudService.getInstance().disconnectMqtt();
    await GreeLocalService.getInstance().destroy();
    this.initialized = false;
  }
}
