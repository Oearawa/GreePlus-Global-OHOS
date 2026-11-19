import {
  MQTT_SSL_VERSION,
  MqttAsync,
  MqttClient,
  MqttClientOptions,
  MqttConnectOptions,
  MqttMessage,
  MqttPublishOptions,
  MqttResponse,
  MqttSubscribeOptions
} from '@ohos/mqtt';
import { connection, socket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  GREE_GENERIC_KEY,
  GREE_MQTT_ALT_TCP_PORT,
  GREE_MQTT_TCP_PORT,
  GREE_MQTT_TLS_PORT
} from '../common/constants/GreeConstants';
import { GreeCryptoUtil } from '../common/utils/GreeCryptoUtil';
import { GreeInnerTypeProbe, GreeMqttPackEnvelope } from '../model/GreeProtocolTypes';

const DOMAIN: number = 0x4752;
const TAG: string = 'GreeMqttTlsClient';
const MQTT_KEEPALIVE_SEC: number = 60;
const MQTT_PING_INTERVAL_MS: number = 30000;
const DNS_TIMEOUT_MS: number = 2500;
const TLS_HANDSHAKE_TIMEOUT_MS: number = 4000;
const TCP_CONNECT_TIMEOUT_MS: number = 3500;
const MQTT_CONNACK_TIMEOUT_MS: number = 3500;
const PAHO_CONNECT_TIMEOUT_MS: number = 8500;
const SUBACK_TIMEOUT_MS: number = 2500;
const REQUEST_TIMEOUT_MS: number = 6000;
const POST_TLS_HANDSHAKE_DELAY_MS: number = 50;

export interface MqttCandidateEndpoint {
  host: string;
  port: number;
  useTls: boolean;
  label?: string;
}

export interface MqttRequestResult {
  success: boolean;
  authFailed: boolean;
  newlyConnected: boolean;
  payloadJson: string;
  errorMessage: string;
}

export type MqttPushHandler = (kind: string, mac: string, plainJson: string) => void;

interface PendingMqttRequest {
  cid: string;
  childMac: string;
  parentMac: string;
  isStatusQuery: boolean;
  resolve: (res: MqttRequestResult) => void;
  timerId: number;
}

interface PendingSubAck {
  packetId: number;
  resolve: (ok: boolean) => void;
  timerId: number;
}

interface GenericErrorShape {
  code?: number;
  errorCode?: number;
  reasonCode?: number;
  message?: string;
}

type ActiveBackend = 'none' | 'paho' | 'tls' | 'tcp';

/**
 * Overseas Gree+ MQTT 3.1.1 client supporting `@ohos/mqtt` (Eclipse Paho C + OpenSSL)
 * as the primary engine, with a lifecycle-corrected HarmonyOS `TLSSocket` / `TCPSocket`
 * fallback (`bind` -> attach listeners -> `connect` -> 50ms -> `CONNECT`).
 */
export class GreeMqttTlsClient {
  private pahoClient: MqttClient | null = null;
  private tlsSocket: socket.TLSSocket | null = null;
  private tcpSocket: socket.TCPSocket | null = null;
  private activeBackend: ActiveBackend = 'none';
  private isConnected: boolean = false;
  private connectPromise: Promise<MqttRequestResult> | null = null;
  private connectSignature: string = '';

  private currentHost: string = '';
  private currentPort: number = GREE_MQTT_TLS_PORT;
  private currentUseTls: boolean = true;
  private currentUid: string = '';
  private currentToken: string = '';
  private nextPacketId: number = 1;
  private pingTimerId: number = -1;

  private rxBuffer: Uint8Array = new Uint8Array(0);
  private subscribedParentMacs: Set<string> = new Set<string>();
  private deviceKeysByMac: Map<string, string> = new Map<string, string>();
  private pendingRequests: Map<string, PendingMqttRequest> = new Map<string, PendingMqttRequest>();
  private pendingSubAcks: Map<number, PendingSubAck> = new Map<number, PendingSubAck>();
  private connAckWaiter: ((ok: boolean, authFailed: boolean, err: string) => void) | null = null;
  private pushHandler: MqttPushHandler | null = null;

  setPushHandler(handler: MqttPushHandler | null): void {
    this.pushHandler = handler;
  }

  getActiveEndpointSummary(): string {
    if (!this.isConnected || this.currentHost.length === 0) {
      return '';
    }
    const scheme: string = this.currentUseTls ? 'TLS' : 'TCP';
    const engine: string = this.activeBackend === 'paho' ? 'ohos/mqtt' : 'socket';
    return `${scheme}://${this.currentHost}:${this.currentPort} (${engine})`;
  }

