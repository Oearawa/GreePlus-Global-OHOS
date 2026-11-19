/**
 * Strictly typed DTO interfaces for Gree LAN UDP (port 7000)
 * and verified Overseas Cloud REST (`#G$&^jgfujy6ujxt` + `enRes`) & MQTT/TLS (`:1984`) payloads.
 */

export interface GreeScanPack {
  t: string;
}

export interface GreeOuterPack {
  cid: string;
  i: number;
  pack: string;
  t: string;
  tcid: string;
  uid: number;
  tag?: string;
}

export interface GreeInnerTypeProbe {
  t: string;
}

export interface GreeDevPack {
  t: string;
  cid?: string;
  mac: string;
  name?: string;
  brand?: string;
  model?: string;
  ver?: string;
  series?: string;
  vender?: string;
  lock?: number;
}

export interface GreeBindReqPack {
  mac: string;
  t: string;
  uid: number;
}

export interface GreeBindOkPack {
  t: string;
  mac: string;
  key: string;
  r?: number;
}

export interface GreeStatusReqPack {
  cols: string[];
  mac: string;
  t: string;
}

export interface GreeDatPack {
  t: string;
  mac?: string;
  r?: number;
  cols: string[];
  dat: number[];
}

export interface GreeCmdReqPack {
  opt: string[];
  p: number[];
  t: string;
  mac?: string;
  sub?: string;
}

export interface GreeResPack {
  t: string;
  r?: number;
  opt: string[];
  val?: number[];
  p?: number[];
}

export interface PersistedDeviceInfo {
  mac: string;
  parentMac?: string;
  name: string;
  brand: string;
  model: string;
  ver: string;
  ip: string;
  port: number;
  key: string;
  isBound: boolean;
  homeId: string;
  countryCode: string;
  apiBaseUrl: string;
  mqttHost?: string;
  mqttPort?: number;
  lastSeenMs: number;
  pow: number;
  mod: number;
  setTem: number;
  temSen: number;
  temUn: number;
  wdSpd: number;
  swUpDn: number;
  swingLfRig?: number;
  quiet: number;
  tur: number;
  lig: number;
  swhSlp: number;
  air: number;
  blo: number;
  health: number;
  stHt: number;
}

export interface GreeCountryServerRoute {
  countryCode: string;
  clusterId: string;
  apiBaseUrl: string;
  mqttHost: string;
  mqttPort: number;
  mqttBrokerUrl: string;
  source: string;
}

export interface GreeCustomServerOverride {
  enabled: boolean;
  apiBaseUrl: string;
  mqttHost: string;
  mqttPort: number;
  appId?: string;
  appKey?: string;
}

export interface GreeCloudSessionInfo {
  account: string;
  countryCode: string;
  countryNameZh: string;
  countryNameEn: string;
  apiBaseUrl: string;
  mqttHost: string;
  mqttPort: number;
  token: string;
  uid: string;
  homeId: string;
  homeName: string;
  lastSyncMs: number;
}

export interface GreeCloudApiHeaderDto {
  appId: string;
  r: number;
  t: string;
  vc: string;
}

export interface GreeUserLoginV2BodyDto {
  api: GreeCloudApiHeaderDto;
  datVc: string;
  psw: string;
  t: string;
  user: string;
}

export interface GreeGetHomesBodyDto {
  api: GreeCloudApiHeaderDto;
  datVc: string;
  token: string;
  uid: number;
}

export interface GreeGetDevsInRoomsBodyDto {
  api: GreeCloudApiHeaderDto;
  datVc: string;
  token: string;
  homeId: number | string;
  uid: number;
}

export interface GreeEnResEnvelopeDto {
  enRes?: string;
  r?: number;
  msg?: string;
}

export interface GreeCloudLoginDataDto {
  uid?: number | string;
  token?: string;
  mqttHost?: string;
  mqttPort?: number | string;
  mqHost?: string;
  mqPort?: number | string;
  broker?: string;
  mqttServer?: string;
  mqtt?: string;
  host?: string;
  port?: number | string;
}

export interface GreeDecryptedLoginRespDto {
  r?: number;
  msg?: string;
  uid?: number | string;
  token?: string;
  mqttHost?: string;
  mqttPort?: number | string;
  mqHost?: string;
  mqPort?: number | string;
  broker?: string;
  mqttServer?: string;
  mqtt?: string;
  host?: string;
  port?: number | string;
  data?: GreeCloudLoginDataDto;
}

export interface GreeCloudHomeItemDto {
  id?: number | string;
  homeId?: number | string;
  name?: string;
  mqttHost?: string;
  mqttPort?: number | string;
  mqHost?: string;
  mqPort?: number | string;
  broker?: string;
  mqttServer?: string;
  mqtt?: string;
  host?: string;
  port?: number | string;
}

export interface GreeDecryptedHomesRespDto {
  r?: number;
  msg?: string;
  mqttHost?: string;
  mqttPort?: number | string;
  mqHost?: string;
  mqPort?: number | string;
  broker?: string;
  mqttServer?: string;
  mqtt?: string;
  host?: string;
  port?: number | string;
  home?: GreeCloudHomeItemDto[];
  homes?: GreeCloudHomeItemDto[];
}

export interface GreeRoomDeviceDto {
  mac?: string;
  pmac?: string;
  name?: string;
  devNoteName?: string;
  key?: string;
  mid?: string;
  model?: string;
  ver?: string;
  brand?: string;
  online?: number;
  mqttHost?: string;
  mqttPort?: number | string;
  mqHost?: string;
  mqPort?: number | string;
  broker?: string;
  mqttServer?: string;
  mqtt?: string;
  host?: string;
  port?: number | string;
}

export interface GreeRoomItemDto {
  roomName?: string;
  devs?: GreeRoomDeviceDto[];
}

export interface GreeDecryptedRoomsRespDto {
  r?: number;
  msg?: string;
  mqttHost?: string;
  mqttPort?: number | string;
  mqHost?: string;
  mqPort?: number | string;
  broker?: string;
  mqttServer?: string;
  mqtt?: string;
  host?: string;
  port?: number | string;
  rooms?: GreeRoomItemDto[];
}

export interface GreeCloudDeviceDto {
  mac: string;
  parentMac?: string;
  name: string;
  brand?: string;
  model?: string;
  ver?: string;
  key?: string;
  ip?: string;
  online?: number;
  homeId?: string;
  mqttHost?: string;
  mqttPort?: number;
}

export interface GreeQueryOnlineBodyDto {
  api: GreeCloudApiHeaderDto;
  datVc: string;
  macs: string[];
  token: string;
  uid: number;
}

export interface GreeQueryOnlineItemDto {
  mac?: string;
  svr?: string;
  isSSL?: number | boolean;
}

export interface GreeDecryptedQueryOnlineRespDto {
  r?: number;
  msg?: string;
  online?: GreeQueryOnlineItemDto[];
}

export interface GreeCloudGatewayServer {
  host: string;
  port: number;
  isSsl: boolean;
}

export interface GreeMqttPackEnvelope {
  cid: string;
  i: number;
  pack: string;
  t: string;
  tcid: string;
  uid: number;
  tag?: string;
}

export interface GreeCloudControlResult {
  success: boolean;
  tokenExpired: boolean;
  message: string;
}

export interface GreeCloudSyncResult {
  success: boolean;
  tokenExpired: boolean;
  message: string;
  syncedCount: number;
  session: GreeCloudSessionInfo | null;
}
