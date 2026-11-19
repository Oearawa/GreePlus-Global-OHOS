import { connection, http, socket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  GREE_CLOUD_API_AES_KEY,
  GREE_CLOUD_GAEN1_HEADER,
  GREE_GENERIC_KEY,
  GREE_MQTT_ALT_TCP_PORT,
  GREE_MQTT_TCP_PORT,
  GREE_MQTT_TLS_PORT,
  GREE_OVERSEAS_APP_HASH,
  GREE_OVERSEAS_APP_ID,
  GREE_STATUS_COLS,
  GreeOnlineChannel
} from '../common/constants/GreeConstants';
import {
  getClusterDefaultMqttHost,
  getCountryByCode,
  GREE_ALL_CLOUD_CLUSTERS,
  GreeCountryItem,
  GreeRegionalCluster,
  normalizeMqttBrokerHost
} from '../common/constants/GreeCountryConfig';
import { GreeCryptoUtil } from '../common/utils/GreeCryptoUtil';
import { StorageUtil } from '../common/utils/StorageUtil';
import { GreeDeviceModel } from '../model/GreeDeviceModel';
import {
  GreeCloudApiHeaderDto,
  GreeCloudControlResult,
  GreeCloudDeviceDto,
  GreeCloudGatewayServer,
  GreeCloudHomeItemDto,
  GreeCloudSessionInfo,
  GreeCloudSyncResult,
  GreeCmdReqPack,
  GreeCountryServerRoute,
  GreeCustomServerOverride,
  GreeDatPack,
  GreeDecryptedHomesRespDto,
  GreeDecryptedLoginRespDto,
  GreeDecryptedQueryOnlineRespDto,
  GreeDecryptedRoomsRespDto,
  GreeEnResEnvelopeDto,
  GreeGetDevsInRoomsBodyDto,
  GreeGetHomesBodyDto,
  GreeInnerTypeProbe,
  GreeMqttPackEnvelope,
  GreeQueryOnlineBodyDto,
  GreeQueryOnlineItemDto,
  GreeResPack,
  GreeRoomDeviceDto,
  GreeRoomItemDto,
  GreeStatusReqPack,
  GreeUserLoginV2BodyDto
} from '../model/GreeProtocolTypes';
import { GreeLocalService } from './GreeLocalService';
import { GreeMqttTlsClient, MqttCandidateEndpoint, MqttRequestResult } from './GreeMqttTlsClient';

const DOMAIN: number = 0x4752;
const TAG: string = 'GreeCloudService';
const HTTP_TIMEOUT_MS: number = 15000;
const CROSS_REGION_PROBE_TIMEOUT_MS: number = 4000;
const BAD_CREDENTIALS_CODE: number = 411;

interface HttpRawResponse {
  statusCode: number;
  body: string;
  networkError: string;
}

interface EffectiveAuthConfig {
  appId: string;
  appHash: string;
}

interface LoginAttemptResult {
  success: boolean;
  badCredentials: boolean;
  uid: string;
  token: string;
  mqttHost: string;
  mqttPort: number;
  errorMessage: string;
}

interface MqttEndpoint {
  host: string;
  port: number;
}

interface HomesFetchResult {
  homes: GreeCloudHomeItemDto[];
  mqttHost: string;
  mqttPort: number;
}

interface CachedGatewayEntry {
  server: GreeCloudGatewayServer;
  expiresAtMs: number;
}

type CloudTransportKind = 'mqtt' | 'gateway';

const GATEWAY_CACHE_TTL_MS: number = 300000;
const GATEWAY_IO_TIMEOUT_MS: number = 6000;

/**
 * 1:1 port of the verified Overseas Gree+ Cloud REST API (`#G$&^jgfujy6ujxt` + `enRes`),
 * MQTT-over-TLS (`:1984`) for `ver >= 3.2`, and `/App/QueryOnline` TLS Gateway for `ver < 3.2`.
 */
export class GreeCloudService {
  private static instance: GreeCloudService | null = null;
  private readonly mqttClient: GreeMqttTlsClient = new GreeMqttTlsClient();
  private readonly gatewayCache: Map<string, CachedGatewayEntry> = new Map<string, CachedGatewayEntry>();
  private readonly learnedTransportByMac: Map<string, CloudTransportKind> = new Map<string, CloudTransportKind>();

  private constructor() {
    this.mqttClient.setPushHandler((kind: string, topicMac: string, plainJson: string) => {
      this.handleMqttPush(kind, topicMac, plainJson).catch((err: Object) => {
        hilog.warn(DOMAIN, TAG, 'handleMqttPush error: %{public}s', String(err));
      });
    });
  }

  static getInstance(): GreeCloudService {
    if (GreeCloudService.instance === null) {
      GreeCloudService.instance = new GreeCloudService();
    }
    return GreeCloudService.instance;
  }

