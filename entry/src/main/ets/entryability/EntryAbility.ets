import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { rpc } from '@kit.IPCKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardRefreshUtil } from '../common/utils/CardRefreshUtil';
import { StorageUtil } from '../common/utils/StorageUtil';
import { GreeDeviceModel } from '../model/GreeDeviceModel';
import AcIntentExecutor from '../service/AcIntentExecutor';
import { AcControlViewModel } from '../viewmodel/AcControlViewModel';

const DOMAIN: number = 0x4752;
const TAG: string = 'EntryAbility';

interface CardControlCallPayload {
  action?: string;
  formId?: string;
  mac?: string;
}

class CardCallParcelable implements rpc.Parcelable {
  code: number;

  constructor(code: number = 0) {
    this.code = code;
  }

  marshalling(dataOut: rpc.MessageSequence): boolean {
    try {
      dataOut.writeInt(this.code);
      return true;
    } catch {
      return false;
    }
  }

  unmarshalling(dataIn: rpc.MessageSequence): boolean {
    try {
      this.code = dataIn.readInt();
      return true;
    } catch {
      return false;
    }
  }
}

export default class EntryAbility extends UIAbility {
  private windowStageRef: window.WindowStage | null = null;
  private pendingTargetPage: string = '';
  private pendingTargetMac: string = '';

  private captureRouteFromWant(want: Want): void {
    if (want.parameters === undefined) {
      return;
    }
    const rawParams: Object | undefined = want.parameters['params'];
    if (typeof rawParams === 'string' && rawParams.length > 0) {
      try {
        const parsed: Record<string, Object> = JSON.parse(rawParams) as Record<string, Object>;
        const targetPage: Object | undefined = parsed['targetPage'];
        const mac: Object | undefined = parsed['mac'];
        if (typeof targetPage === 'string') {
          this.pendingTargetPage = targetPage;
        }
        if (typeof mac === 'string') {
          this.pendingTargetMac = mac;
        }
      } catch {
      }
    }
    const directPage: Object | undefined = want.parameters['targetPage'];
    const directMac: Object | undefined = want.parameters['mac'];
    if (typeof directPage === 'string' && directPage.length > 0) {
      this.pendingTargetPage = directPage;
    }
    if (typeof directMac === 'string' && directMac.length > 0) {
      this.pendingTargetMac = directMac;
    }
  }

  private parseCardCallPayload(rawStr: string): CardControlCallPayload {
    const parsedObj: Record<string, Object> = JSON.parse(rawStr) as Record<string, Object>;
    const nestedParams: Object | undefined = parsedObj['params'];
    const source: Record<string, Object> =
      nestedParams !== undefined && nestedParams !== null && typeof nestedParams === 'object'
        ? nestedParams as Record<string, Object>
        : parsedObj;

    const payload: CardControlCallPayload = {};
    const rawAction: Object | undefined = source['action'];
    if (typeof rawAction === 'string') {
      payload.action = rawAction;
    }
    const rawFormId: Object | undefined = source['formId'];
    if (typeof rawFormId === 'string') {
      payload.formId = rawFormId;
    } else if (typeof rawFormId === 'number') {
      payload.formId = String(rawFormId);
    }
    const rawMac: Object | undefined = source['mac'];
    if (typeof rawMac === 'string') {
      payload.mac = rawMac;
    }
    return payload;
  }

  private async handleNextDeviceAction(vm: AcControlViewModel, formId: string, currentMac: string): Promise<void> {
    if (vm.devices.length === 0) {
      return;
    }
    let currentIdx: number = -1;
    if (currentMac.length > 0) {
      for (let i: number = 0; i < vm.devices.length; i++) {
        if (vm.devices[i].mac.toLowerCase() === currentMac.toLowerCase()) {
          currentIdx = i;
          break;
        }
      }
    }
    const nextIdx: number = (currentIdx + 1) % vm.devices.length;
    const nextMac: string = vm.devices[nextIdx].mac;
    if (formId.length > 0) {
      await StorageUtil.getInstance().setFormBoundMac(formId, nextMac);
      await CardRefreshUtil.refreshSingleForm(this.context, formId);
    } else {
      await CardRefreshUtil.bindAllFormsToMac(this.context, nextMac);
    }
  }