  static normalizeMac(mac: string): string {
    const lower: string = mac.trim().toLowerCase();
    let hex: string = '';
    for (let i: number = 0; i < lower.length; i++) {
      const ch: string = lower.charAt(i);
      if ((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) {
        hex += ch;
      }
    }
    return hex.length > 0 ? hex : lower;
  }

  static getParentMac(mac: string): string {
    const clean: string = GreeMqttTlsClient.normalizeMac(mac);
    if (clean.length > 12 && clean.endsWith('00')) {
      return clean.slice(0, clean.length - 2);
    }
    return clean;
  }

  registerDeviceKey(mac: string, key: string): void {
    const cleanMac: string = GreeMqttTlsClient.normalizeMac(mac);
    if (cleanMac.length > 0 && key.length > 0) {
      this.deviceKeysByMac.set(cleanMac, key);
    }
  }

  async ensureConnected(host: string, port: number, uid: string, token: string): Promise<MqttRequestResult> {
    const targetPort: number = port > 0 ? port : GREE_MQTT_TLS_PORT;
    const useTls: boolean = targetPort !== GREE_MQTT_TCP_PORT && targetPort !== GREE_MQTT_ALT_TCP_PORT;
    const candidates: MqttCandidateEndpoint[] = [
      {
        host: host,
        port: targetPort,
        useTls: useTls
      }
    ];
    return await this.ensureConnectedWithCandidates(candidates, uid, token);
  }

  async ensureConnectedWithCandidates(
    candidates: MqttCandidateEndpoint[],
    uid: string,
    token: string
  ): Promise<MqttRequestResult> {
    if (candidates.length === 0) {
      return {
        success: false,
        authFailed: false,
        newlyConnected: false,
        payloadJson: '',
        errorMessage: '未配置任何有效的云端 MQTT 服务器地址'
      };
    }

    const cleanUid: string = String(uid).trim();
    const cleanToken: string = token.trim();

    if (await this.isAlreadyConnectedToAny(candidates, cleanUid, cleanToken)) {
      return {
        success: true,
        authFailed: false,
        newlyConnected: false,
        payloadJson: '',
        errorMessage: ''
      };
    }

    const signature: string = this.buildCandidateSignature(candidates, cleanUid, cleanToken);
    if (this.connectPromise !== null && this.connectSignature === signature) {
      return await this.connectPromise;
    }

    await this.disconnect();
    this.connectSignature = signature;

    const task: Promise<MqttRequestResult> = this.connectCandidatesSequential(candidates, cleanUid, cleanToken);
    this.connectPromise = task;
    try {
      return await task;
    } finally {
      if (this.connectPromise === task) {
        this.connectPromise = null;
        this.connectSignature = '';
      }
    }
  }

  private async isAlreadyConnectedToAny(
    candidates: MqttCandidateEndpoint[],
    uid: string,
    token: string
  ): Promise<boolean> {
    if (!this.isConnected || this.currentUid !== uid || this.currentToken !== token) {
      return false;
    }
    if (this.activeBackend === 'paho') {
      if (this.pahoClient === null) {
        return false;
      }
      try {
        const alive: boolean = await this.pahoClient.isConnected();
        if (!alive) {
          return false;
        }
      } catch {
        return false;
      }
    } else if (this.activeBackend === 'tls') {
      if (this.tlsSocket === null) {
        return false;
      }
    } else if (this.activeBackend === 'tcp') {
      if (this.tcpSocket === null) {
        return false;
      }
    } else {
      return false;
    }

    for (let i: number = 0; i < candidates.length; i++) {
      const c: MqttCandidateEndpoint = candidates[i];
      if (
        c.host.trim().toLowerCase() === this.currentHost.trim().toLowerCase() &&
        c.port === this.currentPort &&
        c.useTls === this.currentUseTls
      ) {
        return true;
      }
    }
    return false;
  }

  private buildCandidateSignature(candidates: MqttCandidateEndpoint[], uid: string, token: string): string {
    const parts: string[] = [uid, token];
    for (let i: number = 0; i < candidates.length; i++) {
      const c: MqttCandidateEndpoint = candidates[i];
      parts.push(`${c.useTls ? 'tls' : 'tcp'}://${c.host}:${c.port}`);
    }
    return parts.join('|');
  }

  private async connectCandidatesSequential(
    candidates: MqttCandidateEndpoint[],
    uid: string,
    token: string
  ): Promise<MqttRequestResult> {
    const failureReasons: string[] = [];

    for (let i: number = 0; i < candidates.length; i++) {
      const candidate: MqttCandidateEndpoint = candidates[i];
      const tagLabel: string = candidate.useTls ? 'TLS' : 'TCP';
      hilog.info(DOMAIN, TAG, 'Attempting MQTT candidate [%{public}d/%{public}d]: %{public}s:%{public}d (%{public}s)',
        i + 1, candidates.length, candidate.host, candidate.port, tagLabel);

      // 1. Primary path: @ohos/mqtt (Paho C + OpenSSL)
      const pahoRes: MqttRequestResult = await this.connectViaOhosMqtt(candidate, uid, token);
      if (pahoRes.success) {
        return pahoRes;
      }
      if (pahoRes.authFailed) {
        return pahoRes;
      }
      hilog.warn(DOMAIN, TAG, '@ohos/mqtt failed for %{public}s:%{public}d: %{public}s; trying native Socket',
        candidate.host, candidate.port, pahoRes.errorMessage);

      // 2. Fallback path: lifecycle-fixed native TLSSocket / TCPSocket
      const nativeRes: MqttRequestResult = await this.attemptNativeSocketCandidate(candidate, uid, token);
      if (nativeRes.success) {
        return nativeRes;
      }
      if (nativeRes.authFailed) {
        return nativeRes;
      }

      failureReasons.push(
        `${candidate.host}:${candidate.port} (${tagLabel}) -> @ohos/mqtt: ${pahoRes.errorMessage}; native: ${nativeRes.errorMessage}`
      );
    }

    return {
      success: false,
      authFailed: false,
      newlyConnected: false,
      payloadJson: '',
      errorMessage: `云端 MQTT 连接失败: ${failureReasons.join(' | ')}`
    };
  }

  private async connectViaOhosMqtt(
    candidate: MqttCandidateEndpoint,
    uid: string,
    token: string
  ): Promise<MqttRequestResult> {
    const cleanHost: string = candidate.host.trim();
    const targetPort: number = candidate.port;
    const scheme: string = candidate.useTls ? 'ssl' : 'tcp';
    const url: string = `${scheme}://${cleanHost}:${targetPort}`;
    const clientId: string = `app_${this.randomHex(16)}`;

    let client: MqttClient | null = null;
    try {
      const clientOpts: MqttClientOptions = {
        url: url,
        clientId: clientId,
        persistenceType: 1,
        MQTTVersion: 4
      };
      client = await MqttAsync.createMqttAsync(clientOpts);
      this.pahoClient = client;
      this.activeBackend = 'paho';
      this.subscribedParentMacs.clear();

      // Register callbacks before connect() and subscribe()
      client.messageArrived((err: Error, msg: MqttMessage) => {
        if (this.pahoClient !== client || err !== null && err !== undefined) {
          return;
        }
        if (msg === null || msg === undefined || typeof msg.topic !== 'string') {
          return;
        }
        let payloadText: string = typeof msg.payload === 'string' ? msg.payload : '';
        if (payloadText.length === 0 && msg.payloadBinary !== undefined) {
          payloadText = GreeCryptoUtil.bytesToUtf8(new Uint8Array(msg.payloadBinary));
        }
        if (payloadText.length > 0) {
          const isRetained: boolean = msg.retained !== undefined && msg.retained !== 0;
          this.handleIncomingPublish(msg.topic, payloadText, isRetained).catch((pushErr: Object) => {
            hilog.warn(DOMAIN, TAG, 'paho handleIncomingPublish error: %{public}s', this.formatSocketError(pushErr));
          });
        }
      });

      client.connectLost((err: Error, res: MqttResponse) => {
        if (this.pahoClient !== client) {
          return;
        }
        const reason: string = res !== null && res !== undefined && typeof res.message === 'string'
          ? res.message
          : (err !== null && err !== undefined ? err.message : '连接中断');
        hilog.warn(DOMAIN, TAG, 'paho connectLost (%{public}s:%{public}d): %{public}s',
          cleanHost, targetPort, reason);
        this.handleTransportClosed(`MQTT 连接已断开 (${cleanHost}:${targetPort}): ${reason}`);
      });

      const connOpts: MqttConnectOptions = candidate.useTls
        ? {
            cleanSession: true,
            connectTimeout: 8,
            keepAliveInterval: MQTT_KEEPALIVE_SEC,
            MQTTVersion: 4,
            userName: uid,
            password: token,
            sslOptions: {
              enableServerCertAuth: false,
              verify: false,
              sslVersion: MQTT_SSL_VERSION.MQTT_SSL_VERSION_DEFAULT
            }
          }
        : {
            cleanSession: true,
            connectTimeout: 8,
            keepAliveInterval: MQTT_KEEPALIVE_SEC,
            MQTTVersion: 4,
            userName: uid,
            password: token
          };

      hilog.info(DOMAIN, TAG, 'Connecting via @ohos/mqtt: url=%{public}s clientId=%{public}s uid=%{public}s',
        url, clientId, uid);

      const resp: MqttResponse = await this.runWithTimeout(
        client.connect(connOpts),
        PAHO_CONNECT_TIMEOUT_MS,
        `@ohos/mqtt 连接超时 (${url})`
      );

      if (resp.code !== 0) {
        const authFailed: boolean = this.isPahoAuthError(resp);
        await this.disposePahoClient(client);
        return {
          success: false,
          authFailed: authFailed,
          newlyConnected: false,
          payloadJson: '',
          errorMessage: authFailed
            ? `MQTT 鉴权被拒绝 (code=${resp.code}, reason=${resp.reasonCode}): 请重新登录`
            : `MQTT 连接失败 (code=${resp.code}): ${resp.message}`
        };
      }

      this.currentHost = cleanHost;
      this.currentPort = targetPort;
      this.currentUseTls = candidate.useTls;
      this.currentUid = uid;
      this.currentToken = token;
      this.isConnected = true;

      hilog.info(DOMAIN, TAG, '@ohos/mqtt connected successfully to %{public}s', url);
      return {
        success: true,
        authFailed: false,
        newlyConnected: true,
        payloadJson: '',
        errorMessage: ''
      };
    } catch (err) {
      const authFailed: boolean = this.isPahoAuthObject(err);
      const formatted: string = this.formatSocketError(err);
      if (client !== null) {
        await this.disposePahoClient(client);
      }
      return {
        success: false,
        authFailed: authFailed,
        newlyConnected: false,
        payloadJson: '',
        errorMessage: authFailed
          ? `MQTT 鉴权被拒绝 (${formatted})，请重新登录`
          : formatted
      };
    }
  }

  private isPahoAuthError(resp: MqttResponse): boolean {
    if (resp.code === 4 || resp.code === 5 || resp.reasonCode === 4 || resp.reasonCode === 5) {
      return true;
    }
    const lower: string = (resp.message ?? '').toLowerCase();
    return lower.includes('user name') || lower.includes('not authorized') || lower.includes('connack rc 4') ||
      lower.includes('connack rc 5');
  }

  private isPahoAuthObject(err: Object): boolean {
    const shape: GenericErrorShape = err as GenericErrorShape;
    if (shape.code === 4 || shape.code === 5 || shape.reasonCode === 4 || shape.reasonCode === 5) {
      return true;
    }
    const lower: string = this.formatSocketError(err).toLowerCase();
    return lower.includes('user name') || lower.includes('not authorized') || lower.includes('return code 4') ||
      lower.includes('return code 5');
  }

  private async attemptNativeSocketCandidate(
    candidate: MqttCandidateEndpoint,
    uid: string,
    token: string
  ): Promise<MqttRequestResult> {
    const cleanHost: string = candidate.host.trim();
    const targetPort: number = candidate.port;

    this.rxBuffer = new Uint8Array(0);
    this.subscribedParentMacs.clear();
    this.connAckWaiter = null;

    let resolvedIps: string[] = [];
    if (this.isIpv4Literal(cleanHost)) {
      resolvedIps = [cleanHost];
    } else {
      try {
        resolvedIps = await this.resolveIpv4WithTimeout(cleanHost, DNS_TIMEOUT_MS);
      } catch (dnsErr) {
        return {
          success: false,
          authFailed: false,
          newlyConnected: false,
          payloadJson: '',
          errorMessage: `DNS 解析失败 (${cleanHost}): ${this.formatSocketError(dnsErr)}`
        };
      }
    }

    if (resolvedIps.length === 0) {
      return {
        success: false,
        authFailed: false,
        newlyConnected: false,
        payloadJson: '',
        errorMessage: `DNS 解析无可用 IP (${cleanHost})`
      };
    }

    const primaryIp: string = resolvedIps[0];
    let transportErr: string = '';

    if (candidate.useTls) {
      transportErr = await this.establishTlsTransport(cleanHost, primaryIp, targetPort);
      if (transportErr.length > 0 && resolvedIps.length > 1) {
        hilog.info(DOMAIN, TAG, 'Primary IP %{public}s failed, retrying secondary IP %{public}s',
          primaryIp, resolvedIps[1]);
        const secondaryErr: string = await this.establishTlsTransport(cleanHost, resolvedIps[1], targetPort);
        if (secondaryErr.length === 0) {
          transportErr = '';
        } else {
          transportErr = `${transportErr}; 备用IP ${resolvedIps[1]} -> ${secondaryErr}`;
        }
      }
    } else {
      transportErr = await this.establishTcpTransport(cleanHost, primaryIp, targetPort);
      if (transportErr.length > 0 && resolvedIps.length > 1) {
        const secondaryErr: string = await this.establishTcpTransport(cleanHost, resolvedIps[1], targetPort);
        if (secondaryErr.length === 0) {
          transportErr = '';
        } else {
          transportErr = `${transportErr}; 备用IP ${resolvedIps[1]} -> ${secondaryErr}`;
        }
      }
    }

    if (transportErr.length > 0) {
      await this.closeActiveSocketsQuietly();
      return {
        success: false,
        authFailed: false,
        newlyConnected: false,
        payloadJson: '',
        errorMessage: transportErr
      };
    }

    this.activeBackend = candidate.useTls ? 'tls' : 'tcp';
    this.currentHost = cleanHost;
    this.currentPort = targetPort;
    this.currentUseTls = candidate.useTls;
    this.currentUid = uid;
    this.currentToken = token;

    // Give HarmonyOS TLS/TCP session 50ms after connect() resolves before writing CONNECT frame
    await this.delayMs(POST_TLS_HANDSHAKE_DELAY_MS);

    const ackResult: MqttRequestResult = await this.performNativeMqttConnectHandshake(cleanHost, targetPort, uid, token);
    if (!ackResult.success) {
      await this.closeActiveSocketsQuietly();
      return ackResult;
    }

    this.isConnected = true;
    this.startPingTimer();
    hilog.info(DOMAIN, TAG, 'Native MQTT connected via %{public}s://%{public}s:%{public}d (IP %{public}s)',
      candidate.useTls ? 'TLS' : 'TCP', cleanHost, targetPort, primaryIp);
    return ackResult;
  }

  /**
   * Establishes a native TLSSocket connection.
   * Note: `bind()` completes BEFORE `on('message'/'error'/'close')` registration and BEFORE `connect()`,
   * complying with HarmonyOS NetStack's TLSSocket event subscription requirement.
   */
  private async establishTlsTransport(host: string, resolvedIp: string, port: number): Promise<string> {
    const directErr: string = await this.connectFreshTlsDirect(resolvedIp, port);
    if (directErr.length === 0) {
      return '';
    }
    hilog.warn(DOMAIN, TAG, 'Direct TLSSocket failed (%{public}s:%{public}d [%{public}s]): %{public}s',
      host, port, resolvedIp, directErr);

    const upgradeErr: string = await this.connectTcpAndUpgradeTls(host, resolvedIp, port);
    if (upgradeErr.length === 0) {
      return '';
    }
    return `TLS 直连(${resolvedIp}:${port})=${directErr}; TCP升级TLS=${upgradeErr}`;
  }

  private async connectFreshTlsDirect(resolvedIp: string, port: number): Promise<string> {
    const sock: socket.TLSSocket = socket.constructTLSSocketInstance();
    this.tlsSocket = sock;

    try {
      await this.runWithTimeout(sock.bind({ address: '0.0.0.0', port: 0, family: 1 }), 1500, 'Bind 本地端口超时');
      // Register listeners strictly after bind() and before connect()
      this.attachTlsListeners(sock);

      const connectOpts: socket.TLSConnectOptions = {
        address: { address: resolvedIp, port: port, family: 1 },
        secureOptions: {
          useRemoteCipherPrefer: true,
          protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13]
        },
        skipRemoteValidation: true,
        timeout: TLS_HANDSHAKE_TIMEOUT_MS
      };
      await this.runWithTimeout(
        sock.connect(connectOpts),
        TLS_HANDSHAKE_TIMEOUT_MS + 300,
        `TLS 握手超时 (${TLS_HANDSHAKE_TIMEOUT_MS / 1000}s)`
      );
      return '';
    } catch (err) {
      if (this.tlsSocket === sock) {
        this.tlsSocket = null;
      }
      await this.disposeTlsSocket(sock);
      return this.formatSocketError(err);
    }
  }

