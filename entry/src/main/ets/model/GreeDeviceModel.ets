import {
  GREE_UDP_PORT,
  GreeAcMode,
  GreeFanSpeed,
  GreeOnlineChannel,
  GreePowerState,
  GreeSwingLfRig,
  GreeSwingUpDown,
  GreeTempUnit,
  MAX_TEMP_C,
  MAX_TEMP_F,
  MIN_TEMP_C,
  MIN_TEMP_F,
  TEM_SEN_OFFSET
} from '../common/constants/GreeConstants';
import { DEFAULT_COUNTRY_CODE } from '../common/constants/GreeCountryConfig';
import { PersistedDeviceInfo } from './GreeProtocolTypes';

export interface AcStateSnapshot {
  pow: number;
  mod: number;
  setTem: number;
  temUn: number;
  wdSpd: number;
  swUpDn: number;
  swingLfRig: number;
  quiet: number;
  tur: number;
  lig: number;
  swhSlp: number;
  air: number;
  blo: number;
  health: number;
  stHt: number;
}

/**
 * Calibrates Gree TemSen field:
 * Older firmware versions add a +40 offset (e.g. 66 means 26°C).
 */
export function calibrateIndoorTemp(rawTemSen: number): number {
  if (rawTemSen > TEM_SEN_OFFSET) {
    return rawTemSen - TEM_SEN_OFFSET;
  }
  return rawTemSen;
}

export function celsiusToFahrenheit(tempC: number): number {
  return Math.round((tempC * 9) / 5 + 32);
}

export function fahrenheitToCelsius(tempF: number): number {
  return Math.round(((tempF - 32) * 5) / 9);
}

export function formatModeLabel(mod: number): string {
  switch (mod) {
    case GreeAcMode.AUTO:
      return '自动';
    case GreeAcMode.COOL:
      return '制冷';
    case GreeAcMode.DRY:
      return '除湿';
    case GreeAcMode.FAN:
      return '送风';
    case GreeAcMode.HEAT:
      return '制热';
    default:
      return '制冷';
  }
}

export function formatFanSpeedLabel(wdSpd: number): string {
  switch (wdSpd) {
    case GreeFanSpeed.AUTO:
      return '自动';
    case GreeFanSpeed.LOW:
      return '低风';
    case GreeFanSpeed.MEDIUM_LOW:
      return '中低';
    case GreeFanSpeed.MEDIUM:
      return '中风';
    case GreeFanSpeed.MEDIUM_HIGH:
      return '中高';
    case GreeFanSpeed.HIGH:
      return '强风';
    default:
      return '自动';
  }
}

export function formatSwingLabel(swUpDn: number): string {
  switch (swUpDn) {
    case GreeSwingUpDown.DEFAULT:
      return '关闭扫风';
    case GreeSwingUpDown.FULL:
      return '全幅扫风';
    case GreeSwingUpDown.FIXED_TOP:
      return '定格顶部';
    case GreeSwingUpDown.FIXED_UPPER:
      return '定格中上';
    case GreeSwingUpDown.FIXED_MIDDLE:
      return '定格水平';
    case GreeSwingUpDown.FIXED_LOWER:
      return '定格中下';
    case GreeSwingUpDown.FIXED_BOTTOM:
      return '定格底部';
    default:
      return '全幅扫风';
  }
}

export function formatChannelLabel(channel: GreeOnlineChannel): string {
  switch (channel) {
    case GreeOnlineChannel.LAN:
      return 'LAN 直连';
    case GreeOnlineChannel.CLOUD:
      return 'Cloud 云端';
    case GreeOnlineChannel.OFFLINE:
    default:
      return '离线';
  }
}

/**
 * Reactive ArkUI V2 air conditioner device model.
 */
@ObservedV2
export class GreeDeviceModel {
  @Trace mac: string = '';
  @Trace parentMac: string = '';
  @Trace name: string = 'Gree AC';
  @Trace brand: string = 'gree';
  @Trace model: string = 'Gree+ AC';
  @Trace ver: string = 'V1.0';
  @Trace ip: string = '';
  @Trace port: number = GREE_UDP_PORT;
  @Trace key: string = '';
  @Trace isBound: boolean = false;
  @Trace homeId: string = '';
  @Trace countryCode: string = DEFAULT_COUNTRY_CODE;
  @Trace apiBaseUrl: string = '';
  @Trace mqttHost: string = '';
  @Trace mqttPort: number = 0;
  @Trace onlineChannel: GreeOnlineChannel = GreeOnlineChannel.OFFLINE;
  @Trace lastSeenMs: number = 0;

