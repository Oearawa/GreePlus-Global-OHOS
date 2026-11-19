/**
 * Gree+ protocol constants, status field enums, temperature bounds,
 * and verified overseas cloud REST/MQTT & LAN CipherV1/V2 protocol parameters.
 */

export const GREE_UDP_PORT: number = 7000;
export const GREE_GENERIC_KEY: string = 'a3K8Bx%2r8Y7#xDh';
export const GREE_LOCAL_GCM_KEY: string = '{yxAHAY_Lm6pbC/<';
export const GREE_GCM_NONCE_BYTES: number[] = [
  0x54, 0x40, 0x78, 0x44, 0x49, 0x67, 0x5a, 0x51, 0x6c, 0x5e, 0x63, 0x13
];
export const GREE_GCM_AAD: string = 'qualcomm-test';

export const GREE_GLOBAL_BROADCAST: string = '255.255.255.255';
export const GREE_APP_CID: string = 'app';

export const TEM_SEN_OFFSET: number = 40;
export const MIN_TEMP_C: number = 16;
export const MAX_TEMP_C: number = 30;
export const MIN_TEMP_F: number = 61;
export const MAX_TEMP_F: number = 86;

export const POLL_INTERVAL_MS: number = 5000;
export const DEVICE_OFFLINE_THRESHOLD_MS: number = 18000;
export const TEMP_DEBOUNCE_MS: number = 300;
export const CMD_TIMEOUT_MS: number = 1500;
export const CMD_MAX_RETRIES: number = 2;
export const SCAN_RETRY_COUNT: number = 2;

export const GREE_OVERSEAS_APP_ID: string = '4920681951525131286';
export const GREE_OVERSEAS_APP_HASH: string = '0fa513124aa97781d1f3f40d61ca1a89';
export const GREE_CLOUD_API_AES_KEY: string = '#G$&^jgfujy6ujxt';
export const GREE_CLOUD_GAEN1_HEADER: string = '5ac2bdf935bcca70';
export const GREE_MQTT_TLS_PORT: number = 1984;
export const GREE_MQTT_TCP_PORT: number = 1983;
export const GREE_MQTT_ALT_TCP_PORT: number = 1883;

export const GREE_STATUS_COLS: string[] = [
  'Pow',
  'Mod',
  'SetTem',
  'TemSen',
  'TemUn',
  'WdSpd',
  'SwUpDn',
  'SwingLfRig',
  'Quiet',
  'Tur',
  'Lig',
  'SwhSlp',
  'Air',
  'Blo',
  'Health',
  'StHt'
];

export enum GreePowerState {
  OFF = 0,
  ON = 1
}

export enum GreeAcMode {
  AUTO = 0,
  COOL = 1,
  DRY = 2,
  FAN = 3,
  HEAT = 4
}

export enum GreeFanSpeed {
  AUTO = 0,
  LOW = 1,
  MEDIUM_LOW = 2,
  MEDIUM = 3,
  MEDIUM_HIGH = 4,
  HIGH = 5
}

export enum GreeSwingUpDown {
  DEFAULT = 0,
  FULL = 1,
  FIXED_TOP = 2,
  FIXED_UPPER = 3,
  FIXED_MIDDLE = 4,
  FIXED_LOWER = 5,
  FIXED_BOTTOM = 6
}

export enum GreeSwingLfRig {
  OFF = 0,
  FULL = 1,
  FIXED_1 = 2,
  FIXED_2 = 3,
  FIXED_3 = 4,
  FIXED_4 = 5,
  FIXED_5 = 6
}

export enum GreeTempUnit {
  CELSIUS = 0,
  FAHRENHEIT = 1
}

export enum GreeOnlineChannel {
  OFFLINE = 'OFFLINE',
  LAN = 'LAN',
  CLOUD = 'CLOUD'
}
