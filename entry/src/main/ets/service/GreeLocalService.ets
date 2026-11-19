import { socket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CMD_MAX_RETRIES,
  CMD_TIMEOUT_MS,
  DEVICE_OFFLINE_THRESHOLD_MS,
  GREE_APP_CID,
  GREE_GENERIC_KEY,
  GREE_LOCAL_GCM_KEY,
  GREE_STATUS_COLS,
  GREE_UDP_PORT,
  GreeOnlineChannel,
  POLL_INTERVAL_MS,
  SCAN_RETRY_COUNT
} from '../common/constants/GreeConstants';
import { GreeCryptoUtil } from '../common/utils/GreeCryptoUtil';
import { NetworkUtil } from '../common/utils/NetworkUtil';
import { StorageUtil } from '../common/utils/StorageUtil';
import { GreeDeviceModel } from '../model/GreeDeviceModel';
import {
  GreeBindOkPack,
  GreeBindReqPack,
  GreeCloudDeviceDto,
  GreeCmdReqPack,
  GreeDatPack,
  GreeDevPack,
  GreeInnerTypeProbe,
  GreeOuterPack,
  GreeResPack,
  GreeScanPack,
  GreeStatusReqPack,
  PersistedDeviceInfo
} from '../model/GreeProtocolTypes';

const DOMAIN: number = 0x4752;
const TAG: string = 'GreeLocalService';

export interface ManualIpProbeResult {
  device: GreeDeviceModel | null;
  responded: boolean;
  message: string;
}

interface PendingCmdItem {
  mac: string;
  ip: string;
  port: number;
  key: string;
  opt: string[];
  p: number[];
  resolve: (ok: boolean) => void;
}

interface ActiveCmdWaiter {
  mac: string;
  optKey: string;
  resolve: (ok: boolean) => void;
  timerId: number;
}

export type DevicePoolChangeListener = () => void;

/**
 * Manages the UDP port-7000 lifecycle, dual-broadcast LAN discovery, AES key binding,
 * serialized command queue with retry/timeout, and 5-second background polling.
 */
export class GreeLocalService {
  private static instance: GreeLocalService | null = null;

  private udpSocket: socket.UDPSocket | null = null;
  private socketReady: boolean = false;
  private isDestroyed: boolean = false;
  private reconnecting: boolean = false;
  private pollTimerId: number = -1;

  private devicesByMac: Map<string, GreeDeviceModel> = new Map<string, GreeDeviceModel>();
  private listeners: DevicePoolChangeListener[] = [];

  private cmdQueue: PendingCmdItem[] = [];
  private isProcessingCmdQueue: boolean = false;
  private activeWaiter: ActiveCmdWaiter | null = null;

  private readonly onMessageBound = (info: socket.SocketMessageInfo): void => {
    this.handleUdpMessage(info).catch((err: Object) => {
      hilog.error(DOMAIN, TAG, 'handleUdpMessage error: %{public}s', String(err));
    });
  };

  private readonly onErrorBound = (err: Object): void => {
    hilog.error(DOMAIN, TAG, 'UDP socket error event: %{public}s', String(err));
    this.socketReady = false;
    if (!this.isDestroyed) {
      this.scheduleReconnect();
    }
  };

  private readonly onCloseBound = (): void => {
    hilog.warn(DOMAIN, TAG, 'UDP socket closed event');
    this.socketReady = false;
    if (!this.isDestroyed) {
      this.scheduleReconnect();
    }
  };

  static getInstance(): GreeLocalService {
    if (GreeLocalService.instance === null) {
      GreeLocalService.instance = new GreeLocalService();
    }
    return GreeLocalService.instance;
  }