  @Trace pow: number = GreePowerState.OFF;
  @Trace mod: number = GreeAcMode.COOL;
  @Trace setTem: number = 26;
  @Trace temSenRaw: number = 26;
  @Trace indoorTemp: number = 26;
  @Trace temUn: number = GreeTempUnit.CELSIUS;
  @Trace wdSpd: number = GreeFanSpeed.AUTO;
  @Trace swUpDn: number = GreeSwingUpDown.DEFAULT;
  @Trace swingLfRig: number = GreeSwingLfRig.OFF;
  @Trace quiet: number = 0;
  @Trace tur: number = 0;
  @Trace lig: number = 1;
  @Trace swhSlp: number = 0;
  @Trace air: number = 0;
  @Trace blo: number = 0;
  @Trace health: number = 0;
  @Trace stHt: number = 0;

  constructor(mac: string, name?: string) {
    this.mac = mac;
    if (name !== undefined && name.length > 0) {
      this.name = name;
    }
  }

  getDisplayTargetTemp(): number {
    if (this.temUn === GreeTempUnit.FAHRENHEIT) {
      const tempF: number = celsiusToFahrenheit(this.setTem);
      return Math.min(MAX_TEMP_F, Math.max(MIN_TEMP_F, tempF));
    }
    return Math.min(MAX_TEMP_C, Math.max(MIN_TEMP_C, this.setTem));
  }

  getDisplayIndoorTemp(): number {
    const calibratedC: number = calibrateIndoorTemp(this.temSenRaw);
    if (this.temUn === GreeTempUnit.FAHRENHEIT) {
      return celsiusToFahrenheit(calibratedC);
    }
    return calibratedC;
  }

  getTempUnitSymbol(): string {
    return this.temUn === GreeTempUnit.FAHRENHEIT ? '°F' : '°C';
  }

  /**
   * Maps Gree protocol parallel arrays (`cols`, `dat`) onto reactive properties.
   */
  applyStatusArrays(cols: string[], dat: number[]): void {
    const count: number = Math.min(cols.length, dat.length);
    for (let i: number = 0; i < count; i++) {
      this.applySingleField(cols[i], dat[i]);
    }
  }

  applySingleField(col: string, val: number): void {
    switch (col) {
      case 'Pow':
        this.pow = val;
        break;
      case 'Mod':
        this.mod = val;
        break;
      case 'SetTem':
        this.setTem = Math.min(MAX_TEMP_C, Math.max(MIN_TEMP_C, val));
        break;
      case 'TemSen':
        this.temSenRaw = val;
        this.indoorTemp = calibrateIndoorTemp(val);
        break;
      case 'TemUn':
        this.temUn = val;
        break;
      case 'WdSpd':
        this.wdSpd = val;
        break;
      case 'SwUpDn':
        this.swUpDn = val;
        break;
      case 'SwingLfRig':
        this.swingLfRig = val;
        break;
      case 'Quiet':
        this.quiet = val;
        break;
      case 'Tur':
        this.tur = val;
        break;
      case 'Lig':
        this.lig = val;
        break;
      case 'SwhSlp':
        this.swhSlp = val;
        break;
      case 'Air':
        this.air = val;
        break;
      case 'Blo':
        this.blo = val;
        break;
      case 'Health':
        this.health = val;
        break;
      case 'StHt':
        this.stHt = val;
        break;
      default:
        break;
    }
  }

  snapshotState(): AcStateSnapshot {
    return {
      pow: this.pow,
      mod: this.mod,
      setTem: this.setTem,
      temUn: this.temUn,
      wdSpd: this.wdSpd,
      swUpDn: this.swUpDn,
      swingLfRig: this.swingLfRig,
      quiet: this.quiet,
      tur: this.tur,
      lig: this.lig,
      swhSlp: this.swhSlp,
      air: this.air,
      blo: this.blo,
      health: this.health,
      stHt: this.stHt
    };
  }

