import { wifiManager } from '@kit.ConnectivityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GREE_GLOBAL_BROADCAST } from '../constants/GreeConstants';

const DOMAIN: number = 0x4752;
const TAG: string = 'NetworkUtil';

export interface WifiSubnetInfo {
  localIp: string;
  netmask: string;
  subnetBroadcast: string;
}

/**
 * Wi-Fi IPv4 and directed subnet broadcast calculator.
 */
export class NetworkUtil {
  /**
   * Converts a 32-bit integer from HarmonyOS wifiManager IpInfo into dotted IPv4 string.
   * HarmonyOS wifiManager stores IPv4 in network/big-endian or host order depending on platform;
   * standard OpenHarmony WifiIpInfo uses big-endian (MSB = first octet).
   */
  static intToIpv4(ipInt: number): string {
    if (ipInt === 0) {
      return '';
    }
    const b1: number = (ipInt >>> 24) & 0xff;
    const b2: number = (ipInt >>> 16) & 0xff;
    const b3: number = (ipInt >>> 8) & 0xff;
    const b4: number = ipInt & 0xff;
    return `${b1}.${b2}.${b3}.${b4}`;
  }

  /**
   * Computes directed broadcast address from 32-bit IPv4 and netmask integers.
   */
  static computeDirectedBroadcastInt(ipInt: number, netmaskInt: number): number {
    const unsignedIp: number = ipInt >>> 0;
    let effectiveMask: number = netmaskInt >>> 0;
    if (effectiveMask === 0 || effectiveMask === 0xffffffff) {
      // Fallback to /24 mask when simulator/device omits netmask
      effectiveMask = 0xffffff00;
    }
    const invertedMask: number = (~effectiveMask) >>> 0;
    return (unsignedIp | invertedMask) >>> 0;
  }

  static getWifiSubnetInfo(): WifiSubnetInfo {
    try {
      const ipInfo: wifiManager.IpInfo = wifiManager.getIpInfo();
      const ipInt: number = ipInfo.ipAddress >>> 0;
      if (ipInt === 0) {
        return {
          localIp: '',
          netmask: '',
          subnetBroadcast: ''
        };
      }
      const localIp: string = NetworkUtil.intToIpv4(ipInt);
      const maskInt: number = ipInfo.netmask >>> 0;
      const netmask: string = maskInt !== 0 ? NetworkUtil.intToIpv4(maskInt) : '255.255.255.0';
      const broadcastInt: number = NetworkUtil.computeDirectedBroadcastInt(ipInt, maskInt);
      const subnetBroadcast: string = NetworkUtil.intToIpv4(broadcastInt);
      return {
        localIp: localIp,
        netmask: netmask,
        subnetBroadcast: subnetBroadcast
      };
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'wifiManager.getIpInfo unavailable: %{public}s', String(err));
      return {
        localIp: '',
        netmask: '',
        subnetBroadcast: ''
      };
    }
  }

  /**
   * Returns deduplicated discovery broadcast targets:
   * global 255.255.255.255 plus directed subnet broadcast (e.g. 192.168.1.255).
   */
  static getDiscoveryBroadcastTargets(): string[] {
    const targets: string[] = [GREE_GLOBAL_BROADCAST];
    const info: WifiSubnetInfo = NetworkUtil.getWifiSubnetInfo();
    if (info.subnetBroadcast.length > 0 && info.subnetBroadcast !== GREE_GLOBAL_BROADCAST) {
      targets.push(info.subnetBroadcast);
    }
    return targets;
  }

  static isValidIpv4(ip: string): boolean {
    const trimmed: string = ip.trim();
    const parts: string[] = trimmed.split('.');
    if (parts.length !== 4) {
      return false;
    }
    for (let i: number = 0; i < parts.length; i++) {
      const seg: string = parts[i];
      if (seg.length === 0 || seg.length > 3) {
        return false;
      }
      for (let j: number = 0; j < seg.length; j++) {
        const ch: number = seg.charCodeAt(j);
        if (ch < 48 || ch > 57) {
          return false;
        }
      }
      const val: number = Number(seg);
      if (Number.isNaN(val) || val < 0 || val > 255) {
        return false;
      }
    }
    return true;
  }
}