  addListener(listener: DevicePoolChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  removeListener(listener: DevicePoolChangeListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  private notifyListeners(): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i]();
    }
  }

  getDevicesSnapshot(): GreeDeviceModel[] {
    const list: GreeDeviceModel[] = [];
    this.devicesByMac.forEach((dev: GreeDeviceModel) => {
      list.push(dev);
    });
    return list;
  }

  getDeviceByMac(mac: string): GreeDeviceModel | null {
    const normalized: string = mac.trim().toLowerCase();
    let found: GreeDeviceModel | null = null;
    this.devicesByMac.forEach((dev: GreeDeviceModel, key: string) => {
      if (key.toLowerCase() === normalized) {
        found = dev;
      }
    });
    return found;
  }

  async init(): Promise<void> {
    this.isDestroyed = false;
    await this.loadPersistedDevices();
    await this.ensureSocketReady();
    this.startPollingTimer();
  }

  private async loadPersistedDevices(): Promise<void> {
    const saved: PersistedDeviceInfo[] = await StorageUtil.getInstance().loadDevices();
    for (let i: number = 0; i < saved.length; i++) {
      const dev: GreeDeviceModel = GreeDeviceModel.fromPersistedInfo(saved[i]);
      this.devicesByMac.set(dev.mac.toLowerCase(), dev);
    }
    this.notifyListeners();
  }

  private async ensureSocketReady(): Promise<boolean> {
    if (this.isDestroyed) {
      return false;
    }
    if (this.udpSocket !== null && this.socketReady) {
      return true;
    }
    try {
      await this.closeSocketInternal();
      const sock: socket.UDPSocket = socket.constructUDPSocketInstance();
      sock.on('message', this.onMessageBound);
      sock.on('error', this.onErrorBound);
      sock.on('close', this.onCloseBound);

      const bindAddr: socket.NetAddress = {
        address: '0.0.0.0',
        port: 0,
        family: 1
      };
      await sock.bind(bindAddr);

      const extraOpts: socket.UDPExtraOptions = {
        broadcast: true,
        receiveBufferSize: 65536,
        sendBufferSize: 65536
      };
      await sock.setExtraOptions(extraOpts);

      this.udpSocket = sock;
      this.socketReady = true;
      hilog.info(DOMAIN, TAG, 'UDP socket bound and broadcast enabled');
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'ensureSocketReady failed: %{public}s', String(err));
      this.socketReady = false;
      return false;
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnecting || this.isDestroyed) {
      return;
    }
    this.reconnecting = true;
    setTimeout(() => {
      this.reconnecting = false;
      if (!this.isDestroyed) {
        this.ensureSocketReady().catch((err: Object) => {
          hilog.warn(DOMAIN, TAG, 'Reconnect attempt failed: %{public}s', String(err));
        });
      }
    }, 1000);
  }

  private async closeSocketInternal(): Promise<void> {
    if (this.udpSocket !== null) {
      const sock: socket.UDPSocket = this.udpSocket;
      this.udpSocket = null;
      this.socketReady = false;
      try {
        sock.off('message', this.onMessageBound);
        sock.off('error', this.onErrorBound);
        sock.off('close', this.onCloseBound);
        await sock.close();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'closeSocketInternal ignored error: %{public}s', String(err));
      }
    }
  }

  private startPollingTimer(): void {
    if (this.pollTimerId !== -1) {
      clearInterval(this.pollTimerId);
    }
    this.pollTimerId = setInterval(() => {
      this.pollAllDevices().catch((err: Object) => {
        hilog.warn(DOMAIN, TAG, 'pollAllDevices error: %{public}s', String(err));
      });
    }, POLL_INTERVAL_MS);
  }

  async pollAllDevices(): Promise<void> {
    const now: number = Date.now();
    const targets: GreeDeviceModel[] = [];
    let changed: boolean = false;

    this.devicesByMac.forEach((dev: GreeDeviceModel) => {
      if (dev.mac.startsWith('manual_')) {
        return;
      }
      if (dev.onlineChannel === GreeOnlineChannel.LAN &&
        dev.lastSeenMs > 0 &&
        now - dev.lastSeenMs > DEVICE_OFFLINE_THRESHOLD_MS) {
        dev.onlineChannel = dev.homeId.length > 0 ? GreeOnlineChannel.CLOUD : GreeOnlineChannel.OFFLINE;
        changed = true;
      }
      if (dev.ip.length > 0 && dev.key.length > 0 && dev.isBound) {
        targets.push(dev);
      }
    });

    if (changed) {
      this.notifyListeners();
    }

    for (let i: number = 0; i < targets.length; i++) {
      await this.requestDeviceStatus(targets[i]);
    }
  }

  /**
   * Dual-broadcasts {"t":"scan"} to 255.255.255.255:7000 and the directed Wi-Fi subnet broadcast
   * (e.g. 192.168.x.255:7000), plus unicasts to known device IPs.
   */
  async scanLanDevices(): Promise<string[]> {
    const ready: boolean = await this.ensureSocketReady();
    const targets: string[] = NetworkUtil.getDiscoveryBroadcastTargets();
    if (!ready) {
      return targets;
    }

    const scanPack: GreeScanPack = { t: 'scan' };
    const payload: string = JSON.stringify(scanPack);

    // Also probe cached device IPs directly in case router blocks UDP broadcast
    const allTargets: string[] = [];
    for (let i: number = 0; i < targets.length; i++) {
      allTargets.push(targets[i]);
    }
    this.devicesByMac.forEach((dev: GreeDeviceModel) => {
      if (dev.ip.length > 0 && !dev.mac.startsWith('manual_') && allTargets.indexOf(dev.ip) < 0) {
        allTargets.push(dev.ip);
      }
    });

    for (let round: number = 0; round < SCAN_RETRY_COUNT; round++) {
      for (let i: number = 0; i < allTargets.length; i++) {
        await this.sendRawUdp(payload, allTargets[i], GREE_UDP_PORT);
      }
      if (round + 1 < SCAN_RETRY_COUNT) {
        await this.delayMs(250);
      }
    }
    return targets;
  }

  /**
   * Sends unicast {"t":"scan"} directly to an AC IP on port 7000 and waits briefly for discovery.
   */
  async addOrProbeDeviceByIp(ip: string, customName?: string): Promise<ManualIpProbeResult> {
    const cleanIp: string = ip.trim();
    if (!NetworkUtil.isValidIpv4(cleanIp)) {
      return {
        device: null,
        responded: false,
        message: '请输入合法的 IPv4 地址（例如 192.168.1.100）'
      };
    }

    await this.ensureSocketReady();
    const scanPack: GreeScanPack = { t: 'scan' };
    const payload: string = JSON.stringify(scanPack);

    // Remember pending manual name so dev response can inherit custom name if desired
    await this.sendRawUdp(payload, cleanIp, GREE_UDP_PORT);
    await this.delayMs(200);
    await this.sendRawUdp(payload, cleanIp, GREE_UDP_PORT);
    await this.delayMs(1100);

    let matched: GreeDeviceModel | null = null;
    this.devicesByMac.forEach((dev: GreeDeviceModel) => {
      if (dev.ip === cleanIp && !dev.mac.startsWith('manual_')) {
        matched = dev;
      }
    });

    if (matched !== null) {
      const resolvedDevice: GreeDeviceModel = matched;
      if (customName !== undefined && customName.trim().length > 0) {
        resolvedDevice.name = customName.trim();
        await StorageUtil.getInstance().upsertDevice(resolvedDevice.toPersistedInfo());
      }
      this.notifyListeners();
      return {
        device: resolvedDevice,
        responded: true,
        message: `已发现并连接设备 ${resolvedDevice.name} (${cleanIp})`
      };
    }

    // Create a manual IP entry so user can retry probing when device is reachable
    const manualMac: string = `manual_${cleanIp.replace(/\./g, '_')}`;
    const displayName: string = customName !== undefined && customName.trim().length > 0
      ? customName.trim()
      : `手动空调 (${cleanIp})`;
    const placeholder: GreeDeviceModel = new GreeDeviceModel(manualMac, displayName);
    placeholder.ip = cleanIp;
    placeholder.port = GREE_UDP_PORT;
    placeholder.onlineChannel = GreeOnlineChannel.OFFLINE;
    this.devicesByMac.set(manualMac.toLowerCase(), placeholder);
    await StorageUtil.getInstance().upsertDevice(placeholder.toPersistedInfo());
    this.notifyListeners();

    return {
      device: placeholder,
      responded: false,
      message: '暂未收到该设备响应，已保存地址供稍后重试'
    };
  }

  async sendBindRequest(device: GreeDeviceModel): Promise<void> {
    if (device.ip.length === 0 || device.mac.length === 0) {
      return;
    }
    const innerBind: GreeBindReqPack = {
      mac: device.mac,
      t: 'bind',
      uid: 0
    };
    const encrypted: string = await GreeCryptoUtil.encryptPack(JSON.stringify(innerBind), GREE_GENERIC_KEY);
    if (encrypted.length === 0) {
      return;
    }
    const outer: GreeOuterPack = {
      cid: GREE_APP_CID,
      i: 1,
      pack: encrypted,
      t: 'pack',
      tcid: device.mac,
      uid: 0
    };
    await this.sendRawUdp(JSON.stringify(outer), device.ip, device.port);
  }

  async requestDeviceStatus(device: GreeDeviceModel): Promise<void> {
    if (device.ip.length === 0 || device.key.length === 0) {
      return;
    }
    const statusReq: GreeStatusReqPack = {
      cols: GREE_STATUS_COLS,
      mac: device.mac,
      t: 'status'
    };
    const encrypted: string = await GreeCryptoUtil.encryptPack(JSON.stringify(statusReq), device.key);
    if (encrypted.length === 0) {
      return;
    }
    const outer: GreeOuterPack = {
      cid: GREE_APP_CID,
      i: 0,
      pack: encrypted,
      t: 'pack',
      tcid: device.mac,
      uid: 0
    };
    await this.sendRawUdp(JSON.stringify(outer), device.ip, device.port);
  }

  /**
   * Queues a command (`t === "cmd"`, outer `i: 0`, encrypted with device-specific `key`)
   * and waits for `t === "res"` acknowledgement with automatic retries on timeout.
   */
  sendCommand(device: GreeDeviceModel, opt: string[], p: number[]): Promise<boolean> {
    if (device.ip.length === 0 || device.key.length === 0 || opt.length === 0 || opt.length !== p.length) {
      return Promise.resolve(false);
    }
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      const item: PendingCmdItem = {
        mac: device.mac,
        ip: device.ip,
        port: device.port,
        key: device.key,
        opt: opt,
        p: p,
        resolve: resolve
      };
      this.cmdQueue.push(item);
      if (!this.isProcessingCmdQueue) {
        this.processCommandQueue().catch((err: Object) => {
          hilog.error(DOMAIN, TAG, 'processCommandQueue error: %{public}s', String(err));
        });
      }
    });
  }

  private async processCommandQueue(): Promise<void> {
    this.isProcessingCmdQueue = true;
    while (this.cmdQueue.length > 0 && !this.isDestroyed) {
      const nextItem: PendingCmdItem | undefined = this.cmdQueue.shift();
      if (nextItem === undefined) {
        continue;
      }
      const ok: boolean = await this.executeCommandWithRetry(nextItem);
      nextItem.resolve(ok);
    }
    this.isProcessingCmdQueue = false;
  }

  private async executeCommandWithRetry(item: PendingCmdItem): Promise<boolean> {
    const ready: boolean = await this.ensureSocketReady();
    if (!ready) {
      return false;
    }

    const cmdInner: GreeCmdReqPack = {
      opt: item.opt,
      p: item.p,
      t: 'cmd'
    };
    const encrypted: string = await GreeCryptoUtil.encryptPack(JSON.stringify(cmdInner), item.key);
    if (encrypted.length === 0) {
      return false;
    }

    const outer: GreeOuterPack = {
      cid: GREE_APP_CID,
      i: 0,
      pack: encrypted,
      t: 'pack',
      tcid: item.mac,
      uid: 0
    };
    const payload: string = JSON.stringify(outer);
    const optKey: string = item.opt.join(',');

    for (let attempt: number = 0; attempt <= CMD_MAX_RETRIES; attempt++) {
      const acked: boolean = await this.sendAndAwaitAck(item.mac, optKey, payload, item.ip, item.port);
      if (acked) {
        return true;
      }
      if (attempt < CMD_MAX_RETRIES) {
        hilog.warn(DOMAIN, TAG, 'Command timeout for %{public}s [%{public}s], retrying (%{public}d)',
          item.mac, optKey, attempt + 1);
      }
    }
    return false;
  }

  private sendAndAwaitAck(
    mac: string,
    optKey: string,
    payload: string,
    ip: string,
    port: number
  ): Promise<boolean> {
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      if (this.activeWaiter !== null) {
        clearTimeout(this.activeWaiter.timerId);
        this.activeWaiter.resolve(false);
        this.activeWaiter = null;
      }

      const timerId: number = setTimeout(() => {
        if (this.activeWaiter !== null && this.activeWaiter.timerId === timerId) {
          this.activeWaiter = null;
          resolve(false);
        }
      }, CMD_TIMEOUT_MS);

      this.activeWaiter = {
        mac: mac.toLowerCase(),
        optKey: optKey,
        resolve: resolve,
        timerId: timerId
      };

      this.sendRawUdp(payload, ip, port).then((sent: boolean) => {
        if (!sent && this.activeWaiter !== null && this.activeWaiter.timerId === timerId) {
          clearTimeout(timerId);
          this.activeWaiter = null;
          resolve(false);
        }
      }).catch(() => {
        if (this.activeWaiter !== null && this.activeWaiter.timerId === timerId) {
          clearTimeout(timerId);
          this.activeWaiter = null;
          resolve(false);
        }
      });
    });
  }

  private async sendRawUdp(jsonPayload: string, ip: string, port: number): Promise<boolean> {
    if (this.udpSocket === null || !this.socketReady) {
      return false;
    }
    try {
      const targetAddr: socket.NetAddress = {
        address: ip,
        port: port,
        family: 1
      };
      const bytes: Uint8Array = GreeCryptoUtil.utf8ToBytes(jsonPayload);
      const sendOpts: socket.UDPSendOptions = {
        data: bytes.buffer,
        address: targetAddr
      };
      await this.udpSocket.send(sendOpts);
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'sendRawUdp to %{public}s failed: %{public}s', ip, String(err));
      return false;
    }
  }

  private async handleUdpMessage(info: socket.SocketMessageInfo): Promise<void> {
    const rawBytes: Uint8Array = new Uint8Array(info.message);
    const rawText: string = GreeCryptoUtil.bytesToUtf8(rawBytes).trim();
    if (rawText.length === 0) {
      return;
    }

    let outer: GreeOuterPack | null = null;
    try {
      outer = JSON.parse(rawText) as GreeOuterPack;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Invalid JSON from %{public}s', info.remoteInfo.address);
      return;
    }

    if (outer === null || outer.t !== 'pack' || typeof outer.pack !== 'string' || outer.pack.length === 0) {
      return;
    }

    const senderIp: string = info.remoteInfo.address;
    const senderPort: number = info.remoteInfo.port > 0 ? info.remoteInfo.port : GREE_UDP_PORT;
    const matchedDev: GreeDeviceModel | null = this.findDeviceByTcidOrIp(outer.tcid, senderIp);

    const plainJson: string = await this.decryptOuterPack(outer, matchedDev);
    if (plainJson.length === 0) {
      return;
    }

    let probe: GreeInnerTypeProbe | null = null;
    try {
      probe = JSON.parse(plainJson) as GreeInnerTypeProbe;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to parse decrypted inner JSON from %{public}s', senderIp);
      return;
    }
    if (probe === null || typeof probe.t !== 'string') {
      return;
    }

    switch (probe.t) {
      case 'dev':
        await this.onDevDiscovered(JSON.parse(plainJson) as GreeDevPack, senderIp, senderPort);
        break;
      case 'bindok':
        await this.onBindOk(JSON.parse(plainJson) as GreeBindOkPack, senderIp, senderPort);
        break;
      case 'dat':
        await this.onStatusData(JSON.parse(plainJson) as GreeDatPack, outer.tcid, senderIp);
        break;
      case 'res':
        await this.onCmdResponse(JSON.parse(plainJson) as GreeResPack, outer.tcid, senderIp);
        break;
      default:
        break;
    }
  }

  private async decryptOuterPack(outer: GreeOuterPack, device: GreeDeviceModel | null): Promise<string> {
    const hasDeviceKey: boolean = device !== null && device.key.length > 0;
    const hasTag: boolean = outer.tag !== undefined && outer.tag.length > 0;

    if (hasTag && outer.tag !== undefined) {
      if (outer.i === 0 && hasDeviceKey && device !== null) {
        const gcmDev: string = await GreeCryptoUtil.decryptPackGcm(outer.pack, outer.tag, device.key);
        if (gcmDev.length > 0) {
          return gcmDev;
        }
      }
      const gcmGeneric: string = await GreeCryptoUtil.decryptPackGcm(outer.pack, outer.tag, GREE_LOCAL_GCM_KEY);
      if (gcmGeneric.length > 0) {
        return gcmGeneric;
      }
      if (hasDeviceKey && device !== null) {
        return await GreeCryptoUtil.decryptPackGcm(outer.pack, outer.tag, device.key);
      }
      return '';
    }

    if (outer.i === 0 && hasDeviceKey && device !== null) {
      const decryptedWithDevKey: string = await GreeCryptoUtil.decryptPack(outer.pack, device.key);
      if (decryptedWithDevKey.length > 0) {
        return decryptedWithDevKey;
      }
      return await GreeCryptoUtil.decryptPack(outer.pack, GREE_GENERIC_KEY);
    }

    const decryptedWithGeneric: string = await GreeCryptoUtil.decryptPack(outer.pack, GREE_GENERIC_KEY);
    if (decryptedWithGeneric.length > 0) {
      return decryptedWithGeneric;
    }
    if (hasDeviceKey && device !== null) {
      return await GreeCryptoUtil.decryptPack(outer.pack, device.key);
    }
    return '';
  }

  private findDeviceByTcidOrIp(tcid: string | undefined, ip: string): GreeDeviceModel | null {
    if (tcid !== undefined && tcid.length > 0) {
      const byMac: GreeDeviceModel | null = this.getDeviceByMac(tcid);
      if (byMac !== null) {
        return byMac;
      }
    }
    let foundByIp: GreeDeviceModel | null = null;
    this.devicesByMac.forEach((dev: GreeDeviceModel) => {
      if (dev.ip === ip && !dev.mac.startsWith('manual_')) {
        foundByIp = dev;
      }
    });
    return foundByIp;
  }

  private async onDevDiscovered(devPack: GreeDevPack, ip: string, port: number): Promise<void> {
    if (typeof devPack.mac !== 'string' || devPack.mac.length === 0) {
      return;
    }
    const macKey: string = devPack.mac.toLowerCase();

    // Remove placeholder manual_<ip> entry if real MAC just answered from that IP
    const manualPlaceholderKey: string = `manual_${ip.replace(/\./g, '_')}`;
    let inheritedName: string = '';
    const existingPlaceholder: GreeDeviceModel | undefined = this.devicesByMac.get(manualPlaceholderKey);
    if (existingPlaceholder !== undefined) {
      inheritedName = existingPlaceholder.name;
      this.devicesByMac.delete(manualPlaceholderKey);
      await StorageUtil.getInstance().removeDevice(existingPlaceholder.mac);
    }

    let device: GreeDeviceModel | null = this.getDeviceByMac(macKey);
    if (device === null) {
      const devName: string = devPack.name !== undefined && devPack.name.length > 0
        ? devPack.name
        : (inheritedName.length > 0 && !inheritedName.startsWith('手动空调') ? inheritedName : `Gree ${devPack.mac.slice(-4)}`);
      device = new GreeDeviceModel(devPack.mac, devName);
      this.devicesByMac.set(macKey, device);
    } else if (devPack.name !== undefined && devPack.name.length > 0 && device.name.startsWith('Gree ')) {
      device.name = devPack.name;
    }

    device.ip = ip;
    device.port = port;
    device.brand = devPack.brand !== undefined && devPack.brand.length > 0 ? devPack.brand : device.brand;
    device.model = devPack.model !== undefined && devPack.model.length > 0 ? devPack.model : device.model;
    device.ver = devPack.ver !== undefined && devPack.ver.length > 0 ? devPack.ver : device.ver;
    device.lastSeenMs = Date.now();
    device.onlineChannel = GreeOnlineChannel.LAN;

    await StorageUtil.getInstance().upsertDevice(device.toPersistedInfo());
    this.notifyListeners();

    if (!device.isBound || device.key.length === 0) {
      await this.sendBindRequest(device);
    } else {
      await this.requestDeviceStatus(device);
    }
  }

  private async onBindOk(bindPack: GreeBindOkPack, ip: string, port: number): Promise<void> {
    if (typeof bindPack.mac !== 'string' || typeof bindPack.key !== 'string' || bindPack.key.length === 0) {
      return;
    }
    const macKey: string = bindPack.mac.toLowerCase();
    let device: GreeDeviceModel | null = this.getDeviceByMac(macKey);
    if (device === null) {
      device = new GreeDeviceModel(bindPack.mac, `Gree ${bindPack.mac.slice(-4)}`);
      this.devicesByMac.set(macKey, device);
    }
    device.ip = ip;
    device.port = port;
    device.key = bindPack.key;
    device.isBound = true;
    device.lastSeenMs = Date.now();
    device.onlineChannel = GreeOnlineChannel.LAN;

    await StorageUtil.getInstance().upsertDevice(device.toPersistedInfo());
    this.notifyListeners();
    hilog.info(DOMAIN, TAG, 'Device bound and AES key persisted: %{public}s', device.mac);

    await this.requestDeviceStatus(device);
  }

  private async onStatusData(datPack: GreeDatPack, tcid: string | undefined, ip: string): Promise<void> {
    const targetMac: string | undefined = datPack.mac !== undefined && datPack.mac.length > 0 ? datPack.mac : tcid;
    const device: GreeDeviceModel | null = this.findDeviceByTcidOrIp(targetMac, ip);
    if (device === null) {
      return;
    }
    if (Array.isArray(datPack.cols) && Array.isArray(datPack.dat)) {
      device.applyStatusArrays(datPack.cols, datPack.dat);
    }
    device.ip = ip;
    device.lastSeenMs = Date.now();
    device.onlineChannel = GreeOnlineChannel.LAN;
    await StorageUtil.getInstance().upsertDevice(device.toPersistedInfo());
    this.notifyListeners();
  }

  private async onCmdResponse(resPack: GreeResPack, tcid: string | undefined, ip: string): Promise<void> {
    const device: GreeDeviceModel | null = this.findDeviceByTcidOrIp(tcid, ip);
    if (device !== null) {
      const values: number[] = resPack.val !== undefined ? resPack.val : (resPack.p !== undefined ? resPack.p : []);
      if (Array.isArray(resPack.opt) && values.length > 0) {
        device.applyStatusArrays(resPack.opt, values);
      }
      device.ip = ip;
      device.lastSeenMs = Date.now();
      device.onlineChannel = GreeOnlineChannel.LAN;
      await StorageUtil.getInstance().upsertDevice(device.toPersistedInfo());
      this.notifyListeners();
    }

    if (this.activeWaiter !== null) {
      const waiterMacMatches: boolean = device !== null
        ? device.mac.toLowerCase() === this.activeWaiter.mac
        : (tcid !== undefined && tcid.toLowerCase() === this.activeWaiter.mac);
      if (waiterMacMatches) {
        const waiter: ActiveCmdWaiter = this.activeWaiter;
        this.activeWaiter = null;
        clearTimeout(waiter.timerId);
        waiter.resolve(true);
      }
    }
  }

  /**
   * Merges devices and keys fetched from Overseas Gree+ Cloud into the local device pool,
   * enabling zero-latency LAN UDP direct control whenever on the same Wi-Fi network.
   */
  async mergeCloudDevices(
    cloudDevs: GreeCloudDeviceDto[],
    countryCode: string,
    apiBaseUrl: string
  ): Promise<number> {
    let mergedCount: number = 0;
    for (let i: number = 0; i < cloudDevs.length; i++) {
      const dto: GreeCloudDeviceDto = cloudDevs[i];
      if (dto.mac.length === 0) {
        continue;
      }
      const macKey: string = dto.mac.toLowerCase();
      let device: GreeDeviceModel | null = this.getDeviceByMac(macKey);
      if (device === null) {
        device = new GreeDeviceModel(dto.mac, dto.name);
        this.devicesByMac.set(macKey, device);
      } else if (dto.name.length > 0) {
        device.name = dto.name;
      }

      if (dto.brand !== undefined && dto.brand.length > 0) {
        device.brand = dto.brand;
      }
      if (dto.model !== undefined && dto.model.length > 0) {
        device.model = dto.model;
      }
      if (dto.ver !== undefined && dto.ver.length > 0) {
        device.ver = dto.ver;
      }
      if (dto.parentMac !== undefined && dto.parentMac.length > 0) {
        device.parentMac = dto.parentMac;
      }
      if (dto.key !== undefined && dto.key.length > 0) {
        device.key = dto.key;
        device.isBound = true;
      }
      if (dto.ip !== undefined && dto.ip.length > 0 && device.ip.length === 0) {
        device.ip = dto.ip;
      }
      if (dto.homeId !== undefined && dto.homeId.length > 0) {
        device.homeId = dto.homeId;
      }
      device.countryCode = countryCode;
      device.apiBaseUrl = apiBaseUrl;
      if (dto.mqttHost !== undefined && dto.mqttHost.length > 0) {
        device.mqttHost = dto.mqttHost;
      }
      if (dto.mqttPort !== undefined && dto.mqttPort > 0) {
        device.mqttPort = dto.mqttPort;
      }

      if (device.onlineChannel !== GreeOnlineChannel.LAN) {
        device.onlineChannel = dto.online === 1 || device.homeId.length > 0
          ? GreeOnlineChannel.CLOUD
          : GreeOnlineChannel.OFFLINE;
      }

      await StorageUtil.getInstance().upsertDevice(device.toPersistedInfo());
      mergedCount++;
    }

    this.notifyListeners();
    // Immediately probe LAN to upgrade synced cloud devices into LAN direct mode if on same Wi-Fi
    await this.scanLanDevices();
    return mergedCount;
  }

  async upsertLocalDevice(device: GreeDeviceModel): Promise<void> {
    this.devicesByMac.set(device.mac.toLowerCase(), device);
    await StorageUtil.getInstance().upsertDevice(device.toPersistedInfo());
    this.notifyListeners();
  }

  async removeDevice(mac: string): Promise<void> {
    this.devicesByMac.delete(mac.toLowerCase());
    await StorageUtil.getInstance().removeDevice(mac);
    this.notifyListeners();
  }

  private delayMs(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  async destroy(): Promise<void> {
    this.isDestroyed = true;
    if (this.pollTimerId !== -1) {
      clearInterval(this.pollTimerId);
      this.pollTimerId = -1;
    }
    if (this.activeWaiter !== null) {
      clearTimeout(this.activeWaiter.timerId);
      this.activeWaiter.resolve(false);
      this.activeWaiter = null;
    }
    while (this.cmdQueue.length > 0) {
      const pending: PendingCmdItem | undefined = this.cmdQueue.shift();
      if (pending !== undefined) {
        pending.resolve(false);
      }
    }
    await this.closeSocketInternal();
    hilog.info(DOMAIN, TAG, 'GreeLocalService destroyed');
  }
}
