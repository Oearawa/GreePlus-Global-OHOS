import { common, insightIntent, InsightIntentExecutor, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GreeAcMode, GreePowerState } from '../common/constants/GreeConstants';
import { CardRefreshUtil } from '../common/utils/CardRefreshUtil';
import { GreeDeviceModel } from '../model/GreeDeviceModel';
import { AcControlViewModel } from '../viewmodel/AcControlViewModel';

const DOMAIN: number = 0x4752;
const TAG: string = 'AcIntentExecutor';

export interface AcControlIntentParams {
  deviceName?: string;
  power?: string;
  temperature?: number;
  mode?: string;
}

function parseModeString(rawMode: string): GreeAcMode | null {
  const normalized: string = rawMode.trim().toLowerCase();
  switch (normalized) {
    case 'auto':
    case '自动':
      return GreeAcMode.AUTO;
    case 'cool':
    case '制冷':
      return GreeAcMode.COOL;
    case 'dry':
    case '除湿':
      return GreeAcMode.DRY;
    case 'fan':
    case '送风':
      return GreeAcMode.FAN;
    case 'heat':
    case '制热':
      return GreeAcMode.HEAT;
    default:
      return null;
  }
}

export default class AcIntentExecutor extends InsightIntentExecutor {
  static parseUriParams(uri: string): AcControlIntentParams | null {
    const cleanUri: string = uri.trim();
    if (!cleanUri.toLowerCase().startsWith('greeplus://')) {
      return null;
    }
    const qIndex: number = cleanUri.indexOf('?');
    if (qIndex < 0) {
      return {};
    }
    const query: string = cleanUri.slice(qIndex + 1);
    const pairs: string[] = query.split('&');
    const parsed: AcControlIntentParams = {};

    for (let i: number = 0; i < pairs.length; i++) {
      const pair: string = pairs[i];
      if (pair.length === 0) {
        continue;
      }
      const eqIdx: number = pair.indexOf('=');
      if (eqIdx < 0) {
        continue;
      }
      let key: string = pair.slice(0, eqIdx).trim().toLowerCase();
      let val: string = pair.slice(eqIdx + 1).trim();
      try {
        key = decodeURIComponent(key);
        val = decodeURIComponent(val);
      } catch {
      }
      if (key === 'devicename' || key === 'device') {
        parsed.deviceName = val;
      } else if (key === 'power') {
        parsed.power = val.toLowerCase();
      } else if (key === 'temp' || key === 'temperature') {
        const numVal: number = Number(val);
        if (!Number.isNaN(numVal)) {
          parsed.temperature = Math.round(numVal);
        }
      } else if (key === 'mode') {
        parsed.mode = val.toLowerCase();
      }
    }
    return parsed;
  }

  static extractFromRecord(record: Record<string, Object>): AcControlIntentParams {
    const out: AcControlIntentParams = {};
    const rawName: Object | undefined = record['deviceName'];
    if (typeof rawName === 'string' && rawName.trim().length > 0) {
      out.deviceName = rawName.trim();
    }
    const rawPower: Object | undefined = record['power'];
    if (typeof rawPower === 'string' && rawPower.trim().length > 0) {
      out.power = rawPower.trim().toLowerCase();
    }
    const rawTemp: Object | undefined = record['temperature'] ?? record['temp'];
    if (typeof rawTemp === 'number' && !Number.isNaN(rawTemp)) {
      out.temperature = Math.round(rawTemp);
    } else if (typeof rawTemp === 'string' && rawTemp.trim().length > 0) {
      const parsedNum: number = Number(rawTemp.trim());
      if (!Number.isNaN(parsedNum)) {
        out.temperature = Math.round(parsedNum);
      }
    }
    const rawMode: Object | undefined = record['mode'];
    if (typeof rawMode === 'string' && rawMode.trim().length > 0) {
      out.mode = rawMode.trim().toLowerCase();
    }
    return out;
  }

  static async executeControlParams(
    context: common.Context | null,
    params: AcControlIntentParams
  ): Promise<boolean> {
    const vm: AcControlViewModel = AcControlViewModel.getInstance();
    if (context !== null) {
      await vm.init(context);
    } else {
      await vm.init();
    }

    const targetDevice: GreeDeviceModel | null = vm.findDeviceByNameOrFirst(params.deviceName);
    if (targetDevice === null) {
      hilog.warn(DOMAIN, TAG, 'executeControlParams: no device available');
      return false;
    }

    let executed: boolean = false;
    if (params.power === 'on') {
      if (targetDevice.pow !== GreePowerState.ON) {
        await vm.togglePower(targetDevice.mac);
      }
      executed = true;
    } else if (params.power === 'off') {
      if (targetDevice.pow !== GreePowerState.OFF) {
        await vm.togglePower(targetDevice.mac);
      }
      executed = true;
    }

    if (params.mode !== undefined) {
      const mappedMode: GreeAcMode | null = parseModeString(params.mode);
      if (mappedMode !== null) {
        await vm.setMode(targetDevice.mac, mappedMode);
        executed = true;
      }
    }

    if (params.temperature !== undefined) {
      const delta: number = params.temperature - targetDevice.getDisplayTargetTemp();
      if (delta !== 0) {
        await vm.stepTargetTemperature(targetDevice.mac, delta);
      }
      executed = true;
    }

    const cardContext: common.Context | null = context !== null ? context : vm.getAppContext();
    if (executed && cardContext !== null) {
      await CardRefreshUtil.refreshAllCards(cardContext);
    }
    return executed;
  }

  static async handleWantIfApplicable(context: common.Context, want: Want): Promise<boolean> {
    if (typeof want.uri === 'string' && want.uri.toLowerCase().startsWith('greeplus://')) {
      const uriParams: AcControlIntentParams | null = AcIntentExecutor.parseUriParams(want.uri);
      if (uriParams !== null) {
        return await AcIntentExecutor.executeControlParams(context, uriParams);
      }
    }
    return false;
  }

  async onExecuteInUIAbilityBackgroundMode(
    name: string,
    param: Record<string, Object>
  ): Promise<insightIntent.ExecuteResult> {
    hilog.info(DOMAIN, TAG, 'Execute background intent: %{public}s', name);
    const parsed: AcControlIntentParams = AcIntentExecutor.extractFromRecord(param);
    const appCtx: common.Context | null = AcControlViewModel.getInstance().getAppContext();
    const ok: boolean = await AcIntentExecutor.executeControlParams(appCtx, parsed);
    return {
      code: ok ? 0 : -1
    };
  }

  async onExecuteInUIAbilityForegroundMode(
    name: string,
    param: Record<string, Object>,
    pageLoader: window.WindowStage
  ): Promise<insightIntent.ExecuteResult> {
    hilog.info(DOMAIN, TAG, 'Execute foreground intent: %{public}s', name);
    const parsed: AcControlIntentParams = AcIntentExecutor.extractFromRecord(param);
    const appCtx: common.Context | null = AcControlViewModel.getInstance().getAppContext();
    const ok: boolean = await AcIntentExecutor.executeControlParams(appCtx, parsed);
    try {
      await pageLoader.loadContent('pages/Index');
    } catch {
    }
    return {
      code: ok ? 0 : -1
    };
  }
}