  restoreSnapshot(snap: AcStateSnapshot): void {
    this.pow = snap.pow;
    this.mod = snap.mod;
    this.setTem = snap.setTem;
    this.temUn = snap.temUn;
    this.wdSpd = snap.wdSpd;
    this.swUpDn = snap.swUpDn;
    this.swingLfRig = snap.swingLfRig;
    this.quiet = snap.quiet;
    this.tur = snap.tur;
    this.lig = snap.lig;
    this.swhSlp = snap.swhSlp;
    this.air = snap.air;
    this.blo = snap.blo;
    this.health = snap.health;
    this.stHt = snap.stHt;
  }

  toPersistedInfo(): PersistedDeviceInfo {
    return {
      mac: this.mac,
      parentMac: this.parentMac,
      name: this.name,
      brand: this.brand,
      model: this.model,
      ver: this.ver,
      ip: this.ip,
      port: this.port,
      key: this.key,
      isBound: this.isBound,
      homeId: this.homeId,
      countryCode: this.countryCode,
      apiBaseUrl: this.apiBaseUrl,
      mqttHost: this.mqttHost,
      mqttPort: this.mqttPort,
      lastSeenMs: this.lastSeenMs,
      pow: this.pow,
      mod: this.mod,
      setTem: this.setTem,
      temSen: this.temSenRaw,
      temUn: this.temUn,
      wdSpd: this.wdSpd,
      swUpDn: this.swUpDn,
      swingLfRig: this.swingLfRig,
      quiet: this.quiet,
      tur: this.tur,
      lig: this.lig,
      swhSlp: this.swhSlp,
      air: this.air,
      blo: this.blo,
      health: this.health,
      stHt: this.stHt
    };
  }

  static fromPersistedInfo(info: PersistedDeviceInfo): GreeDeviceModel {
    const dev: GreeDeviceModel = new GreeDeviceModel(info.mac, info.name);
    dev.parentMac = info.parentMac !== undefined ? info.parentMac : '';
    dev.brand = info.brand.length > 0 ? info.brand : 'gree';
    dev.model = info.model.length > 0 ? info.model : 'Gree+ AC';
    dev.ver = info.ver.length > 0 ? info.ver : 'V1.0';
    dev.ip = info.ip;
    dev.port = info.port > 0 ? info.port : GREE_UDP_PORT;
    dev.key = info.key;
    dev.isBound = info.isBound || info.key.length > 0;
    dev.homeId = info.homeId;
    dev.countryCode = info.countryCode !== undefined && info.countryCode.length > 0
      ? info.countryCode
      : DEFAULT_COUNTRY_CODE;
    dev.apiBaseUrl = info.apiBaseUrl !== undefined ? info.apiBaseUrl : '';
    dev.mqttHost = info.mqttHost !== undefined ? info.mqttHost : '';
    dev.mqttPort = info.mqttPort !== undefined ? info.mqttPort : 0;
    dev.lastSeenMs = info.lastSeenMs;
    dev.pow = info.pow;
    dev.mod = info.mod;
    dev.setTem = Math.min(MAX_TEMP_C, Math.max(MIN_TEMP_C, info.setTem > 0 ? info.setTem : 26));
    dev.temSenRaw = info.temSen;
    dev.indoorTemp = calibrateIndoorTemp(info.temSen);
    dev.temUn = info.temUn;
    dev.wdSpd = info.wdSpd;
    dev.swUpDn = info.swUpDn;
    dev.swingLfRig = info.swingLfRig !== undefined ? info.swingLfRig : GreeSwingLfRig.OFF;
    dev.quiet = info.quiet;
    dev.tur = info.tur;
    dev.lig = info.lig;
    dev.swhSlp = info.swhSlp;
    dev.air = info.air;
    dev.blo = info.blo;
    dev.health = info.health;
    dev.stHt = info.stHt;
    if (dev.key.length > 0 && dev.ip.length > 0) {
      dev.onlineChannel = GreeOnlineChannel.LAN;
    } else if (dev.key.length > 0 && dev.homeId.length > 0) {
      dev.onlineChannel = GreeOnlineChannel.CLOUD;
    } else {
      dev.onlineChannel = GreeOnlineChannel.OFFLINE;
    }
    return dev;
  }
}