  private async handleCardCallAction(payload: CardControlCallPayload): Promise<void> {
    const vm: AcControlViewModel = AcControlViewModel.getInstance();
    await vm.init(this.context);

    const formId: string = payload.formId ?? '';
    let resolvedMac: string = payload.mac ?? '';
    if (resolvedMac.length === 0 && formId.length > 0) {
      resolvedMac = await StorageUtil.getInstance().getFormBoundMac(formId);
    }

    if (payload.action === 'next_device') {
      await this.handleNextDeviceAction(vm, formId, resolvedMac);
      return;
    }

    const target: GreeDeviceModel | null = resolvedMac.length > 0
      ? vm.getDevice(resolvedMac)
      : vm.findDeviceByNameOrFirst();
    if (target === null) {
      hilog.warn(DOMAIN, TAG, 'Card control ignored: no matching device');
      return;
    }

    if (payload.action === 'toggle_power') {
      await vm.togglePower(target.mac);
    } else if (payload.action === 'temp_up') {
      await vm.stepTargetTemperature(target.mac, 1);
    } else if (payload.action === 'temp_down') {
      await vm.stepTargetTemperature(target.mac, -1);
    } else if (payload.action === 'cycle_mode') {
      await vm.cycleMode(target.mac);
    } else if (payload.action === 'cycle_fan') {
      await vm.cycleFanSpeed(target.mac);
    } else if (payload.action === 'toggle_swing') {
      await vm.toggleSwingFull(target.mac);
    }

    if (formId.length > 0) {
      await CardRefreshUtil.refreshSingleForm(this.context, formId);
    }
    await CardRefreshUtil.refreshAllCards(this.context);
  }

  private registerCardCallee(): void {
    try {
      this.callee.on('ac_card_control', (data: rpc.MessageSequence): rpc.Parcelable => {
        try {
          const rawStr: string = data.readString();
          hilog.info(DOMAIN, TAG, 'ac_card_control received: %{public}s', rawStr);
          const parsed: CardControlCallPayload = this.parseCardCallPayload(rawStr);
          this.handleCardCallAction(parsed).catch((err: Object) => {
            hilog.warn(DOMAIN, TAG, 'handleCardCallAction error: %{public}s', String(err));
          });
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'ac_card_control parse error: %{public}s', String(err));
        }
        return new CardCallParcelable(0);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'callee.on failed: %{public}s', String(err));
    }
  }

  private navigateIfPending(): void {
    if (this.pendingTargetPage !== 'pages/DeviceControlPage' || this.windowStageRef === null) {
      return;
    }
    const targetMac: string = this.pendingTargetMac;
    this.pendingTargetPage = '';
    this.pendingTargetMac = '';

    try {
      const mainWin: window.Window = this.windowStageRef.getMainWindowSync();
      mainWin.getUIContext().getRouter().pushUrl({
        url: 'pages/DeviceControlPage',
        params: { mac: targetMac }
      }).catch(() => {});
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'navigateIfPending error: %{public}s', String(err));
    }
  }

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.registerCardCallee();

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setColorMode ignored: %{public}s', String(err));
    }

    this.captureRouteFromWant(want);

    AcControlViewModel.getInstance().init(this.context).then(() => {
      AcIntentExecutor.handleWantIfApplicable(this.context, want).catch(() => {});
    }).catch((err: Object) => {
      hilog.error(DOMAIN, TAG, 'ViewModel init error: %{public}s', String(err));
    });
    hilog.info(DOMAIN, TAG, '%{public}s', 'EntryAbility onCreate');
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.captureRouteFromWant(want);
    AcIntentExecutor.handleWantIfApplicable(this.context, want).catch(() => {});
    this.navigateIfPending();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'EntryAbility onDestroy');
    try {
      this.callee.off('ac_card_control');
    } catch {
    }
    AcControlViewModel.getInstance().destroy().catch((err: Object) => {
      hilog.warn(DOMAIN, TAG, 'ViewModel destroy error: %{public}s', String(err));
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStageRef = windowStage;
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      try {
        const mainWin: window.Window = windowStage.getMainWindowSync();
        mainWin.setWindowSystemBarProperties({
          statusBarContentColor: '#182431',
          navigationBarContentColor: '#182431'
        }).catch(() => {});
      } catch {
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'loadContent succeeded');
      this.navigateIfPending();
    });
  }
}
