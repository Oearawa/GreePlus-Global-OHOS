import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  GreeAcMode,
  GreeFanSpeed,
  GreePowerState,
  GreeSwingUpDown,
  GreeTempUnit,
  MAX_TEMP_C,
  MAX_TEMP_F,
  MIN_TEMP_C,
  MIN_TEMP_F
} from '../common/constants/GreeConstants';
import { AcCardBindingData, CardRefreshUtil } from '../common/utils/CardRefreshUtil';
import { NetworkUtil, WifiSubnetInfo } from '../common/utils/NetworkUtil';
import { StorageUtil } from '../common/utils/StorageUtil';
import { celsiusToFahrenheit, fahrenheitToCelsius, GreeDeviceModel } from '../model/GreeDeviceModel';
import { GreeCloudControlResult, PersistedDeviceInfo } from '../model/GreeProtocolTypes';
import { GreeCloudService } from '../service/GreeCloudService';
import { GreeLocalService } from '../service/GreeLocalService';

const DOMAIN: number = 0x4752;
const TAG: string = 'EntryFormAbility';

interface FormEventPayload {
  action?: string;
  mac?: string;
  formId?: string;
}

interface CommandPair {
  opt: string[];
  p: number[];
}

export default class EntryFormAbility extends FormExtensionAbility {
  private extractFormId(want: Want): string {
    if (want.parameters === undefined) {
      return '';
    }
    const rawId: Object | undefined = want.parameters['ohos.extra.param.key.form_identity'] ??
      want.parameters[formInfo.FormParam.IDENTITY_KEY];
    if (typeof rawId === 'string') {
      return rawId;
    }
    if (typeof rawId === 'number') {
      return String(rawId);
    }
    return '';
  }

  private extractDimension(want: Want): number {
    if (want.parameters === undefined) {
      return 2;
    }
    const rawDim: Object | undefined = want.parameters[formInfo.FormParam.DIMENSION_KEY];
    const dimNum: number = Number(rawDim);
    if (!Number.isNaN(dimNum) && dimNum > 0) {
      return dimNum;
    }
    return 2;
  }

  private parseEventPayload(message: string): FormEventPayload {
    const out: FormEventPayload = {};
    try {
      const parsed: Record<string, Object> = JSON.parse(message) as Record<string, Object>;
      const nested: Object | undefined = parsed['params'];
      const source: Record<string, Object> =
        nested !== undefined && nested !== null && typeof nested === 'object'
          ? nested as Record<string, Object>
          : parsed;
      const rawAction: Object | undefined = source['action'];
      if (typeof rawAction === 'string') {
        out.action = rawAction;
      }
      const rawMac: Object | undefined = source['mac'];
      if (typeof rawMac === 'string') {
        out.mac = rawMac;
      }
      const rawFormId: Object | undefined = source['formId'];
      if (typeof rawFormId === 'string') {
        out.formId = rawFormId;
      } else if (typeof rawFormId === 'number') {
        out.formId = String(rawFormId);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'parseEventPayload error: %{public}s', String(err));
    }
    return out;
  }

