import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  GreeAcMode,
  GreeFanSpeed,
  GreePowerState,
  GreeSwingUpDown
} from '../constants/GreeConstants';
import { AcModeThemePalette, getAcModeTheme } from '../theme/AcThemeHelper';
import { GreeDeviceModel } from '../../model/GreeDeviceModel';
import { PersistedDeviceInfo } from '../../model/GreeProtocolTypes';
import { StorageUtil } from './StorageUtil';

const DOMAIN: number = 0x4752;
const TAG: string = 'CardRefreshUtil';

export interface AcCardBindingData {
  formId: string;
  hasDevice: boolean;
  deviceCount: number;
  mac: string;
  name: string;
  isOn: boolean;
  mode: number;
  modeText: string;
  fanText: string;
  swingOn: boolean;
  swingText: string;
  setTempText: string;
  indoorTempText: string;
  unitSymbol: string;
  primaryColor: string;
  softBgColor: string;
  dimension: number;
}

function formatCardModeText(isOn: boolean, mod: number): string {
  if (!isOn) {
    return '已关机';
  }
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

function formatCardFanText(wdSpd: number): string {
  switch (wdSpd) {
    case GreeFanSpeed.LOW:
      return '低风';
    case GreeFanSpeed.MEDIUM_LOW:
    case GreeFanSpeed.MEDIUM:
      return '中风';
    case GreeFanSpeed.MEDIUM_HIGH:
    case GreeFanSpeed.HIGH:
      return '高风';
    default:
      return '自动';
  }
}

export class CardRefreshUtil {
  static buildCardBindingData(
    devices: PersistedDeviceInfo[],
    dimension: number = 2,
    targetMac?: string,
    formId: string = ''
  ): AcCardBindingData {
    if (devices.length === 0) {
      return {
        formId: formId,
        hasDevice: false,
        deviceCount: 0,
        mac: '',
        name: '格力空调',
        isOn: false,
        mode: GreeAcMode.COOL,
        modeText: '未添加设备',
        fanText: '自动',
        swingOn: false,
        swingText: '定格',
        setTempText: '--',
        indoorTempText: '--',
        unitSymbol: '°C',
        primaryColor: '#8A94A6',
        softBgColor: '#F1F3F5',
        dimension: dimension
      };
    }

    let chosen: PersistedDeviceInfo = devices[0];
    if (targetMac !== undefined && targetMac.length > 0) {
      for (let i: number = 0; i < devices.length; i++) {
        if (devices[i].mac.toLowerCase() === targetMac.toLowerCase()) {
          chosen = devices[i];
          break;
        }
      }
    }

    const model: GreeDeviceModel = GreeDeviceModel.fromPersistedInfo(chosen);
    const isOn: boolean = model.pow === GreePowerState.ON;
    const theme: AcModeThemePalette = getAcModeTheme(model.pow, model.mod);
    const unitSymbol: string = model.getTempUnitSymbol();
    const swingOn: boolean = model.swUpDn === GreeSwingUpDown.FULL;

    return {
      formId: formId,
      hasDevice: true,
      deviceCount: devices.length,
      mac: model.mac,
      name: model.name,
      isOn: isOn,
      mode: model.mod,
      modeText: formatCardModeText(isOn, model.mod),
      fanText: formatCardFanText(model.wdSpd),
      swingOn: swingOn,
      swingText: swingOn ? '扫风' : '定格',
      setTempText: `${model.getDisplayTargetTemp()}`,
      indoorTempText: `${model.getDisplayIndoorTemp()}`,
      unitSymbol: unitSymbol,
      primaryColor: theme.primaryColor,
      softBgColor: theme.softBgColor,
      dimension: dimension
    };
  }

  static async refreshSingleForm(
    context: common.Context,
    formId: string,
    devicesOverride?: PersistedDeviceInfo[]
  ): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    try {
      const storage: StorageUtil = StorageUtil.getInstance();
      await storage.init(context);
      const devices: PersistedDeviceInfo[] = devicesOverride !== undefined
        ? devicesOverride
        : await storage.loadDevices();
      const dim: number = await storage.getFormDimension(formId);
      let boundMac: string = await storage.getFormBoundMac(formId);
      if (boundMac.length === 0 && devices.length > 0) {
        boundMac = await storage.assignNextAvailableMacForForm(formId, devices);
      }

      const cardData: AcCardBindingData = CardRefreshUtil.buildCardBindingData(devices, dim, boundMac, formId);
      const bindingData: formBindingData.FormBindingData = formBindingData.createFormBindingData(cardData);
      try {
        await formProvider.updateForm(formId, bindingData);
      } catch (err) {
        const bizErr: BusinessError = err as BusinessError;
        hilog.warn(DOMAIN, TAG, 'updateForm failed formId=%{public}s code=%{public}d',
          formId, bizErr?.code ?? -1);
        if (bizErr?.code === 16501001) {
          await storage.removeFormId(formId);
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'refreshSingleForm error: %{public}s', String(err));
    }
  }

  static async refreshAllCards(
    context: common.Context,
    devicesOverride?: PersistedDeviceInfo[]
  ): Promise<void> {
    try {
      const storage: StorageUtil = StorageUtil.getInstance();
      await storage.init(context);
      const formIds: string[] = await storage.loadFormIds();
      if (formIds.length === 0) {
        return;
      }

      const devices: PersistedDeviceInfo[] = devicesOverride !== undefined
        ? devicesOverride
        : await storage.loadDevices();
      const map: Record<string, string> = await storage.loadFormDeviceMap();

      for (let i: number = 0; i < formIds.length; i++) {
        const formId: string = formIds[i];
        const dim: number = await storage.getFormDimension(formId);
        let targetMac: string = typeof map[formId] === 'string' ? map[formId] : '';
        if (targetMac.length === 0 && devices.length > 0) {
          targetMac = await storage.assignNextAvailableMacForForm(formId, devices);
        }
        const cardData: AcCardBindingData = CardRefreshUtil.buildCardBindingData(devices, dim, targetMac, formId);
        const bindingData: formBindingData.FormBindingData = formBindingData.createFormBindingData(cardData);
        try {
          await formProvider.updateForm(formId, bindingData);
        } catch (err) {
          const bizErr: BusinessError = err as BusinessError;
          hilog.warn(DOMAIN, TAG, 'updateForm failed formId=%{public}s code=%{public}d',
            formId, bizErr?.code ?? -1);
          if (bizErr?.code === 16501001) {
            await storage.removeFormId(formId);
          }
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'refreshAllCards error: %{public}s', String(err));
    }
  }

  static async bindAllFormsToMac(context: common.Context, mac: string): Promise<void> {
    if (mac.length === 0) {
      return;
    }
    try {
      const storage: StorageUtil = StorageUtil.getInstance();
      await storage.init(context);
      await storage.saveLastSelectedMac(mac);
      const formIds: string[] = await storage.loadFormIds();
      for (let i: number = 0; i < formIds.length; i++) {
        await storage.setFormBoundMac(formIds[i], mac);
      }
      await CardRefreshUtil.refreshAllCards(context);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'bindAllFormsToMac error: %{public}s', String(err));
    }
  }
}