  private normalizeBaseUrl(rawUrl: string): string {
    const trimmed: string = rawUrl.trim();
    if (trimmed.length === 0) {
      return '';
    }
    let normalized: string = trimmed;
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = `https://${normalized}`;
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.slice(0, normalized.length - 1);
    }
    return normalized;
  }

  private async getEffectiveAuthConfig(): Promise<EffectiveAuthConfig> {
    const customOverride: GreeCustomServerOverride | null = await StorageUtil.getInstance().loadCustomServerOverride();
    const appId: string = customOverride !== null && customOverride.enabled &&
      customOverride.appId !== undefined && customOverride.appId.trim().length > 0
      ? customOverride.appId.trim()
      : GREE_OVERSEAS_APP_ID;
    const appHash: string = customOverride !== null && customOverride.enabled &&
      customOverride.appKey !== undefined && customOverride.appKey.trim().length > 0
      ? customOverride.appKey.trim()
      : GREE_OVERSEAS_APP_HASH;
    return {
      appId: appId,
      appHash: appHash
    };
  }

  private async buildApiHeader(now: Date): Promise<GreeCloudApiHeaderDto> {
    const auth: EffectiveAuthConfig = await this.getEffectiveAuthConfig();
    const stamp: string = GreeCryptoUtil.formatUtcClientTime(now);
    const ts: number = Math.floor(now.getTime() / 1000);
    const vc: string = await GreeCryptoUtil.computeApiVc(auth.appId, auth.appHash, stamp, ts);
    return {
      appId: auth.appId,
      r: ts,
      t: stamp,
      vc: vc
    };
  }

  private formatHttpError(err: Object | Error | string): string {
    if (typeof err === 'string') {
      const trimmed: string = err.trim();
      return trimmed.length > 0 ? trimmed : '网络连接失败，请检查网络';
    }
    if (err instanceof Error) {
      const msgLower: string = err.message.toLowerCase();
      if (msgLower.includes('timeout') || msgLower.includes('timed out')) {
        return '网络连接超时，请检查网络';
      }
      if (msgLower.includes('resolve') || msgLower.includes('connect') || msgLower.includes('network')) {
        return '网络连接失败，请检查网络';
      }
      return err.message.length > 0 ? err.message : '网络连接失败，请检查网络';
    }
    const errRecord: Record<string, Object> = err as Record<string, Object>;
    const rawCode: Object | undefined = errRecord['code'];
    const rawMsg: Object | undefined = errRecord['message'];
    const codeNum: number = typeof rawCode === 'number' ? rawCode : -1;
    const msgStr: string = typeof rawMsg === 'string' ? rawMsg.trim() : '';

    if (codeNum === 2300028 || msgStr.toLowerCase().includes('timeout')) {
      return '网络连接超时，请检查网络';
    }
    if (codeNum === 2300006 || codeNum === 2300007 || codeNum === 2300056) {
      return '网络连接失败，请检查网络';
    }
    if (msgStr.length > 0) {
      return codeNum > 0 ? `${msgStr} (${codeNum})` : msgStr;
    }
    try {
      const serialized: string = JSON.stringify(err);
      if (serialized !== undefined && serialized.length > 2 && serialized !== '{}') {
        return `网络异常: ${serialized}`;
      }
    } catch {
    }
    return '网络连接失败，请检查网络';
  }

  /**
   * Sends encrypted Base64 body (`AES-128-ECB` with `#G$&^jgfujy6ujxt`) using exact Gree+ headers
   * and decrypts `enRes` from the server response.
   */
  private async postEncryptedCloudApi(
    baseUrl: string,
    endpoint: string,
    bodyJson: string,
    timeoutMs: number = HTTP_TIMEOUT_MS
  ): Promise<HttpRawResponse> {
    const encryptedBody: string = await GreeCryptoUtil.encryptCloudRequestBody(bodyJson, GREE_CLOUD_API_AES_KEY);
    if (encryptedBody.length === 0) {
      return {
        statusCode: 0,
        body: '',
        networkError: '请求数据加密失败'
      };
    }

    const httpClient: http.HttpRequest = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Gaen1': GREE_CLOUD_GAEN1_HEADER,
        'Charset': 'utf-8'
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: encryptedBody,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
      };
      const response: http.HttpResponse = await httpClient.request(`${baseUrl}${endpoint}`, options);
      const rawBody: string = typeof response.result === 'string' ? response.result : String(response.result);
      if (response.responseCode < 200 || response.responseCode >= 300 || rawBody.length === 0) {
        return {
          statusCode: response.responseCode,
          body: rawBody,
          networkError: ''
        };
      }

      let envelope: GreeEnResEnvelopeDto | null = null;
      try {
        envelope = JSON.parse(rawBody) as GreeEnResEnvelopeDto;
      } catch {
        return {
          statusCode: response.responseCode,
          body: rawBody,
          networkError: ''
        };
      }

      if (envelope !== null && typeof envelope.enRes === 'string' && envelope.enRes.length > 0) {
        const decryptedJson: string = await GreeCryptoUtil.decryptCloudEnRes(envelope.enRes, GREE_CLOUD_API_AES_KEY);
        if (decryptedJson.length > 0) {
          hilog.info(DOMAIN, TAG, 'Decrypted %{public}s response (len=%{public}d): %{public}s',
            endpoint, decryptedJson.length, decryptedJson.slice(0, 1800));
        }
        return {
          statusCode: response.responseCode,
          body: decryptedJson.length > 0 ? decryptedJson : rawBody,
          networkError: decryptedJson.length === 0 ? '响应 enRes 解密失败' : ''
        };
      }
      return {
        statusCode: response.responseCode,
        body: rawBody,
        networkError: ''
      };
    } catch (err) {
      const formattedErr: string = this.formatHttpError(err as Object);
      hilog.warn(DOMAIN, TAG, 'HTTP POST failed for %{public}s%{public}s: %{public}s',
        baseUrl, endpoint, formattedErr);
      return {
        statusCode: 0,
        body: '',
        networkError: formattedErr
      };
    } finally {
      httpClient.destroy();
    }
  }

  /**
   * Resolves the verified regional REST & MQTT endpoints for `countryCode`,
   * honoring any custom packet-capture override if enabled.
   */
  async resolveCountryServer(countryCode: string): Promise<GreeCountryServerRoute> {
    const matched: GreeCountryItem | null = getCountryByCode(countryCode);
    const defaultCluster: GreeRegionalCluster = GREE_ALL_CLOUD_CLUSTERS[0];
    const fallbackApi: string = matched !== null ? matched.defaultApiBaseUrl : defaultCluster.apiBaseUrl;
    const fallbackMqttHost: string = matched !== null ? matched.defaultMqttHost : defaultCluster.mqttHost;
    const fallbackMqttPort: number = matched !== null ? matched.defaultMqttPort : defaultCluster.mqttPort;
    const resolvedCode: string = matched !== null ? matched.code : '';
    const resolvedClusterId: string = matched !== null ? matched.clusterId : defaultCluster.clusterId;
    const customOverride: GreeCustomServerOverride | null = await StorageUtil.getInstance().loadCustomServerOverride();

    const hasCustomEndpoint: boolean = customOverride !== null && customOverride.enabled && (
      customOverride.apiBaseUrl.trim().length > 0 ||
      customOverride.mqttHost.trim().length > 0 ||
      customOverride.mqttPort > 0
    );

    if (hasCustomEndpoint && customOverride !== null) {
      const customApi: string = customOverride.apiBaseUrl.trim().length > 0
        ? this.normalizeBaseUrl(customOverride.apiBaseUrl)
        : fallbackApi;
      const customMqttHost: string = customOverride.mqttHost.trim().length > 0
        ? normalizeMqttBrokerHost(customOverride.mqttHost, customApi)
        : getClusterDefaultMqttHost(customApi);
      const customMqttPort: number = customOverride.mqttPort > 0 ? customOverride.mqttPort : GREE_MQTT_TLS_PORT;
      const customScheme: string = (customMqttPort === GREE_MQTT_TCP_PORT || customMqttPort === GREE_MQTT_ALT_TCP_PORT)
        ? 'tcp'
        : 'ssl';
      return {
        countryCode: resolvedCode,
        clusterId: 'custom-override',
        apiBaseUrl: customApi,
        mqttHost: customMqttHost,
        mqttPort: customMqttPort,
        mqttBrokerUrl: `${customScheme}://${customMqttHost}:${customMqttPort}`,
        source: '抓包自定义覆盖'
      };
    }

    const defaultHost: string = normalizeMqttBrokerHost(fallbackMqttHost, fallbackApi);
    const defaultPort: number = fallbackMqttPort > 0 ? fallbackMqttPort : GREE_MQTT_TLS_PORT;
    const defaultScheme: string = (defaultPort === GREE_MQTT_TCP_PORT || defaultPort === GREE_MQTT_ALT_TCP_PORT)
      ? 'tcp'
      : 'ssl';
    return {
      countryCode: resolvedCode,
      clusterId: resolvedClusterId,
      apiBaseUrl: fallbackApi,
      mqttHost: defaultHost,
      mqttPort: defaultPort,
      mqttBrokerUrl: `${defaultScheme}://${defaultHost}:${defaultPort}`,
      source: '官方海外区域集群映射'
    };
  }

  private parseBrokerEndpoint(hostCandidates: (string | undefined)[], portCandidates: (number | string | undefined)[]): MqttEndpoint {
    let rawHost: string = '';
    for (let i: number = 0; i < hostCandidates.length; i++) {
      const candidate: string | undefined = hostCandidates[i];
      if (candidate !== undefined && candidate.trim().length > 0) {
        rawHost = candidate.trim();
        break;
      }
    }

    let parsedPort: number = 0;
    for (let i: number = 0; i < portCandidates.length; i++) {
      const pVal: number | string | undefined = portCandidates[i];
      if (pVal !== undefined) {
        const numeric: number = typeof pVal === 'number' ? pVal : Number(String(pVal).trim());
        if (!Number.isNaN(numeric) && numeric > 0 && numeric <= 65535) {
          parsedPort = Math.floor(numeric);
          break;
        }
      }
    }

    if (rawHost.length === 0) {
      return { host: '', port: parsedPort };
    }

    let cleaned: string = rawHost;
    const schemeIdx: number = cleaned.indexOf('://');
    if (schemeIdx >= 0) {
      cleaned = cleaned.slice(schemeIdx + 3);
    }
    const slashIdx: number = cleaned.indexOf('/');
    if (slashIdx >= 0) {
      cleaned = cleaned.slice(0, slashIdx);
    }
    const colonIdx: number = cleaned.lastIndexOf(':');
    if (colonIdx > 0 && colonIdx < cleaned.length - 1) {
      const inlinePort: number = Number(cleaned.slice(colonIdx + 1));
      if (!Number.isNaN(inlinePort) && inlinePort > 0 && inlinePort <= 65535) {
        cleaned = cleaned.slice(0, colonIdx);
        if (parsedPort === 0) {
          parsedPort = Math.floor(inlinePort);
        }
      }
    }

    const lowerHost: string = cleaned.toLowerCase();
    if (lowerHost.endsWith('grih.gree.com') || lowerHost.startsWith('192.168.') || lowerHost.startsWith('10.')) {
      return { host: '', port: 0 };
    }
    return {
      host: cleaned,
      port: parsedPort
    };
  }

  private async attemptLoginAtServer(
    baseUrl: string,
    account: string,
    password: string,
    timeoutMs: number = HTTP_TIMEOUT_MS
  ): Promise<LoginAttemptResult> {
    const now: Date = new Date();
    const apiHeader: GreeCloudApiHeaderDto = await this.buildApiHeader(now);
    const auth: EffectiveAuthConfig = await this.getEffectiveAuthConfig();
    const stamp: string = apiHeader.t;
    const psw: string = await GreeCryptoUtil.computeLoginPasswordHash(password, stamp);
    if (psw.length === 0) {
      return {
        success: false,
        badCredentials: false,
        uid: '',
        token: '',
        mqttHost: '',
        mqttPort: 0,
        errorMessage: '密码三重 MD5 摘要计算失败'
      };
    }

    const datVc: string = await GreeCryptoUtil.computeDatVc(auth.appHash, [account, psw, stamp]);
    const loginBody: GreeUserLoginV2BodyDto = {
      api: apiHeader,
      datVc: datVc,
      psw: psw,
      t: stamp,
      user: account
    };

    const raw: HttpRawResponse = await this.postEncryptedCloudApi(
      baseUrl,
      '/App/UserLoginV2',
      JSON.stringify(loginBody),
      timeoutMs
    );
    if (raw.statusCode === 0 || raw.body.length === 0) {
      return {
        success: false,
        badCredentials: false,
        uid: '',
        token: '',
        mqttHost: '',
        mqttPort: 0,
        errorMessage: raw.networkError.length > 0 ? raw.networkError : '网络连接失败，请检查网络'
      };
    }
    if (raw.statusCode < 200 || raw.statusCode >= 300) {
      return {
        success: false,
        badCredentials: false,
        uid: '',
        token: '',
        mqttHost: '',
        mqttPort: 0,
        errorMessage: `HTTP ${raw.statusCode} (${baseUrl}): ${raw.body}`
      };
    }

    let resp: GreeDecryptedLoginRespDto | null = null;
    try {
      resp = JSON.parse(raw.body) as GreeDecryptedLoginRespDto;
    } catch {
      return {
        success: false,
        badCredentials: false,
        uid: '',
        token: '',
        mqttHost: '',
        mqttPort: 0,
        errorMessage: `登录响应 JSON 解析失败: ${raw.body}`
      };
    }

    if (resp === null) {
      return {
        success: false,
        badCredentials: false,
        uid: '',
        token: '',
        mqttHost: '',
        mqttPort: 0,
        errorMessage: '云端登录响应为空'
      };
    }

    const rCode: number = resp.r !== undefined ? resp.r : -1;
    const msg: string = resp.msg !== undefined ? resp.msg : '';
    if (rCode === BAD_CREDENTIALS_CODE) {
      return {
        success: false,
        badCredentials: true,
        uid: '',
        token: '',
        mqttHost: '',
        mqttPort: 0,
        errorMessage: '账号或密码错误'
      };
    }
    if (rCode !== 200) {
      return {
        success: false,
        badCredentials: false,
        uid: '',
        token: '',
        mqttHost: '',
        mqttPort: 0,
        errorMessage: msg.length > 0 ? `[${rCode}] ${msg}` : `登录失败 (r=${rCode})`
      };
    }

    const uidRaw: number | string | undefined = resp.uid !== undefined
      ? resp.uid
      : (resp.data !== undefined ? resp.data.uid : undefined);
    const tokenRaw: string | undefined = resp.token !== undefined
      ? resp.token
      : (resp.data !== undefined ? resp.data.token : undefined);

    const uidStr: string = uidRaw !== undefined ? String(uidRaw) : '';
    const tokenStr: string = tokenRaw !== undefined ? String(tokenRaw) : '';
    if (uidStr.length === 0 || tokenStr.length === 0) {
      return {
        success: false,
        badCredentials: false,
        uid: '',
        token: '',
        mqttHost: '',
        mqttPort: 0,
        errorMessage: '登录响应缺少 uid 或 token'
      };
    }

    const loginBroker: MqttEndpoint = this.parseBrokerEndpoint(
      [
        resp.mqttHost,
        resp.mqHost,
        resp.mqttServer,
        resp.broker,
        resp.mqtt,
        resp.data?.mqttHost,
        resp.data?.mqHost,
        resp.data?.mqttServer,
        resp.data?.broker,
        resp.data?.mqtt,
        resp.host,
        resp.data?.host
      ],
      [
        resp.mqttPort,
        resp.mqPort,
        resp.data?.mqttPort,
        resp.data?.mqPort,
        resp.port,
        resp.data?.port
      ]
    );
    if (loginBroker.host.length > 0 || loginBroker.port > 0) {
      hilog.info(DOMAIN, TAG, 'UserLoginV2 dynamic MQTT broker: %{public}s:%{public}d',
        loginBroker.host, loginBroker.port);
    }

    return {
      success: true,
      badCredentials: false,
      uid: uidStr,
      token: tokenStr,
      mqttHost: loginBroker.host,
      mqttPort: loginBroker.port,
      errorMessage: ''
    };
  }

  /**
   * Logs in via `/App/UserLoginV2`. If the selected country's server returns `r === 411`
   * (because Gree+ accounts belong to a single regional cluster), automatically probes
   * the remaining verified clusters unless a custom server override is active.
   */
  async loginAndSync(account: string, password: string, countryCode: string): Promise<GreeCloudSyncResult> {
    const cleanAccount: string = account.trim();
    if (cleanAccount.length === 0 || password.length === 0) {
      return {
        success: false,
        tokenExpired: false,
        message: '请输入海外 Gree+ 账号（邮箱或手机号）与密码',
        syncedCount: 0,
        session: null
      };
    }

    const country: GreeCountryItem | null = getCountryByCode(countryCode);
    if (country === null) {
      return {
        success: false,
        tokenExpired: false,
        message: '请先选择国家/地区',
        syncedCount: 0,
        session: null
      };
    }
    await StorageUtil.getInstance().saveSelectedCountryCode(country.code);
    const primaryRoute: GreeCountryServerRoute = await this.resolveCountryServer(country.code);
    const customOverride: GreeCustomServerOverride | null = await StorageUtil.getInstance().loadCustomServerOverride();
    const isCustomOverrideActive: boolean = customOverride !== null && customOverride.enabled &&
      customOverride.apiBaseUrl.trim().length > 0;

    let activeApiUrl: string = primaryRoute.apiBaseUrl;
    let activeMqttHost: string = primaryRoute.mqttHost;
    let activeMqttPort: number = primaryRoute.mqttPort;
    let loginAttempt: LoginAttemptResult = await this.attemptLoginAtServer(activeApiUrl, cleanAccount, password);

    if (!loginAttempt.success && loginAttempt.badCredentials && !isCustomOverrideActive) {
      let anyClusterReached: boolean = true;
      let lastNetworkError: string = '';

      for (let i: number = 0; i < GREE_ALL_CLOUD_CLUSTERS.length; i++) {
        const cluster: GreeRegionalCluster = GREE_ALL_CLOUD_CLUSTERS[i];
        if (cluster.apiBaseUrl === primaryRoute.apiBaseUrl) {
          continue;
        }
        hilog.info(DOMAIN, TAG, 'Primary server returned 411, probing regional cluster %{public}s',
          cluster.apiBaseUrl);
        try {
          const fallbackAttempt: LoginAttemptResult = await this.attemptLoginAtServer(
            cluster.apiBaseUrl,
            cleanAccount,
            password,
            CROSS_REGION_PROBE_TIMEOUT_MS
          );
          if (fallbackAttempt.success) {
            loginAttempt = fallbackAttempt;
            activeApiUrl = cluster.apiBaseUrl;
            activeMqttHost = cluster.mqttHost;
            activeMqttPort = cluster.mqttPort;
            break;
          }
          if (fallbackAttempt.badCredentials) {
            anyClusterReached = true;
          } else {
            lastNetworkError = fallbackAttempt.errorMessage;
            hilog.warn(DOMAIN, TAG, 'Cluster %{public}s probe failed (continuing): %{public}s',
              cluster.apiBaseUrl, fallbackAttempt.errorMessage);
            continue;
          }
        } catch (err) {
          const formattedErr: string = this.formatHttpError(err as Object);
          lastNetworkError = formattedErr;
          hilog.warn(DOMAIN, TAG, 'Cluster %{public}s probe threw error (continuing): %{public}s',
            cluster.apiBaseUrl, formattedErr);
          continue;
        }
      }

      if (!loginAttempt.success && !anyClusterReached && lastNetworkError.length > 0) {
        loginAttempt = {
          success: false,
          badCredentials: false,
          uid: '',
          token: '',
          mqttHost: '',
          mqttPort: 0,
          errorMessage: lastNetworkError
        };
      }
    }

    if (!loginAttempt.success) {
      return {
        success: false,
        tokenExpired: false,
        message: loginAttempt.badCredentials
          ? '未找到该账号所属区域，请确认邮箱与密码'
          : loginAttempt.errorMessage,
        syncedCount: 0,
        session: null
      };
    }

    if (loginAttempt.mqttHost.length > 0 && !isCustomOverrideActive) {
      activeMqttHost = loginAttempt.mqttHost;
    }
    if (loginAttempt.mqttPort > 0 && !isCustomOverrideActive) {
      activeMqttPort = loginAttempt.mqttPort;
    }

    const homesResult: HomesFetchResult = await this.fetchUserHomes(
      activeApiUrl,
      loginAttempt.uid,
      loginAttempt.token
    );
    if (homesResult.mqttHost.length > 0 && !isCustomOverrideActive) {
      activeMqttHost = homesResult.mqttHost;
    }
    if (homesResult.mqttPort > 0 && !isCustomOverrideActive) {
      activeMqttPort = homesResult.mqttPort;
    }

    const homes: GreeCloudHomeItemDto[] = homesResult.homes;
    const primaryHomeId: string = homes.length > 0 ? this.getHomeId(homes[0]) : '';
    const primaryHomeName: string = homes.length > 0 && homes[0].name !== undefined && homes[0].name.length > 0
      ? homes[0].name
      : `${country.nameEn} Home`;

    const resolvedMqttHost: string = normalizeMqttBrokerHost(activeMqttHost, activeApiUrl);
    const session: GreeCloudSessionInfo = {
      account: cleanAccount,
      countryCode: country.code,
      countryNameZh: country.nameZh,
      countryNameEn: country.nameEn,
      apiBaseUrl: activeApiUrl,
      mqttHost: resolvedMqttHost,
      mqttPort: activeMqttPort > 0 ? activeMqttPort : GREE_MQTT_TLS_PORT,
      token: loginAttempt.token,
      uid: loginAttempt.uid,
      homeId: primaryHomeId,
      homeName: primaryHomeName,
      lastSyncMs: Date.now()
    };

    await StorageUtil.getInstance().saveCloudSession(session);
    const syncRes: GreeCloudSyncResult = await this.syncDevicesForSession(session, homes);
    return {
      success: syncRes.success,
      tokenExpired: syncRes.tokenExpired,
      message: syncRes.success
        ? `已登录并同步 ${syncRes.syncedCount} 台设备`
        : syncRes.message,
      syncedCount: syncRes.syncedCount,
      session: session
    };
  }

  private getHomeId(home: GreeCloudHomeItemDto): string {
    if (home.id !== undefined) {
      return String(home.id);
    }
    if (home.homeId !== undefined) {
      return String(home.homeId);
    }
    return '';
  }

  private async fetchUserHomes(
    apiBaseUrl: string,
    uid: string,
    token: string
  ): Promise<HomesFetchResult> {
    const now: Date = new Date();
    const apiHeader: GreeCloudApiHeaderDto = await this.buildApiHeader(now);
    const auth: EffectiveAuthConfig = await this.getEffectiveAuthConfig();
    const numericUid: number = Number(uid);
    const uidNum: number = Number.isNaN(numericUid) ? 0 : numericUid;
    const datVc: string = await GreeCryptoUtil.computeDatVc(auth.appHash, [token, String(uidNum)]);

    const homesBody: GreeGetHomesBodyDto = {
      api: apiHeader,
      datVc: datVc,
      token: token,
      uid: uidNum
    };

    const raw: HttpRawResponse = await this.postEncryptedCloudApi(
      apiBaseUrl,
      '/App/GetHomes',
      JSON.stringify(homesBody)
    );
    if (raw.statusCode < 200 || raw.statusCode >= 300 || raw.body.length === 0) {
      return { homes: [], mqttHost: '', mqttPort: 0 };
    }
    try {
      const resp: GreeDecryptedHomesRespDto = JSON.parse(raw.body) as GreeDecryptedHomesRespDto;
      if (resp !== null && resp.r === 200) {
        const homeList: GreeCloudHomeItemDto[] = Array.isArray(resp.home)
          ? resp.home
          : (Array.isArray(resp.homes) ? resp.homes : []);
        const firstHome: GreeCloudHomeItemDto | undefined = homeList.length > 0 ? homeList[0] : undefined;
        const homesBroker: MqttEndpoint = this.parseBrokerEndpoint(
          [
            resp.mqttHost,
            resp.mqHost,
            resp.mqttServer,
            resp.broker,
            resp.mqtt,
            firstHome?.mqttHost,
            firstHome?.mqHost,
            firstHome?.mqttServer,
            firstHome?.broker,
            firstHome?.mqtt,
            resp.host,
            firstHome?.host
          ],
          [
            resp.mqttPort,
            resp.mqPort,
            firstHome?.mqttPort,
            firstHome?.mqPort,
            resp.port,
            firstHome?.port
          ]
        );
        if (homesBroker.host.length > 0 || homesBroker.port > 0) {
          hilog.info(DOMAIN, TAG, 'GetHomes dynamic MQTT broker: %{public}s:%{public}d',
            homesBroker.host, homesBroker.port);
        }
        return {
          homes: homeList,
          mqttHost: homesBroker.host,
          mqttPort: homesBroker.port
        };
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'GetHomes parse warning: %{public}s', String(err));
    }
    return { homes: [], mqttHost: '', mqttPort: 0 };
  }

  async syncDevicesForSession(
    session: GreeCloudSessionInfo,
    knownHomes?: GreeCloudHomeItemDto[]
  ): Promise<GreeCloudSyncResult> {
    let homes: GreeCloudHomeItemDto[] = knownHomes !== undefined ? knownHomes : [];
    if (homes.length === 0) {
      const homesResult: HomesFetchResult = await this.fetchUserHomes(session.apiBaseUrl, session.uid, session.token);
      homes = homesResult.homes;
      if (homesResult.mqttHost.length > 0) {
        session.mqttHost = homesResult.mqttHost;
      }
      if (homesResult.mqttPort > 0) {
        session.mqttPort = homesResult.mqttPort;
      }
    }

    if (homes.length === 0 && session.homeId.length === 0) {
      return {
        success: false,
        tokenExpired: false,
        message: `未能从 ${session.apiBaseUrl} 获取到家庭列表，请检查登录状态`,
        syncedCount: 0,
        session: session
      };
    }

    const targetHomes: GreeCloudHomeItemDto[] = homes.length > 0
      ? homes
      : [{ id: session.homeId, name: session.homeName }];

    const collected: GreeCloudDeviceDto[] = [];
    let tokenExpired: boolean = false;
    let reachableHomes: number = 0;
    let lastServerErr: string = '';

    const numericUid: number = Number(session.uid);
    const uidNum: number = Number.isNaN(numericUid) ? 0 : numericUid;
    const auth: EffectiveAuthConfig = await this.getEffectiveAuthConfig();

    for (let i: number = 0; i < targetHomes.length; i++) {
      const homeIdStr: string = this.getHomeId(targetHomes[i]);
      if (homeIdStr.length === 0) {
        continue;
      }
      const homeIdVal: number | string = targetHomes[i].id !== undefined
        ? targetHomes[i].id!
        : homeIdStr;

      const now: Date = new Date();
      const apiHeader: GreeCloudApiHeaderDto = await this.buildApiHeader(now);
      const datVc: string = await GreeCryptoUtil.computeDatVc(auth.appHash, [
        session.token,
        String(uidNum),
        String(homeIdVal)
      ]);
      const devsBody: GreeGetDevsInRoomsBodyDto = {
        api: apiHeader,
        datVc: datVc,
        token: session.token,
        homeId: homeIdVal,
        uid: uidNum
      };

      const raw: HttpRawResponse = await this.postEncryptedCloudApi(
        session.apiBaseUrl,
        '/App/GetDevsInRoomsOfHomeV2',
        JSON.stringify(devsBody)
      );
      if (raw.statusCode === 0 || raw.body.length === 0) {
        continue;
      }
      if (raw.statusCode === 401 || raw.statusCode === 403) {
        tokenExpired = true;
        break;
      }
      reachableHomes++;
      try {
        const roomsResp: GreeDecryptedRoomsRespDto = JSON.parse(raw.body) as GreeDecryptedRoomsRespDto;
        if (roomsResp === null) {
          continue;
        }
        const rCode: number = roomsResp.r !== undefined ? roomsResp.r : -1;
        if (rCode === BAD_CREDENTIALS_CODE || rCode === 401 || rCode === 1004 || rCode === 1005) {
          tokenExpired = true;
          lastServerErr = roomsResp.msg ?? '';
          break;
        }
        if (rCode !== 200) {
          lastServerErr = roomsResp.msg !== undefined ? `[${rCode}] ${roomsResp.msg}` : `[${rCode}]`;
          continue;
        }
        const respBroker: MqttEndpoint = this.parseBrokerEndpoint(
          [roomsResp.mqttHost, roomsResp.mqHost, roomsResp.mqttServer, roomsResp.broker, roomsResp.mqtt, roomsResp.host],
          [roomsResp.mqttPort, roomsResp.mqPort, roomsResp.port]
        );
        if (respBroker.host.length > 0 && session.mqttHost.length === 0) {
          session.mqttHost = respBroker.host;
        }
        if (respBroker.port > 0) {
          session.mqttPort = respBroker.port;
        }

        const rooms: GreeRoomItemDto[] = Array.isArray(roomsResp.rooms) ? roomsResp.rooms : [];
        for (let rIdx: number = 0; rIdx < rooms.length; rIdx++) {
          const devs: GreeRoomDeviceDto[] = Array.isArray(rooms[rIdx].devs) ? rooms[rIdx].devs! : [];
          for (let dIdx: number = 0; dIdx < devs.length; dIdx++) {
            const rawDev: GreeRoomDeviceDto = devs[dIdx];
            const mac: string = rawDev.mac !== undefined ? rawDev.mac.trim().toLowerCase() : '';
            const parentMac: string = rawDev.pmac !== undefined ? rawDev.pmac.trim().toLowerCase() : '';
            const key: string = rawDev.key !== undefined ? rawDev.key.trim() : '';
            hilog.info(DOMAIN, TAG,
              'Synced dev mac=%{public}s pmac=%{public}s ver=%{public}s mid=%{public}s model=%{public}s online=%{public}d keyLen=%{public}d',
              mac, parentMac, rawDev.ver ?? '', rawDev.mid ?? '', rawDev.model ?? '', rawDev.online ?? -1, key.length);
            if (mac.length === 0 || key.length !== 16) {
              continue;
            }
            const devBroker: MqttEndpoint = this.parseBrokerEndpoint(
              [rawDev.mqttHost, rawDev.mqHost, rawDev.mqttServer, rawDev.broker, rawDev.mqtt, rawDev.host, respBroker.host],
              [rawDev.mqttPort, rawDev.mqPort, rawDev.port, respBroker.port]
            );
            const noteName: string = rawDev.devNoteName !== undefined ? rawDev.devNoteName.trim() : '';
            const origName: string = rawDev.name !== undefined ? rawDev.name.trim() : '';
            const displayName: string = noteName.length > 0 ? noteName : (origName.length > 0 ? origName : mac);
            collected.push({
              mac: mac,
              parentMac: parentMac,
              name: displayName,
              brand: rawDev.brand,
              model: rawDev.model !== undefined && rawDev.model.length > 0 ? rawDev.model : rawDev.mid,
              ver: rawDev.ver,
              key: key,
              online: rawDev.online,
              homeId: homeIdStr,
              mqttHost: devBroker.host,
              mqttPort: devBroker.port
            });
            this.mqttClient.registerDeviceKey(mac, key);
            if (parentMac.length > 0) {
              this.mqttClient.registerDeviceKey(parentMac, key);
            }
          }
        }
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'GetDevsInRoomsOfHomeV2 parse warning: %{public}s', String(err));
      }
    }

    if (tokenExpired) {
      return {
        success: false,
        tokenExpired: true,
        message: lastServerErr.length > 0
          ? `登录 Token 已过期: ${lastServerErr}`
          : '云端登录 Token 已过期，请重新登录 Gree+ 账号',
        syncedCount: 0,
        session: session
      };
    }

    if (reachableHomes === 0 && collected.length === 0) {
      return {
        success: false,
        tokenExpired: false,
        message: lastServerErr.length > 0
          ? lastServerErr
          : `无法从 ${session.apiBaseUrl} 拉取设备列表，请检查网络或重新登录`,
        syncedCount: 0,
        session: session
      };
    }

    const deduplicated: GreeCloudDeviceDto[] = this.deduplicateDevicesByKey(collected);
    session.lastSyncMs = Date.now();
    await StorageUtil.getInstance().saveCloudSession(session);
    const mergedCount: number = await GreeLocalService.getInstance().mergeCloudDevices(
      deduplicated,
      session.countryCode,
      session.apiBaseUrl
    );

    return {
      success: true,
      tokenExpired: false,
      message: `已同步 ${mergedCount} 台设备`,
      syncedCount: mergedCount,
      session: session
    };
  }

  /**
   * Deduplicates multi-endpoint devices sharing a key, preferring `<mac>00` when present
   * (matching `cloud_api.py` `_deduplicate`).
   */
  private deduplicateDevicesByKey(devices: GreeCloudDeviceDto[]): GreeCloudDeviceDto[] {
    const byKey: Map<string, GreeCloudDeviceDto[]> = new Map<string, GreeCloudDeviceDto[]>();
    for (let i: number = 0; i < devices.length; i++) {
      const key: string = devices[i].key ?? devices[i].mac;
      const existing: GreeCloudDeviceDto[] | undefined = byKey.get(key);
      if (existing === undefined) {
        byKey.set(key, [devices[i]]);
      } else {
        existing.push(devices[i]);
      }
    }

    const result: GreeCloudDeviceDto[] = [];
    byKey.forEach((group: GreeCloudDeviceDto[]) => {
      const preferred: GreeCloudDeviceDto[] = [];
      for (let i: number = 0; i < group.length; i++) {
        if (group[i].mac.length > 12 && group[i].mac.endsWith('00')) {
          preferred.push(group[i]);
        }
      }
      const chosen: GreeCloudDeviceDto[] = preferred.length > 0 ? preferred : group;
      for (let i: number = 0; i < chosen.length; i++) {
        result.push(chosen[i]);
      }
    });
    return result;
  }

  private resolveSessionMqttEndpoint(session: GreeCloudSessionInfo): MqttEndpoint {
    const rawHost: string = normalizeMqttBrokerHost(session.mqttHost, session.apiBaseUrl);
    const rawPort: number = session.mqttPort > 0 ? session.mqttPort : GREE_MQTT_TLS_PORT;
    if (rawHost.length > 0 && !rawHost.toLowerCase().endsWith('.grih.gree.com')) {
      return { host: rawHost, port: rawPort };
    }
    for (let i: number = 0; i < GREE_ALL_CLOUD_CLUSTERS.length; i++) {
      if (GREE_ALL_CLOUD_CLUSTERS[i].apiBaseUrl === session.apiBaseUrl) {
        return {
          host: GREE_ALL_CLOUD_CLUSTERS[i].mqttHost,
          port: GREE_ALL_CLOUD_CLUSTERS[i].mqttPort
        };
      }
    }
    const country: GreeCountryItem | null = getCountryByCode(session.countryCode);
    if (country !== null) {
      return {
        host: country.defaultMqttHost,
        port: country.defaultMqttPort
      };
    }
    return {
      host: GREE_ALL_CLOUD_CLUSTERS[0].mqttHost,
      port: GREE_ALL_CLOUD_CLUSTERS[0].mqttPort
    };
  }

  private buildMqttCandidates(
    device: GreeDeviceModel,
    session: GreeCloudSessionInfo,
    customOverride: GreeCustomServerOverride | null
  ): MqttCandidateEndpoint[] {
    const candidates: MqttCandidateEndpoint[] = [];
    const seen: Set<string> = new Set<string>();

    const pushCandidate = (rawHost: string, rawPort: number, forceUseTls?: boolean): void => {
      const normalizedHost: string = normalizeMqttBrokerHost(rawHost, session.apiBaseUrl);
      if (normalizedHost.length === 0) {
        return;
      }
      const port: number = rawPort > 0 ? rawPort : GREE_MQTT_TLS_PORT;
      const useTls: boolean = forceUseTls !== undefined
        ? forceUseTls
        : (port !== GREE_MQTT_TCP_PORT && port !== GREE_MQTT_ALT_TCP_PORT);
      const key: string = `${useTls ? 'tls' : 'tcp'}://${normalizedHost.toLowerCase()}:${port}`;
      if (seen.has(key)) {
        return;
      }
      seen.add(key);
      candidates.push({
        host: normalizedHost,
        port: port,
        useTls: useTls
      });
    };

    if (customOverride !== null && customOverride.enabled && customOverride.mqttHost.trim().length > 0) {
      const customPort: number = customOverride.mqttPort > 0 ? customOverride.mqttPort : GREE_MQTT_TLS_PORT;
      pushCandidate(customOverride.mqttHost, customPort);
    }

    if (device.mqttHost.trim().length > 0) {
      const devPort: number = device.mqttPort > 0 ? device.mqttPort : GREE_MQTT_TLS_PORT;
      pushCandidate(device.mqttHost, devPort);
    }

    const sessionEndpoint: MqttEndpoint = this.resolveSessionMqttEndpoint(session);
    pushCandidate(sessionEndpoint.host, sessionEndpoint.port);

    const clusterHost: string = getClusterDefaultMqttHost(session.apiBaseUrl);
    pushCandidate(clusterHost, GREE_MQTT_TLS_PORT, true);

    if (clusterHost.toLowerCase() !== 'mqtt-hk.gree.com') {
      pushCandidate('mqtt-hk.gree.com', GREE_MQTT_TLS_PORT, true);
    }
    return candidates;
  }

  /**
   * Sends an AES-128-ECB encrypted `cmd` packet via Cloud MQTT (`:1984`) or `/App/QueryOnline` Gateway.
   */
  async sendRemoteCommand(
    device: GreeDeviceModel,
    opt: string[],
    p: number[]
  ): Promise<GreeCloudControlResult> {
    const normalizedMac: string = GreeMqttTlsClient.normalizeMac(device.mac);
    const innerCmd: GreeCmdReqPack = {
      mac: normalizedMac,
      opt: opt,
      p: p,
      t: 'cmd'
    };
    return await this.dispatchCloudRequest(device, JSON.stringify(innerCmd), false);
  }

  /**
   * Queries current device status via Cloud MQTT (`:1984`) or `/App/QueryOnline` Gateway.
   */
  async fetchRemoteDeviceStatus(device: GreeDeviceModel): Promise<GreeCloudControlResult> {
    const normalizedMac: string = GreeMqttTlsClient.normalizeMac(device.mac);
    const statusReq: GreeStatusReqPack = {
      cols: GREE_STATUS_COLS,
      mac: normalizedMac,
      t: 'status'
    };
    return await this.dispatchCloudRequest(device, JSON.stringify(statusReq), true);
  }

  /**
   * Per `greeclimate_davo22/cloud_gateway.py`: modules with firmware version `< 3.2`
   * use the per-device TLS Gateway resolved via `/App/QueryOnline`, while `>= 3.2`
   * modules use the regional MQTT broker (`:1984`).
   */
  private usesMqttTransport(ver: string): boolean {
    const cleaned: string = ver.trim().replace(/^[vV]+/, '');
    if (cleaned.length === 0) {
      return true;
    }
    const chunks: string[] = cleaned.split('.');
    const nums: number[] = [];
    for (let i: number = 0; i < chunks.length; i++) {
      let digits: string = '';
      for (let j: number = 0; j < chunks[i].length; j++) {
        const ch: string = chunks[i].charAt(j);
        if (ch >= '0' && ch <= '9') {
          digits += ch;
        } else {
          break;
        }
      }
      if (digits.length === 0) {
        break;
      }
      nums.push(Number(digits));
    }
    if (nums.length === 0) {
      return true;
    }
    const major: number = nums[0];
    const minor: number = nums.length > 1 ? nums[1] : 0;
    return major > 3 || (major === 3 && minor >= 2);
  }

  private async dispatchCloudRequest(
    device: GreeDeviceModel,
    innerPlainJson: string,
    isStatusQuery: boolean
  ): Promise<GreeCloudControlResult> {
    const session: GreeCloudSessionInfo | null = await StorageUtil.getInstance().loadCloudSession();
    if (session === null || session.token.length === 0 || session.uid.length === 0) {
      return {
        success: false,
        tokenExpired: true,
        message: '尚未登录 Gree+ 云端账号，无法执行远程控制'
      };
    }

    const childMac: string = GreeMqttTlsClient.normalizeMac(device.mac);
    const learned: CloudTransportKind | undefined = this.learnedTransportByMac.get(childMac);
    const preferMqtt: boolean = learned !== undefined ? learned === 'mqtt' : this.usesMqttTransport(device.ver);

    hilog.info(DOMAIN, TAG,
      'Cloud dispatch mac=%{public}s pmac=%{public}s ver=%{public}s primary=%{public}s',
      childMac, device.parentMac, device.ver, preferMqtt ? 'MQTT' : 'QueryOnlineGateway');

    const primaryRes: GreeCloudControlResult = preferMqtt
      ? await this.sendEncryptedMqttRequest(device, session, innerPlainJson, isStatusQuery)
      : await this.sendViaCloudGateway(device, session, innerPlainJson);

    if (primaryRes.success) {
      this.learnedTransportByMac.set(childMac, preferMqtt ? 'mqtt' : 'gateway');
      return primaryRes;
    }
    if (primaryRes.tokenExpired) {
      return primaryRes;
    }

    hilog.warn(DOMAIN, TAG, 'Primary cloud transport (%{public}s) failed for %{public}s: %{public}s; trying fallback',
      preferMqtt ? 'MQTT' : 'Gateway', childMac, primaryRes.message);

    const secondaryRes: GreeCloudControlResult = preferMqtt
      ? await this.sendViaCloudGateway(device, session, innerPlainJson)
      : await this.sendEncryptedMqttRequest(device, session, innerPlainJson, isStatusQuery);

    if (secondaryRes.success) {
      this.learnedTransportByMac.set(childMac, preferMqtt ? 'gateway' : 'mqtt');
      return secondaryRes;
    }
    if (secondaryRes.tokenExpired) {
      return secondaryRes;
    }

    return {
      success: false,
      tokenExpired: false,
      message: `${preferMqtt ? 'MQTT' : '网关'}: ${primaryRes.message} | ${preferMqtt ? '网关' : 'MQTT'}: ${secondaryRes.message}`
    };
  }

  private async sendEncryptedMqttRequest(
    device: GreeDeviceModel,
    session: GreeCloudSessionInfo,
    innerPlainJson: string,
    isStatusQuery: boolean
  ): Promise<GreeCloudControlResult> {
    const deviceKey: string = device.key.length > 0 ? device.key : GREE_GENERIC_KEY;
    const customOverride: GreeCustomServerOverride | null = await StorageUtil.getInstance().loadCustomServerOverride();
    const candidates: MqttCandidateEndpoint[] = this.buildMqttCandidates(device, session, customOverride);
    const connRes: MqttRequestResult = await this.mqttClient.ensureConnectedWithCandidates(
      candidates,
      session.uid,
      session.token
    );
    if (!connRes.success) {
      return {
        success: false,
        tokenExpired: connRes.authFailed,
        message: connRes.errorMessage
      };
    }

    const reqRes: MqttRequestResult = await this.mqttClient.publishEncryptedRequest(
      device.mac,
      device.parentMac,
      deviceKey,
      session.uid,
      innerPlainJson,
      isStatusQuery
    );
    if (!reqRes.success) {
      return {
        success: false,
        tokenExpired: reqRes.authFailed,
        message: reqRes.errorMessage
      };
    }

    await this.applyDecryptedCloudPayload(device, reqRes.payloadJson);
    device.lastSeenMs = Date.now();
    device.onlineChannel = GreeOnlineChannel.CLOUD;
    await StorageUtil.getInstance().upsertDevice(device.toPersistedInfo());

    if (connRes.newlyConnected && !isStatusQuery) {
      this.fetchRemoteDeviceStatus(device).catch(() => {});
    }

    return {
      success: true,
      tokenExpired: false,
      message: '云端 MQTT 指令执行成功'
    };
  }

  private async queryDeviceOnlineGateway(
    session: GreeCloudSessionInfo,
    targetMac: string,
    forceRefresh: boolean = false
  ): Promise<GreeCloudGatewayServer | null> {
    const cleanMac: string = GreeMqttTlsClient.normalizeMac(targetMac);
    if (cleanMac.length === 0) {
      return null;
    }

    const nowMs: number = Date.now();
    if (!forceRefresh) {
      const cached: CachedGatewayEntry | undefined = this.gatewayCache.get(cleanMac);
      if (cached !== undefined && cached.expiresAtMs > nowMs) {
        return cached.server;
      }
    }

    const now: Date = new Date();
    const apiHeader: GreeCloudApiHeaderDto = await this.buildApiHeader(now);
    const auth: EffectiveAuthConfig = await this.getEffectiveAuthConfig();
    const numericUid: number = Number(session.uid.trim());
    const uidNum: number = Number.isNaN(numericUid) ? 0 : Math.floor(numericUid);
    const datVc: string = await GreeCryptoUtil.computeDatVc(auth.appHash, [
      session.token,
      String(uidNum),
      cleanMac
    ]);
    const body: GreeQueryOnlineBodyDto = {
      api: apiHeader,
      datVc: datVc,
      macs: [cleanMac],
      token: session.token,
      uid: uidNum
    };

    const raw: HttpRawResponse = await this.postEncryptedCloudApi(
      session.apiBaseUrl,
      '/App/QueryOnline',
      JSON.stringify(body)
    );
    if (raw.statusCode < 200 || raw.statusCode >= 300 || raw.body.length === 0) {
      return null;
    }

    try {
      const resp: GreeDecryptedQueryOnlineRespDto = JSON.parse(raw.body) as GreeDecryptedQueryOnlineRespDto;
      if (resp === null || resp.r !== 200 || !Array.isArray(resp.online)) {
        return null;
      }
      for (let i: number = 0; i < resp.online.length; i++) {
        const entry: GreeQueryOnlineItemDto = resp.online[i];
        const entryMac: string = entry.mac !== undefined ? GreeMqttTlsClient.normalizeMac(entry.mac) : '';
        if (entryMac.length > 0 && entryMac !== cleanMac) {
          continue;
        }
        const svr: string = entry.svr !== undefined ? entry.svr.trim() : '';
        const colonIdx: number = svr.lastIndexOf(':');
        if (colonIdx <= 0 || colonIdx >= svr.length - 1) {
          continue;
        }
        const host: string = svr.slice(0, colonIdx).trim();
        const port: number = Number(svr.slice(colonIdx + 1).trim());
        if (host.length === 0 || Number.isNaN(port) || port <= 0) {
          continue;
        }
        const isSsl: boolean = entry.isSSL === true || entry.isSSL === 1;
        const resolvedServer: GreeCloudGatewayServer = {
          host: host,
          port: Math.floor(port),
          isSsl: isSsl
        };
        this.gatewayCache.set(cleanMac, {
          server: resolvedServer,
          expiresAtMs: nowMs + GATEWAY_CACHE_TTL_MS
        });
        hilog.info(DOMAIN, TAG, 'QueryOnline resolved gateway for %{public}s: %{public}s:%{public}d ssl=%{public}s',
          cleanMac, host, resolvedServer.port, String(isSsl));
        return resolvedServer;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'QueryOnline parse warning: %{public}s', String(err));
    }
    return null;
  }

  private async sendViaCloudGateway(
    device: GreeDeviceModel,
    session: GreeCloudSessionInfo,
    innerPlainJson: string
  ): Promise<GreeCloudControlResult> {
    const childMac: string = GreeMqttTlsClient.normalizeMac(device.mac);
    const parentMac: string = device.parentMac.trim().length > 0
      ? GreeMqttTlsClient.normalizeMac(device.parentMac)
      : GreeMqttTlsClient.getParentMac(childMac);

    let gateway: GreeCloudGatewayServer | null = await this.queryDeviceOnlineGateway(session, childMac);
    let gatewayMac: string = childMac;
    if (gateway === null && parentMac !== childMac) {
      gateway = await this.queryDeviceOnlineGateway(session, parentMac);
      gatewayMac = parentMac;
    }
    if (gateway === null) {
      return {
        success: false,
        tokenExpired: false,
        message: `云端网关离线 (QueryOnline 未返回 ${childMac} 在线节点)`
      };
    }

    const deviceKey: string = device.key.length > 0 ? device.key : GREE_GENERIC_KEY;
    const encryptedPack: string = await GreeCryptoUtil.encryptPack(innerPlainJson, deviceKey);
    if (encryptedPack.length === 0) {
      return {
        success: false,
        tokenExpired: false,
        message: '云端网关指令 AES-128-ECB 加密失败'
      };
    }

    const numericUid: number = Number(session.uid.trim());
    const uidNum: number = Number.isNaN(numericUid) ? 0 : Math.floor(numericUid);
    const wireEnvelope: GreeMqttPackEnvelope = {
      cid: 'app',
      i: 0,
      pack: encryptedPack,
      t: 'pack',
      tcid: childMac,
      uid: uidNum
    };
    const wireLine: string = `${JSON.stringify(wireEnvelope)}\n`;

    let resolvedIp: string = gateway.host;
    try {
      const addrs: connection.NetAddress[] = await connection.getAddressesByName(gateway.host);
      for (let i: number = 0; i < addrs.length; i++) {
        if (addrs[i].address !== undefined && addrs[i].address.indexOf(':') < 0 && addrs[i].address.length > 0) {
          resolvedIp = addrs[i].address;
          break;
        }
      }
    } catch (dnsErr) {
      this.gatewayCache.delete(gatewayMac);
      return {
        success: false,
        tokenExpired: false,
        message: `网关 DNS 解析失败 (${gateway.host}): ${String(dnsErr)}`
      };
    }

    const replyLine: string = await this.exchangeGatewayLine(gateway, resolvedIp, wireLine);
    if (replyLine.length === 0) {
      this.gatewayCache.delete(gatewayMac);
      return {
        success: false,
        tokenExpired: false,
        message: `云端网关 ${gateway.host}:${gateway.port} 无响应或超时`
      };
    }

    try {
      const replyOuter: GreeMqttPackEnvelope = JSON.parse(replyLine) as GreeMqttPackEnvelope;
      if (replyOuter === null || typeof replyOuter.pack !== 'string' || replyOuter.pack.length === 0) {
        return {
          success: false,
          tokenExpired: false,
          message: '云端控制响应异常，请稍后重试'
        };
      }
      const decryptedReply: string = await GreeCryptoUtil.decryptPack(replyOuter.pack, deviceKey);
      if (decryptedReply.length === 0) {
        return {
          success: false,
          tokenExpired: false,
          message: '云端控制响应异常，请稍后重试'
        };
      }
      hilog.info(DOMAIN, TAG, 'Decrypted CloudGateway reply (%{public}s): %{public}s',
        childMac, decryptedReply.slice(0, 600));
      await this.applyDecryptedCloudPayload(device, decryptedReply);
      device.lastSeenMs = Date.now();
      device.onlineChannel = GreeOnlineChannel.CLOUD;
      await StorageUtil.getInstance().upsertDevice(device.toPersistedInfo());
      return {
        success: true,
        tokenExpired: false,
        message: '云端网关指令执行成功'
      };
    } catch (parseErr) {
      return {
        success: false,
        tokenExpired: false,
        message: `云端网关回包解析失败: ${String(parseErr)}`
      };
    }
  }

  private toExactArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    const buf: ArrayBuffer = new ArrayBuffer(bytes.byteLength);
    const view: Uint8Array = new Uint8Array(buf);
    view.set(bytes);
    return buf;
  }

  private async exchangeGatewayLine(
    gateway: GreeCloudGatewayServer,
    resolvedIp: string,
    wireLine: string
  ): Promise<string> {
    const wireBuffer: ArrayBuffer = this.toExactArrayBuffer(GreeCryptoUtil.utf8ToBytes(wireLine));
    if (gateway.isSsl) {
      const tlsSock: socket.TLSSocket = socket.constructTLSSocketInstance();
      return await new Promise<string>((resolve: (line: string) => void) => {
        let settled: boolean = false;
        let rxAcc: string = '';

        const finish = (result: string): void => {
          if (settled) {
            return;
          }
          settled = true;
          clearTimeout(timerId);
          try {
            tlsSock.off('message');
            tlsSock.off('error');
            tlsSock.off('close');
            tlsSock.close().catch(() => {});
          } catch {
          }
          resolve(result);
        };

        const timerId: number = setTimeout(() => {
          finish(rxAcc.trim());
        }, GATEWAY_IO_TIMEOUT_MS);

        const runTlsExchange = async (): Promise<void> => {
          await tlsSock.bind({ address: '0.0.0.0', port: 0, family: 1 });
          tlsSock.on('message', (info: socket.SocketMessageInfo) => {
            rxAcc += GreeCryptoUtil.bytesToUtf8(new Uint8Array(info.message));
            const nlIdx: number = rxAcc.indexOf('\n');
            if (nlIdx >= 0) {
              finish(rxAcc.slice(0, nlIdx).trim());
            } else if (rxAcc.trim().startsWith('{') && rxAcc.trim().endsWith('}')) {
              finish(rxAcc.trim());
            }
          });
          tlsSock.on('error', (err: Object) => {
            hilog.warn(DOMAIN, TAG, 'CloudGateway TLSSocket error: %{public}s', String(err));
            finish(rxAcc.trim());
          });
          tlsSock.on('close', () => {
            finish(rxAcc.trim());
          });

          const tlsOpts: socket.TLSConnectOptions = {
            address: { address: resolvedIp, port: gateway.port, family: 1 },
            secureOptions: {
              useRemoteCipherPrefer: true,
              protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13]
            },
            skipRemoteValidation: true,
            timeout: 4500
          };
          await tlsSock.connect(tlsOpts);
          await tlsSock.send(wireBuffer);
        };

        runTlsExchange().catch((err: Object) => {
          hilog.warn(DOMAIN, TAG, 'CloudGateway TLS exchange failed (%{public}s:%{public}d): %{public}s',
            gateway.host, gateway.port, String(err));
          finish('');
        });
      });
    }

    const tcpSock: socket.TCPSocket = socket.constructTCPSocketInstance();
    return await new Promise<string>((resolve: (line: string) => void) => {
      let settled: boolean = false;
      let rxAcc: string = '';

      const finish = (result: string): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timerId);
        try {
          tcpSock.off('message');
          tcpSock.off('error');
          tcpSock.off('close');
          tcpSock.close().catch(() => {});
        } catch {
        }
        resolve(result);
      };

      const timerId: number = setTimeout(() => {
        finish(rxAcc.trim());
      }, GATEWAY_IO_TIMEOUT_MS);

      tcpSock.on('message', (info: socket.SocketMessageInfo) => {
        rxAcc += GreeCryptoUtil.bytesToUtf8(new Uint8Array(info.message));
        const nlIdx: number = rxAcc.indexOf('\n');
        if (nlIdx >= 0) {
          finish(rxAcc.slice(0, nlIdx).trim());
        } else if (rxAcc.trim().startsWith('{') && rxAcc.trim().endsWith('}')) {
          finish(rxAcc.trim());
        }
      });
      tcpSock.on('error', (err: Object) => {
        hilog.warn(DOMAIN, TAG, 'CloudGateway TCPSocket error: %{public}s', String(err));
        finish(rxAcc.trim());
      });
      tcpSock.on('close', () => {
        finish(rxAcc.trim());
      });

      const tcpOpts: socket.TCPConnectOptions = {
        address: { address: resolvedIp, port: gateway.port, family: 1 },
        timeout: 4500
      };
      tcpSock.connect(tcpOpts).then(async () => {
        const sendOpts: socket.TCPSendOptions = { data: wireBuffer };
        await tcpSock.send(sendOpts);
      }).catch((err: Object) => {
        hilog.warn(DOMAIN, TAG, 'CloudGateway TCP exchange failed (%{public}s:%{public}d): %{public}s',
          gateway.host, gateway.port, String(err));
        finish('');
      });
    });
  }

  private async handleMqttPush(kind: string, topicMac: string, plainJson: string): Promise<void> {
    if (kind !== 'status' && kind !== 'response') {
      return;
    }
    const dev: GreeDeviceModel | null = GreeLocalService.getInstance().getDeviceByMac(topicMac);
    if (dev === null) {
      return;
    }
    await this.applyDecryptedCloudPayload(dev, plainJson);
    dev.lastSeenMs = Date.now();
    if (dev.onlineChannel !== GreeOnlineChannel.LAN) {
      dev.onlineChannel = GreeOnlineChannel.CLOUD;
    }
    await StorageUtil.getInstance().upsertDevice(dev.toPersistedInfo());
  }

  private async applyDecryptedCloudPayload(device: GreeDeviceModel, plainJson: string): Promise<void> {
    if (plainJson.length === 0) {
      return;
    }
    try {
      const probe: GreeInnerTypeProbe = JSON.parse(plainJson) as GreeInnerTypeProbe;
      if (probe === null || typeof probe.t !== 'string') {
        return;
      }
      if (probe.t === 'res') {
        const resPack: GreeResPack = JSON.parse(plainJson) as GreeResPack;
        const values: number[] = resPack.val !== undefined
          ? resPack.val
          : (resPack.p !== undefined ? resPack.p : []);
        if (Array.isArray(resPack.opt) && values.length > 0) {
          device.applyStatusArrays(resPack.opt, values);
        }
      } else if (probe.t === 'dat') {
        const datPack: GreeDatPack = JSON.parse(plainJson) as GreeDatPack;
        if (Array.isArray(datPack.cols) && Array.isArray(datPack.dat)) {
          device.applyStatusArrays(datPack.cols, datPack.dat);
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'applyDecryptedCloudPayload parse warning: %{public}s', String(err));
    }
  }

  async disconnectMqtt(): Promise<void> {
    await this.mqttClient.disconnect();
  }

  async logout(): Promise<void> {
    this.gatewayCache.clear();
    this.learnedTransportByMac.clear();
    await this.mqttClient.disconnect();
    await StorageUtil.getInstance().saveCloudSession(null);
  }
}