  private applyActionToModel(model: GreeDeviceModel, action: string): CommandPair | null {
    if (action === 'toggle_power') {
      const nextPow: number = model.pow === GreePowerState.ON ? GreePowerState.OFF : GreePowerState.ON;
      model.pow = nextPow;
      return { opt: ['Pow'], p: [nextPow] };
    }

    if (action === 'temp_up' || action === 'temp_down') {
      const delta: number = action === 'temp_up' ? 1 : -1;
      if (model.temUn === GreeTempUnit.FAHRENHEIT) {
        const curF: number = celsiusToFahrenheit(model.setTem);
        const nextF: number = Math.min(MAX_TEMP_F, Math.max(MIN_TEMP_F, curF + delta));
        const nextC: number = Math.min(MAX_TEMP_C, Math.max(MIN_TEMP_C, fahrenheitToCelsius(nextF)));
        model.setTem = nextC;
      } else {
        const nextC: number = Math.min(MAX_TEMP_C, Math.max(MIN_TEMP_C, model.setTem + delta));
        model.setTem = nextC;
      }
      return { opt: ['TemUn', 'SetTem'], p: [model.temUn, model.setTem] };
    }

    if (action === 'cycle_mode') {
      const order: GreeAcMode[] = [
        GreeAcMode.COOL,
        GreeAcMode.HEAT,
        GreeAcMode.DRY,
        GreeAcMode.FAN,
        GreeAcMode.AUTO
      ];
      const idx: number = order.indexOf(model.mod as GreeAcMode);
      const nextMode: GreeAcMode = order[(idx + 1) % order.length];
      if (model.pow === GreePowerState.OFF) {
        model.pow = GreePowerState.ON;
        model.mod = nextMode;
        return { opt: ['Pow', 'Mod'], p: [GreePowerState.ON, nextMode] };
      }
      model.mod = nextMode;
      return { opt: ['Mod'], p: [nextMode] };
    }

    if (action === 'cycle_fan') {
      let nextSpeed: GreeFanSpeed = GreeFanSpeed.LOW;
      if (model.wdSpd === GreeFanSpeed.LOW) {
        nextSpeed = GreeFanSpeed.MEDIUM;
      } else if (model.wdSpd === GreeFanSpeed.MEDIUM_LOW || model.wdSpd === GreeFanSpeed.MEDIUM) {
        nextSpeed = GreeFanSpeed.HIGH;
      } else if (model.wdSpd === GreeFanSpeed.MEDIUM_HIGH || model.wdSpd === GreeFanSpeed.HIGH) {
        nextSpeed = GreeFanSpeed.AUTO;
      } else {
        nextSpeed = GreeFanSpeed.LOW;
      }
      model.wdSpd = nextSpeed;
      model.quiet = 0;
      model.tur = 0;
      return { opt: ['WdSpd', 'Quiet', 'Tur'], p: [nextSpeed, 0, 0] };
    }

    if (action === 'toggle_swing') {
      const nextSwing: number = model.swUpDn === GreeSwingUpDown.FULL
        ? GreeSwingUpDown.DEFAULT
        : GreeSwingUpDown.FULL;
      model.swUpDn = nextSwing;
      return { opt: ['SwUpDn'], p: [nextSwing] };
    }

    return null;
  }