  private async connectTcpAndUpgradeTls(host: string, resolvedIp: string, port: number): Promise<string> {
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    let tls: socket.TLSSocket | null = null;
    try {
      const tcpOpts: socket.TCPConnectOptions = {
        address: { address: resolvedIp, port: port, family: 1 },
        timeout: TCP_CONNECT_TIMEOUT_MS
      };
      await this.runWithTimeout(
        tcp.connect(tcpOpts),
        TCP_CONNECT_TIMEOUT_MS + 300,
        `TCP 建连超时 (${resolvedIp}:${port})`
      );

      tls = socket.constructTLSSocketInstance(tcp);
      this.tlsSocket = tls;
      this.attachTlsListeners(tls);

      const tlsOpts: socket.TLSConnectOptions = {
        address: { address: host, port: port, family: 1 },
        secureOptions: {
          useRemoteCipherPrefer: true,
          protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13]
        },
        skipRemoteValidation: true,
        timeout: TLS_HANDSHAKE_TIMEOUT_MS
      };
      await this.runWithTimeout(
        tls.connect(tlsOpts),
        TLS_HANDSHAKE_TIMEOUT_MS + 300,
        `TLS 握手超时 (${TLS_HANDSHAKE_TIMEOUT_MS / 1000}s)`
      );
      return '';
    } catch (err) {
      if (tls !== null) {
        if (this.tlsSocket === tls) {
          this.tlsSocket = null;
        }
        await this.disposeTlsSocket(tls);
      } else {
        await this.disposeTcpSocket(tcp);
      }
      return this.formatSocketError(err);
    }
  }

  private async establishTcpTransport(host: string, resolvedIp: string, port: number): Promise<string> {
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    this.tcpSocket = tcp;
    this.attachTcpListeners(tcp);

    try {
      const tcpOpts: socket.TCPConnectOptions = {
        address: { address: resolvedIp, port: port, family: 1 },
        timeout: TCP_CONNECT_TIMEOUT_MS
      };
      await this.runWithTimeout(
        tcp.connect(tcpOpts),
        TCP_CONNECT_TIMEOUT_MS + 300,
        `TCP 明文连接超时 (${host}:${port} [${resolvedIp}])`
      );
      return '';
    } catch (err) {
      if (this.tcpSocket === tcp) {
        this.tcpSocket = null;
      }
      await this.disposeTcpSocket(tcp);
      return this.formatSocketError(err);
    }
  }

  private async performNativeMqttConnectHandshake(
    host: string,
    port: number,
    uid: string,
    token: string
  ): Promise<MqttRequestResult> {
    const clientId: string = `app_${this.randomHex(16)}`;
    const connectPacket: Uint8Array = this.buildConnectPacket(clientId, uid, token);
    const maskedHex: string = this.formatMaskedConnectHeaderHex(connectPacket, clientId, uid, 32);
    hilog.info(DOMAIN, TAG,
      'Sending native MQTT CONNECT (%{public}d bytes) to %{public}s:%{public}d header[0..32]=%{public}s',
      connectPacket.length, host, port, maskedHex);

    return await new Promise<MqttRequestResult>((resolve: (res: MqttRequestResult) => void) => {
      let done: boolean = false;
      const finishAck = (res: MqttRequestResult): void => {
        if (done) {
          return;
        }
        done = true;
        clearTimeout(ackTimer);
        if (this.connAckWaiter !== null) {
          this.connAckWaiter = null;
        }
        resolve(res);
      };

      const ackTimer: number = setTimeout(() => {
        finishAck({
          success: false,
          authFailed: false,
          newlyConnected: false,
          payloadJson: '',
          errorMessage: `等待 MQTT CONNACK 响应超时 (${host}:${port}, hdr=${maskedHex})`
        });
      }, MQTT_CONNACK_TIMEOUT_MS);

      this.connAckWaiter = (ok: boolean, authFailed: boolean, errMsg: string): void => {
        finishAck({
          success: ok,
          authFailed: authFailed,
          newlyConnected: ok,
          payloadJson: '',
          errorMessage: errMsg
        });
      };

      this.sendRawBytes(connectPacket).catch((err: Object) => {
        finishAck({
          success: false,
          authFailed: false,
          newlyConnected: false,
          payloadJson: '',
          errorMessage: `发送 MQTT CONNECT 失败 (${host}:${port}): ${this.formatSocketError(err)}`
        });
      });
    });
  }

  private formatMaskedConnectHeaderHex(
    packet: Uint8Array,
    clientId: string,
    uid: string,
    maxBytes: number
  ): string {
    const clientLen: number = GreeCryptoUtil.utf8ToBytes(clientId).length;
    const uidLen: number = GreeCryptoUtil.utf8ToBytes(uid).length;
    // Offset of password bytes: 1-byte type + 1-4 byte remLen + 10-byte varHeader + 2+clientLen + 2+uidLen + 2(passLen)
    let remLenBytes: number = 1;
    while (remLenBytes < 4 && remLenBytes < packet.length && (packet[remLenBytes] & 0x80) !== 0) {
      remLenBytes++;
    }
    const headerPlusPrefixLen: number = 10 + 2 + clientLen + 2 + uidLen;
    const tokenStartIdx: number = 1 + remLenBytes + headerPlusPrefixLen + 2;
    const limit: number = Math.min(maxBytes, packet.length);
    const hexChars: string = '0123456789abcdef';
    const parts: string[] = [];
    for (let i: number = 0; i < limit; i++) {
      if (i >= tokenStartIdx) {
        parts.push('**');
      } else {
        const b: number = packet[i] & 0xff;
        parts.push(hexChars.charAt((b >>> 4) & 0x0f) + hexChars.charAt(b & 0x0f));
      }
    }
    return parts.join(' ');
  }

  private attachTlsListeners(sock: socket.TLSSocket): void {
    sock.on('message', (info: socket.SocketMessageInfo) => {
      if (this.tlsSocket !== sock) {
        return;
      }
      const chunk: Uint8Array = new Uint8Array(info.message);
      this.appendAndParseIncoming(chunk);
    });
    sock.on('error', (err: Object) => {
      if (this.tlsSocket !== sock) {
        return;
      }
      const formatted: string = this.formatSocketError(err);
      hilog.warn(DOMAIN, TAG, 'TLSSocket error: %{public}s', formatted);
      this.handleTransportClosed(`MQTT TLS Socket 错误 (${this.currentHost}:${this.currentPort}): ${formatted}`);
    });
    sock.on('close', () => {
      if (this.tlsSocket !== sock) {
        return;
      }
      hilog.info(DOMAIN, TAG, 'TLSSocket closed');
      this.handleTransportClosed(`MQTT TLS 连接已关闭 (${this.currentHost}:${this.currentPort})`);
    });
  }

  private attachTcpListeners(sock: socket.TCPSocket): void {
    sock.on('message', (info: socket.SocketMessageInfo) => {
      if (this.tcpSocket !== sock) {
        return;
      }
      const chunk: Uint8Array = new Uint8Array(info.message);
      this.appendAndParseIncoming(chunk);
    });
    sock.on('error', (err: Object) => {
      if (this.tcpSocket !== sock) {
        return;
      }
      const formatted: string = this.formatSocketError(err);
      hilog.warn(DOMAIN, TAG, 'TCPSocket error: %{public}s', formatted);
      this.handleTransportClosed(`MQTT TCP Socket 错误 (${this.currentHost}:${this.currentPort}): ${formatted}`);
    });
    sock.on('close', () => {
      if (this.tcpSocket !== sock) {
        return;
      }
      hilog.info(DOMAIN, TAG, 'TCPSocket closed');
      this.handleTransportClosed(`MQTT TCP 连接已关闭 (${this.currentHost}:${this.currentPort})`);
    });
  }

  private toExactArrayBuffer(packet: Uint8Array): ArrayBuffer {
    const out: ArrayBuffer = new ArrayBuffer(packet.byteLength);
    const view: Uint8Array = new Uint8Array(out);
    view.set(packet);
    return out;
  }

  private async sendRawBytes(packet: Uint8Array): Promise<void> {
    const rawBuffer: ArrayBuffer = this.toExactArrayBuffer(packet);
    if (this.activeBackend === 'tls') {
      if (this.tlsSocket === null) {
        throw new Error('TLS Socket 未就绪');
      }
      await this.tlsSocket.send(rawBuffer);
      return;
    }
    if (this.tcpSocket === null) {
      throw new Error('TCP Socket 未就绪');
    }
    const sendOpts: socket.TCPSendOptions = {
      data: rawBuffer
    };
    await this.tcpSocket.send(sendOpts);
  }

  private hasOpenTransport(): boolean {
    if (!this.isConnected) {
      return false;
    }
    if (this.activeBackend === 'paho') {
      return this.pahoClient !== null;
    }
    if (this.activeBackend === 'tls') {
      return this.tlsSocket !== null;
    }
    if (this.activeBackend === 'tcp') {
      return this.tcpSocket !== null;
    }
    return false;
  }

  async subscribeDevice(parentMac: string, childMac?: string): Promise<boolean> {
    const cleanParent: string = GreeMqttTlsClient.normalizeMac(parentMac);
    const cleanChild: string = childMac !== undefined && childMac.trim().length > 0
      ? GreeMqttTlsClient.normalizeMac(childMac)
      : cleanParent;
    const subKey: string = `${cleanParent}|${cleanChild}`;
    if (!this.hasOpenTransport()) {
      return false;
    }
    if (this.subscribedParentMacs.has(subKey)) {
      return true;
    }

    const topics: string[] = [
      `response/${cleanParent}/#`,
      `status/${cleanParent}/#`,
      `connect/${cleanParent}`
    ];
    if (cleanChild !== cleanParent) {
      topics.push(`response/${cleanChild}/#`);
      topics.push(`status/${cleanChild}/#`);
      topics.push(`connect/${cleanChild}`);
    }

    hilog.info(DOMAIN, TAG, 'Subscribing MQTT topics: %{public}s', topics.join(', '));

    if (this.activeBackend === 'paho' && this.pahoClient !== null) {
      try {
        const subOpts: MqttSubscribeOptions[] = [];
        for (let i: number = 0; i < topics.length; i++) {
          subOpts.push({ topic: topics[i], qos: 1 });
        }
        const subRes: MqttResponse = await this.pahoClient.subscribeMany(subOpts);
        hilog.info(DOMAIN, TAG, 'paho subscribeMany code=%{public}d msg=%{public}s', subRes.code, subRes.message);
        if (subRes.code === 0) {
          this.subscribedParentMacs.add(subKey);
          return true;
        }
        return false;
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'paho subscribeMany error: %{public}s', this.formatSocketError(err));
        return false;
      }
    }

    const packetId: number = this.allocatePacketId();
    const subPacket: Uint8Array = this.buildSubscribePacket(packetId, topics);

    const subOk: boolean = await new Promise<boolean>((resolve: (ok: boolean) => void) => {
      const timerId: number = setTimeout(() => {
        this.pendingSubAcks.delete(packetId);
        resolve(false);
      }, SUBACK_TIMEOUT_MS);

      this.pendingSubAcks.set(packetId, {
        packetId: packetId,
        resolve: resolve,
        timerId: timerId
      });

      this.sendRawBytes(subPacket).catch((err: Object) => {
        const pending: PendingSubAck | undefined = this.pendingSubAcks.get(packetId);
        if (pending !== undefined) {
          clearTimeout(pending.timerId);
          this.pendingSubAcks.delete(packetId);
          hilog.warn(DOMAIN, TAG, 'subscribeDevice send error: %{public}s', this.formatSocketError(err));
          pending.resolve(false);
        }
      });
    });

    if (subOk) {
      this.subscribedParentMacs.add(subKey);
    }
    return subOk;
  }

  async publishEncryptedRequest(
    mac: string,
    parentMacInput: string,
    deviceKey: string,
    uid: string,
    innerCommandJson: string,
    isStatusQuery: boolean = false
  ): Promise<MqttRequestResult> {
    if (!this.hasOpenTransport()) {
      return {
        success: false,
        authFailed: false,
        newlyConnected: false,
        payloadJson: '',
        errorMessage: 'MQTT 尚未建立有效连接'
      };
    }

    const childMac: string = GreeMqttTlsClient.normalizeMac(mac);
    const parentMac: string = parentMacInput.trim().length > 0
      ? GreeMqttTlsClient.normalizeMac(parentMacInput)
      : GreeMqttTlsClient.getParentMac(childMac);
    this.registerDeviceKey(childMac, deviceKey);
    this.registerDeviceKey(parentMac, deviceKey);

    await this.subscribeDevice(parentMac, childMac);

    const encryptedPack: string = await GreeCryptoUtil.encryptPack(innerCommandJson, deviceKey);
    if (encryptedPack.length === 0) {
      return {
        success: false,
        authFailed: false,
        newlyConnected: false,
        payloadJson: '',
        errorMessage: 'MQTT 指令 AES-128-ECB 加密失败'
      };
    }

    const cid: string = this.generateCid();
    const numericUid: number = Number(uid.trim());
    const effectiveUid: number = Number.isNaN(numericUid) ? 0 : Math.floor(numericUid);
    const envelope: GreeMqttPackEnvelope = {
      cid: cid,
      i: 0,
      pack: encryptedPack,
      t: 'pack',
      tcid: childMac,
      uid: effectiveUid
    };
    const topic: string = `request/${parentMac}`;
    const envelopeJson: string = JSON.stringify(envelope);

    hilog.info(DOMAIN, TAG,
      'Publishing MQTT topic=%{public}s cid=%{public}s tcid=%{public}s uid=%{public}d inner=%{public}s',
      topic, cid, childMac, effectiveUid, innerCommandJson);

    if (this.activeBackend === 'paho' && this.pahoClient !== null) {
      return await new Promise<MqttRequestResult>((resolve: (res: MqttRequestResult) => void) => {
        const timerId: number = setTimeout(() => {
          this.pendingRequests.delete(cid);
          resolve({
            success: false,
            authFailed: false,
            newlyConnected: false,
            payloadJson: '',
            errorMessage: `云端 MQTT 响应超时 (${childMac} @ ${this.currentHost}:${this.currentPort})`
          });
        }, REQUEST_TIMEOUT_MS);

        this.pendingRequests.set(cid, {
          cid: cid,
          childMac: childMac,
          parentMac: parentMac,
          isStatusQuery: isStatusQuery,
          resolve: resolve,
          timerId: timerId
        });

        const pubOpts: MqttPublishOptions = {
          topic: topic,
          payload: envelopeJson,
          qos: 1,
          retained: false
        };
        this.pahoClient!.publish(pubOpts).catch((err: Object) => {
          const pending: PendingMqttRequest | undefined = this.pendingRequests.get(cid);
          if (pending !== undefined) {
            clearTimeout(pending.timerId);
            this.pendingRequests.delete(cid);
            pending.resolve({
              success: false,
              authFailed: false,
              newlyConnected: false,
              payloadJson: '',
              errorMessage: `发送 MQTT PUBLISH 失败: ${this.formatSocketError(err)}`
            });
          }
        });
      });
    }

    const payloadBytes: Uint8Array = GreeCryptoUtil.utf8ToBytes(envelopeJson);
    const packetId: number = this.allocatePacketId();
    const publishPacket: Uint8Array = this.buildPublishPacket(topic, payloadBytes, packetId);

    return await new Promise<MqttRequestResult>((resolve: (res: MqttRequestResult) => void) => {
      const timerId: number = setTimeout(() => {
        this.pendingRequests.delete(cid);
        resolve({
          success: false,
          authFailed: false,
          newlyConnected: false,
          payloadJson: '',
          errorMessage: `云端 MQTT 响应超时 (${childMac} @ ${this.currentHost}:${this.currentPort})`
        });
      }, REQUEST_TIMEOUT_MS);

      this.pendingRequests.set(cid, {
        cid: cid,
        childMac: childMac,
        parentMac: parentMac,
        isStatusQuery: isStatusQuery,
        resolve: resolve,
        timerId: timerId
      });

      this.sendRawBytes(publishPacket).catch((err: Object) => {
        const pending: PendingMqttRequest | undefined = this.pendingRequests.get(cid);
        if (pending !== undefined) {
          clearTimeout(pending.timerId);
          this.pendingRequests.delete(cid);
          pending.resolve({
            success: false,
            authFailed: false,
            newlyConnected: false,
            payloadJson: '',
            errorMessage: `发送 MQTT PUBLISH 失败: ${this.formatSocketError(err)}`
          });
        }
      });
    });
  }

  private startPingTimer(): void {
    if (this.pingTimerId !== -1) {
      clearInterval(this.pingTimerId);
    }
    this.pingTimerId = setInterval(() => {
      if ((this.activeBackend === 'tls' || this.activeBackend === 'tcp') && this.hasOpenTransport()) {
        const pingReq: Uint8Array = new Uint8Array([0xc0, 0x00]);
        this.sendRawBytes(pingReq).catch((err: Object) => {
          hilog.warn(DOMAIN, TAG, 'MQTT PINGREQ failed: %{public}s', this.formatSocketError(err));
          this.handleTransportClosed('MQTT 心跳发送失败，连接已断开');
        });
      }
    }, MQTT_PING_INTERVAL_MS);
  }

  private handleTransportClosed(reason: string): void {
    this.isConnected = false;
    this.subscribedParentMacs.clear();
    if (this.pingTimerId !== -1) {
      clearInterval(this.pingTimerId);
      this.pingTimerId = -1;
    }
    if (this.connAckWaiter !== null) {
      const waiter = this.connAckWaiter;
      this.connAckWaiter = null;
      waiter(false, false, reason);
    }
    this.pendingSubAcks.forEach((sub: PendingSubAck) => {
      clearTimeout(sub.timerId);
      sub.resolve(false);
    });
    this.pendingSubAcks.clear();

    this.pendingRequests.forEach((req: PendingMqttRequest) => {
      clearTimeout(req.timerId);
      req.resolve({
        success: false,
        authFailed: false,
        newlyConnected: false,
        payloadJson: '',
        errorMessage: reason
      });
    });
    this.pendingRequests.clear();
  }

  async disconnect(): Promise<void> {
    if ((this.activeBackend === 'tls' || this.activeBackend === 'tcp') && this.hasOpenTransport()) {
      try {
        await this.sendRawBytes(new Uint8Array([0xe0, 0x00]));
      } catch {
      }
    }
    this.handleTransportClosed('MQTT 连接已断开');
    this.rxBuffer = new Uint8Array(0);
    await this.closeActiveSocketsQuietly();
    this.activeBackend = 'none';
  }

  private async closeActiveSocketsQuietly(): Promise<void> {
    if (this.pahoClient !== null) {
      const client: MqttClient = this.pahoClient;
      this.pahoClient = null;
      await this.disposePahoClient(client);
    }
    if (this.tlsSocket !== null) {
      const sock: socket.TLSSocket = this.tlsSocket;
      this.tlsSocket = null;
      await this.disposeTlsSocket(sock);
    }
    if (this.tcpSocket !== null) {
      const sock: socket.TCPSocket = this.tcpSocket;
      this.tcpSocket = null;
      await this.disposeTcpSocket(sock);
    }
  }

  private async disposePahoClient(client: MqttClient): Promise<void> {
    if (this.pahoClient === client) {
      this.pahoClient = null;
    }
    try {
      const alive: boolean = await client.isConnected();
      if (alive) {
        await client.disconnect();
      }
    } catch {
    }
    try {
      await client.destroy();
    } catch {
    }
  }

  private async disposeTlsSocket(sock: socket.TLSSocket): Promise<void> {
    try {
      sock.off('message');
      sock.off('error');
      sock.off('close');
      await sock.close();
    } catch {
    }
  }

  private async disposeTcpSocket(sock: socket.TCPSocket): Promise<void> {
    try {
      sock.off('message');
      sock.off('error');
      sock.off('close');
      await sock.close();
    } catch {
    }
  }

  private async resolveIpv4WithTimeout(host: string, timeoutMs: number): Promise<string[]> {
    const addresses: connection.NetAddress[] = await this.runWithTimeout(
      connection.getAddressesByName(host),
      timeoutMs,
      `DNS 解析超时 (${host})`
    );
    const ipv4List: string[] = [];
    const otherList: string[] = [];
    for (let i: number = 0; i < addresses.length; i++) {
      const addr: string = addresses[i].address !== undefined ? addresses[i].address.trim() : '';
      if (addr.length === 0) {
        continue;
      }
      if (this.isIpv4Literal(addr)) {
        if (ipv4List.indexOf(addr) < 0) {
          ipv4List.push(addr);
        }
      } else if (otherList.indexOf(addr) < 0) {
        otherList.push(addr);
      }
    }
    return ipv4List.length > 0 ? ipv4List : otherList;
  }

  private isIpv4Literal(text: string): boolean {
    const parts: string[] = text.split('.');
    if (parts.length !== 4) {
      return false;
    }
    for (let i: number = 0; i < 4; i++) {
      if (parts[i].length === 0 || parts[i].length > 3) {
        return false;
      }
      for (let j: number = 0; j < parts[i].length; j++) {
        const ch: string = parts[i].charAt(j);
        if (ch < '0' || ch > '9') {
          return false;
        }
      }
      const val: number = Number(parts[i]);
      if (Number.isNaN(val) || val < 0 || val > 255) {
        return false;
      }
    }
    return true;
  }

  private delayMs(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private runWithTimeout<T>(promise: Promise<T>, timeoutMs: number, timeoutMessage: string): Promise<T> {
    return new Promise<T>((resolve: (val: T) => void, reject: (reason: Object) => void) => {
      let finished: boolean = false;
      const timerId: number = setTimeout(() => {
        if (finished) {
          return;
        }
        finished = true;
        reject(new Error(timeoutMessage));
      }, timeoutMs);

      promise.then((value: T) => {
        if (finished) {
          return;
        }
        finished = true;
        clearTimeout(timerId);
        resolve(value);
      }).catch((err: Object) => {
        if (finished) {
          return;
        }
        finished = true;
        clearTimeout(timerId);
        reject(err);
      });
    });
  }

  private formatSocketError(err: Object): string {
    if (typeof err === 'string') {
      return err;
    }
    const errObj: GenericErrorShape = err as GenericErrorShape;
    const hasCode: boolean = typeof errObj.code === 'number';
    const hasReason: boolean = typeof errObj.reasonCode === 'number' && errObj.reasonCode !== 0;
    const hasMsg: boolean = typeof errObj.message === 'string' && errObj.message.length > 0;
    if (hasCode && hasMsg) {
      return hasReason
        ? `[code=${errObj.code}, rc=${errObj.reasonCode}] ${errObj.message}`
        : `[code=${errObj.code}] ${errObj.message}`;
    }
    if (hasCode) {
      return `[code=${errObj.code}]`;
    }
    if (hasMsg) {
      return errObj.message!;
    }
    try {
      const json: string = JSON.stringify(err);
      if (json !== undefined && json !== '{}') {
        return json;
      }
    } catch {
    }
    return String(err);
  }

  private appendAndParseIncoming(chunk: Uint8Array): void {
    const merged: Uint8Array = new Uint8Array(this.rxBuffer.length + chunk.length);
    merged.set(this.rxBuffer, 0);
    merged.set(chunk, this.rxBuffer.length);
    this.rxBuffer = merged;

    while (this.rxBuffer.length >= 2) {
      const firstByte: number = this.rxBuffer[0];
      const packetType: number = (firstByte >>> 4) & 0x0f;

      let multiplier: number = 1;
      let remainingLength: number = 0;
      let offset: number = 1;
      let hasFullVarint: boolean = false;

      while (offset < this.rxBuffer.length && offset <= 4) {
        const encodedByte: number = this.rxBuffer[offset];
        remainingLength += (encodedByte & 0x7f) * multiplier;
        offset++;
        if ((encodedByte & 0x80) === 0) {
          hasFullVarint = true;
          break;
        }
        multiplier *= 128;
      }

      if (!hasFullVarint) {
        break;
      }

      const totalPacketLength: number = offset + remainingLength;
      if (this.rxBuffer.length < totalPacketLength) {
        break;
      }

      const body: Uint8Array = this.rxBuffer.slice(offset, totalPacketLength);
      this.rxBuffer = this.rxBuffer.slice(totalPacketLength);
      this.handleMqttPacket(packetType, firstByte & 0x0f, body);
    }
  }

  private handleMqttPacket(packetType: number, flags: number, body: Uint8Array): void {
    // CONNACK (packetType === 2)
    if (packetType === 2 && body.length >= 2) {
      const returnCode: number = body[1];
      hilog.info(DOMAIN, TAG, 'Received native MQTT CONNACK code=%{public}d from %{public}s:%{public}d',
        returnCode, this.currentHost, this.currentPort);
      if (this.connAckWaiter !== null) {
        const waiter = this.connAckWaiter;
        this.connAckWaiter = null;
        if (returnCode === 0) {
          waiter(true, false, '');
        } else {
          const authFailed: boolean = returnCode === 4 || returnCode === 5;
          waiter(false, authFailed, authFailed
            ? `MQTT 鉴权被拒绝 (CONNACK code=${returnCode})，请重新登录`
            : `MQTT 连接被拒绝 (CONNACK code=${returnCode})`);
        }
      }
      return;
    }

    // SUBACK (packetType === 9)
    if (packetType === 9 && body.length >= 2) {
      const packetId: number = ((body[0] & 0xff) << 8) | (body[1] & 0xff);
      const pendingSub: PendingSubAck | undefined = this.pendingSubAcks.get(packetId);
      if (pendingSub !== undefined) {
        clearTimeout(pendingSub.timerId);
        this.pendingSubAcks.delete(packetId);
        pendingSub.resolve(true);
      }
      return;
    }

    // PUBLISH (packetType === 3)
    if (packetType === 3 && body.length >= 2) {
      const qos: number = (flags >>> 1) & 0x03;
      const retained: boolean = (flags & 0x01) !== 0;
      const topicLen: number = ((body[0] & 0xff) << 8) | (body[1] & 0xff);
      if (2 + topicLen > body.length) {
        return;
      }
      const topic: string = GreeCryptoUtil.bytesToUtf8(body.slice(2, 2 + topicLen));
      let payloadStart: number = 2 + topicLen;
      if (qos > 0) {
        if (payloadStart + 2 > body.length) {
          return;
        }
        const packetIdHigh: number = body[payloadStart];
        const packetIdLow: number = body[payloadStart + 1];
        payloadStart += 2;
        if (qos === 1 && this.hasOpenTransport()) {
          const puback: Uint8Array = new Uint8Array([0x40, 0x02, packetIdHigh, packetIdLow]);
          this.sendRawBytes(puback).catch(() => {});
        }
      }
      const payloadStr: string = GreeCryptoUtil.bytesToUtf8(body.slice(payloadStart));
      this.handleIncomingPublish(topic, payloadStr, retained).catch((err: Object) => {
        hilog.warn(DOMAIN, TAG, 'handleIncomingPublish error: %{public}s', this.formatSocketError(err));
      });
    }
  }

  private async decryptEnvelopeWithCandidateKeys(
    kind: string,
    topicMac: string,
    normCid: string,
    normTcid: string,
    pack: string
  ): Promise<string> {
    if (kind === 'connect') {
      return await GreeCryptoUtil.decryptPack(pack, GREE_GENERIC_KEY);
    }
    const candidateKeys: string[] = [];
    const addKey = (k: string | undefined): void => {
      if (k !== undefined && k.length > 0 && candidateKeys.indexOf(k) < 0) {
        candidateKeys.push(k);
      }
    };
    addKey(this.deviceKeysByMac.get(topicMac));
    addKey(this.deviceKeysByMac.get(normTcid));
    addKey(this.deviceKeysByMac.get(normCid));
    this.deviceKeysByMac.forEach((val: string) => {
      addKey(val);
    });
    addKey(GREE_GENERIC_KEY);

    for (let i: number = 0; i < candidateKeys.length; i++) {
      const plain: string = await GreeCryptoUtil.decryptPack(pack, candidateKeys[i]);
      if (plain.length > 0 && plain.startsWith('{')) {
        return plain;
      }
    }
    return '';
  }

  private async handleIncomingPublish(topic: string, payloadStr: string, retained: boolean): Promise<void> {
    hilog.info(DOMAIN, TAG, 'MQTT PUBLISH recv topic=%{public}s retained=%{public}s raw=%{public}s',
      topic, String(retained), payloadStr.slice(0, 300));

    const parts: string[] = topic.split('/');
    if (parts.length < 2) {
      return;
    }
    const kind: string = parts[0].toLowerCase();
    const topicMac: string = GreeMqttTlsClient.normalizeMac(parts[1]);

    let envelope: GreeMqttPackEnvelope | null = null;
    try {
      envelope = JSON.parse(payloadStr) as GreeMqttPackEnvelope;
    } catch {
      return;
    }
    if (envelope === null || typeof envelope.pack !== 'string' || envelope.pack.length === 0) {
      return;
    }

    const rawTcid: string = typeof envelope.tcid === 'string' ? envelope.tcid.trim() : '';
    const rawCid: string = typeof envelope.cid === 'string' ? envelope.cid.trim() : '';
    const normTcid: string = GreeMqttTlsClient.normalizeMac(rawTcid);
    const normCid: string = GreeMqttTlsClient.normalizeMac(rawCid);

    const plainJson: string = await this.decryptEnvelopeWithCandidateKeys(
      kind,
      topicMac,
      normCid,
      normTcid,
      envelope.pack
    );
    if (plainJson.length === 0) {
      hilog.warn(DOMAIN, TAG, 'Failed to decrypt MQTT pack on topic=%{public}s tcid=%{public}s cid=%{public}s',
        topic, rawTcid, rawCid);
      return;
    }

    hilog.info(DOMAIN, TAG, 'Decrypted MQTT [%{public}s]: %{public}s', topic, plainJson.slice(0, 600));

    let innerType: string = '';
    try {
      const probe: GreeInnerTypeProbe = JSON.parse(plainJson) as GreeInnerTypeProbe;
      if (probe !== null && typeof probe.t === 'string') {
        innerType = probe.t;
      }
    } catch {
    }
    const isDatOrRes: boolean = innerType === 'dat' || innerType === 'res';

    // 1. Exact cid <-> envelope.tcid match on response/
    if (kind === 'response' && rawTcid.length > 0) {
      const exactPending: PendingMqttRequest | undefined = this.pendingRequests.get(rawTcid);
      if (exactPending !== undefined) {
        clearTimeout(exactPending.timerId);
        this.pendingRequests.delete(rawTcid);
        exactPending.resolve({
          success: true,
          authFailed: false,
          newlyConnected: false,
          payloadJson: plainJson,
          errorMessage: ''
        });
        return;
      }
    }

    // 2. Device MAC match on response/ or live dat/res push on status/
    if (kind === 'response' || (kind === 'status' && !retained && isDatOrRes)) {
      let matchedCid: string = '';
      this.pendingRequests.forEach((req: PendingMqttRequest, cidKey: string) => {
        if (matchedCid.length > 0) {
          return;
        }
        const macMatches: boolean =
          req.childMac === topicMac ||
          req.parentMac === topicMac ||
          req.childMac === normTcid ||
          req.parentMac === normTcid ||
          req.childMac === normCid ||
          req.parentMac === normCid;
        if (macMatches && (kind === 'response' || isDatOrRes)) {
          matchedCid = cidKey;
        }
      });

      if (matchedCid.length > 0) {
        const matchedPending: PendingMqttRequest | undefined = this.pendingRequests.get(matchedCid);
        if (matchedPending !== undefined) {
          clearTimeout(matchedPending.timerId);
          this.pendingRequests.delete(matchedCid);
          matchedPending.resolve({
            success: true,
            authFailed: false,
            newlyConnected: false,
            payloadJson: plainJson,
            errorMessage: ''
          });
          return;
        }
      }
    }

    if (this.pushHandler !== null) {
      this.pushHandler(kind, topicMac, plainJson);
    }
  }

  private allocatePacketId(): number {
    const id: number = this.nextPacketId;
    this.nextPacketId = this.nextPacketId >= 65535 ? 1 : this.nextPacketId + 1;
    return id;
  }

  private encodeUtf8Field(text: string): Uint8Array {
    const strBytes: Uint8Array = GreeCryptoUtil.utf8ToBytes(text);
    const out: Uint8Array = new Uint8Array(2 + strBytes.length);
    out[0] = (strBytes.length >>> 8) & 0xff;
    out[1] = strBytes.length & 0xff;
    out.set(strBytes, 2);
    return out;
  }

  /**
   * Encodes MQTT 3.1.1 variable-length Remaining Length (1 to 4 bytes, up to 256MB).
   */
  private encodeRemainingLength(length: number): Uint8Array {
    const encoded: number[] = [];
    let x: number = length;
    do {
      let digit: number = x % 128;
      x = Math.floor(x / 128);
      if (x > 0) {
        digit = digit | 0x80;
      }
      encoded.push(digit);
    } while (x > 0);
    return new Uint8Array(encoded);
  }

  private concatArrays(parts: Uint8Array[]): Uint8Array {
    let total: number = 0;
    for (let i: number = 0; i < parts.length; i++) {
      total += parts[i].length;
    }
    const result: Uint8Array = new Uint8Array(total);
    let offset: number = 0;
    for (let i: number = 0; i < parts.length; i++) {
      result.set(parts[i], offset);
      offset += parts[i].length;
    }
    return result;
  }

  private buildConnectPacket(clientId: string, username: string, password: string): Uint8Array {
    const varHeader: Uint8Array = new Uint8Array([
      0x00, 0x04, 0x4d, 0x51, 0x54, 0x54,
      0x04,
      0xc2,
      (MQTT_KEEPALIVE_SEC >>> 8) & 0xff,
      MQTT_KEEPALIVE_SEC & 0xff
    ]);
    const payload: Uint8Array = this.concatArrays([
      this.encodeUtf8Field(clientId),
      this.encodeUtf8Field(username),
      this.encodeUtf8Field(password)
    ]);
    const body: Uint8Array = this.concatArrays([varHeader, payload]);
    const remLen: Uint8Array = this.encodeRemainingLength(body.length);
    return this.concatArrays([new Uint8Array([0x10]), remLen, body]);
  }

  private buildSubscribePacket(packetId: number, topics: string[]): Uint8Array {
    const pidBytes: Uint8Array = new Uint8Array([(packetId >>> 8) & 0xff, packetId & 0xff]);
    const parts: Uint8Array[] = [pidBytes];
    for (let i: number = 0; i < topics.length; i++) {
      parts.push(this.encodeUtf8Field(topics[i]));
      parts.push(new Uint8Array([0x01]));
    }
    const body: Uint8Array = this.concatArrays(parts);
    const remLen: Uint8Array = this.encodeRemainingLength(body.length);
    return this.concatArrays([new Uint8Array([0x82]), remLen, body]);
  }

  private buildPublishPacket(topic: string, payloadBytes: Uint8Array, packetId: number): Uint8Array {
    const topicField: Uint8Array = this.encodeUtf8Field(topic);
    const pidBytes: Uint8Array = new Uint8Array([(packetId >>> 8) & 0xff, packetId & 0xff]);
    const body: Uint8Array = this.concatArrays([topicField, pidBytes, payloadBytes]);
    const remLen: Uint8Array = this.encodeRemainingLength(body.length);
    return this.concatArrays([new Uint8Array([0x32]), remLen, body]);
  }

  private randomHex(len: number): string {
    const chars: string = '0123456789abcdef';
    let out: string = '';
    for (let i: number = 0; i < len; i++) {
      out += chars.charAt(Math.floor(Math.random() * 16));
    }
    return out;
  }

  private generateCid(): string {
    const n: number = 1000000000 + Math.floor(Math.random() * 8999999999);
    return `${n}`;
  }
}