  private async dispatchHardwareCommand(
    model: GreeDeviceModel,
    cmd: CommandPair
  ): Promise<boolean> {
    let lanOk: boolean = false;
    try {
      const wifiInfo: WifiSubnetInfo = NetworkUtil.getWifiSubnetInfo();
      if (wifiInfo.localIp.length > 0 && model.ip.length > 0 && model.key.length > 0) {
        await GreeLocalService.getInstance().init();
        lanOk = await GreeLocalService.getInstance().sendCommand(model, cmd.opt, cmd.p);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'LAN sendCommand error: %{public}s', String(err));
    }

    if (lanOk) {
      return true;
    }

    try {
      const session = await StorageUtil.getInstance().loadCloudSession();
      if (model.homeId.length > 0 || session !== null) {
        const cloudRes: GreeCloudControlResult = await GreeCloudService.getInstance().sendRemoteCommand(
          model,
          cmd.opt,
          cmd.p
        );
        return cloudRes.success;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Cloud sendRemoteCommand error: %{public}s', String(err));
    }
    return false;
  }

  private async handleFormEventAsync(formId: string, message: string): Promise<void> {
    hilog.info(DOMAIN, TAG, 'onFormEvent formId=%{public}s msg=%{public}s', formId, message);
    const payload: FormEventPayload = this.parseEventPayload(message);
    const action: string = payload.action ?? '';
    if (action.length === 0) {
      return;
    }

    const storage: StorageUtil = StorageUtil.getInstance();
    await storage.reloadFromDisk(this.context);
    await storage.addFormId(formId);

    const devices: PersistedDeviceInfo[] = await storage.loadDevices();
    if (devices.length === 0) {
      await CardRefreshUtil.refreshSingleForm(this.context, formId, devices);
      return;
    }

    let boundMac: string = await storage.getFormBoundMac(formId);
    if (boundMac.length === 0 && payload.mac !== undefined && payload.mac.length > 0) {
      boundMac = payload.mac;
    }

    if (action === 'next_device') {
      let curIdx: number = -1;
      for (let i: number = 0; i < devices.length; i++) {
        if (devices[i].mac.toLowerCase() === boundMac.toLowerCase()) {
          curIdx = i;
          break;
        }
      }
      const nextIdx: number = (curIdx + 1) % devices.length;
      const nextMac: string = devices[nextIdx].mac;
      await storage.setFormBoundMac(formId, nextMac);
      await CardRefreshUtil.refreshSingleForm(this.context, formId, devices);
      return;
    }

    let chosen: PersistedDeviceInfo = devices[0];
    if (boundMac.length > 0) {
      for (let i: number = 0; i < devices.length; i++) {
        if (devices[i].mac.toLowerCase() === boundMac.toLowerCase()) {
          chosen = devices[i];
          break;
        }
      }
    }
    await storage.setFormBoundMac(formId, chosen.mac);

    const model: GreeDeviceModel = GreeDeviceModel.fromPersistedInfo(chosen);
    const cmd: CommandPair | null = this.applyActionToModel(model, action);
    if (cmd === null) {
      return;
    }

    // 1. 先乐观持久化并立即刷新桌面卡片，确保零延迟视觉反馈
    await storage.upsertDevice(model.toPersistedInfo());
    const optimisticDevices: PersistedDeviceInfo[] = await storage.loadDevices();
    await CardRefreshUtil.refreshSingleForm(this.context, formId, optimisticDevices);
    await CardRefreshUtil.refreshAllCards(this.context, optimisticDevices);

    // 2. 后台下发真实硬件指令（局域网 UDP 7000 / 海外云端双模）
    const ok: boolean = await this.dispatchHardwareCommand(model, cmd);
    if (ok) {
      await storage.upsertDevice(model.toPersistedInfo());
      const syncedDevices: PersistedDeviceInfo[] = await storage.loadDevices();
      await CardRefreshUtil.refreshAllCards(this.context, syncedDevices);
    }
  }

  private async syncFormData(formId: string, dimensionHint: number): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    try {
      const storage: StorageUtil = StorageUtil.getInstance();
      await storage.reloadFromDisk(this.context);
      await storage.addFormId(formId);

      let effectiveDim: number = dimensionHint;
      if (effectiveDim > 0) {
        await storage.setFormDimension(formId, effectiveDim);
      } else {
        effectiveDim = await storage.getFormDimension(formId);
      }

      const devices: PersistedDeviceInfo[] = await storage.loadDevices();
      const boundMac: string = await storage.assignNextAvailableMacForForm(formId, devices);
      const cardData: AcCardBindingData = CardRefreshUtil.buildCardBindingData(devices, effectiveDim, boundMac, formId);
      const binding: formBindingData.FormBindingData = formBindingData.createFormBindingData(cardData);
      await formProvider.updateForm(formId, binding);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'syncFormData error formId=%{public}s: %{public}s', formId, String(err));
    }
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId: string = this.extractFormId(want);
    const dimension: number = this.extractDimension(want);
    this.syncFormData(formId, dimension).catch(() => {});
    const initialData: AcCardBindingData = CardRefreshUtil.buildCardBindingData([], dimension, undefined, formId);
    return formBindingData.createFormBindingData(initialData);
  }

  onCastToNormalForm(formId: string): void {
    this.syncFormData(formId, 0).catch(() => {});
  }

  onUpdateForm(formId: string): void {
    this.syncFormData(formId, 0).catch(() => {});
  }

  onFormEvent(formId: string, message: string): void {
    this.handleFormEventAsync(formId, message).catch((err: Object) => {
      hilog.warn(DOMAIN, TAG, 'handleFormEventAsync error: %{public}s', String(err));
    });
  }

  onRemoveForm(formId: string): void {
    this.removeFormRecord(formId).catch(() => {});
  }

  private async removeFormRecord(formId: string): Promise<void> {
    const storage: StorageUtil = StorageUtil.getInstance();
    await storage.reloadFromDisk(this.context);
    await storage.removeFormId(formId);
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
