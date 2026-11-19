import {
  GreeAcMode,
  GreeFanSpeed,
  GreeOnlineChannel,
  GreePowerState
} from '../common/constants/GreeConstants';
import {
  AcModeThemePalette,
  formatControlNavChannelText,
  getAcModeTheme,
  getChannelDotColor
} from '../common/theme/AcThemeHelper';
import { HapticUtil } from '../common/utils/HapticUtil';
import { TempDialControl } from '../components/TempDialControl';
import { GreeDeviceModel } from '../model/GreeDeviceModel';
import { AcControlViewModel } from '../viewmodel/AcControlViewModel';
import { DeviceControlRouteParams } from './Index';

interface FeatureGridItem {
  col: string;
  title: string;
  symbol: Resource;
}

interface SwingOption {
  level: number;
  label: string;
}

const SWING_OPTIONS: SwingOption[] = [
  { level: 0, label: '关闭' },
  { level: 1, label: '全扫' },
  { level: 2, label: '1' },
  { level: 3, label: '2' },
  { level: 4, label: '3' },
  { level: 5, label: '4' },
  { level: 6, label: '5' }
];

const FEATURE_GRID_ITEMS: FeatureGridItem[] = [
  { col: 'Lig', title: '灯光', symbol: $r('sys.symbol.lightbulb') },
  { col: 'SwhSlp', title: '睡眠', symbol: $r('sys.symbol.moon_fill') },
  { col: 'Tur', title: '强劲', symbol: $r('sys.symbol.bolt_1') },
  { col: 'Quiet', title: '静音', symbol: $r('sys.symbol.speaker_slash') },
  { col: 'StHt', title: '辅热', symbol: $r('sys.symbol.flame_fill') },
  { col: 'Health', title: '健康', symbol: $r('sys.symbol.leaf_fill') },
  { col: 'Blo', title: '干燥', symbol: $r('sys.symbol.sun_max') },
  { col: 'Air', title: '换气', symbol: $r('sys.symbol.wind') }
];

@Entry
@ComponentV2
struct DeviceControlPage {
  private readonly vm: AcControlViewModel = AcControlViewModel.getInstance();
  @Local private targetMac: string = '';
  @Local private showDeviceInfoModal: boolean = false;
  @Local private showRenameModal: boolean = false;
  @Local private showDeleteConfirmModal: boolean = false;
  @Local private renameInput: string = '';

  aboutToAppear(): void {
    const rawParams: Object = this.getUIContext().getRouter().getParams();
    if (rawParams !== undefined && rawParams !== null) {
      const typedParams: DeviceControlRouteParams = rawParams as DeviceControlRouteParams;
      if (typeof typedParams.mac === 'string' && typedParams.mac.length > 0) {
        this.targetMac = typedParams.mac;
        return;
      }
    }
    this.targetMac = this.vm.selectedMac;
  }

  private getCurrentDevice(): GreeDeviceModel | null {
    if (this.targetMac.length > 0) {
      return this.vm.getDevice(this.targetMac);
    }
    return this.vm.getSelectedDevice();
  }

  private getTheme(): AcModeThemePalette {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    if (dev !== null) {
      return getAcModeTheme(dev.pow, dev.mod);
    }
    return getAcModeTheme(GreePowerState.OFF, GreeAcMode.COOL);
  }

  private isDeviceOn(): boolean {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    return dev !== null && dev.pow === GreePowerState.ON;
  }

  private isDeviceOffline(): boolean {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    return dev !== null && dev.onlineChannel === GreeOnlineChannel.OFFLINE;
  }

  private getDeviceName(): string {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    return dev !== null ? dev.name : '空调控制';
  }

  private getDeviceChannel(): GreeOnlineChannel {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    return dev !== null ? dev.onlineChannel : GreeOnlineChannel.OFFLINE;
  }

  private isFeatureTileActive(device: GreeDeviceModel, col: string): boolean {
    switch (col) {
      case 'Lig':
        return device.lig === 1;
      case 'SwhSlp':
        return device.swhSlp === 1;
      case 'Tur':
        return device.tur === 1;
      case 'Quiet':
        return device.quiet === 1;
      case 'StHt':
        return device.stHt === 1;
      case 'Health':
        return device.health === 1;
      case 'Blo':
        return device.blo === 1;
      case 'Air':
        return device.air === 1;
      default:
        return false;
    }
  }

  private getSwUpDnLevel(): number {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    return dev !== null ? dev.swUpDn : 0;
  }

  private getSwingLfRigLevel(): number {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    return dev !== null ? dev.swingLfRig : 0;
  }

  private formatSwingStatusText(level: number): string {
    if (level === 1) {
      return '全扫';
    }
    if (level >= 2 && level <= 6) {
      return `定格 ${level - 1}档`;
    }
    return '关闭';
  }

  private handleSelectSwUpDn(level: number): void {
    HapticUtil.tick();
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    if (dev !== null) {
      this.vm.setSwingUpDown(dev, level);
    }
  }

  private handleSelectSwingLfRig(level: number): void {
    HapticUtil.tick();
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    if (dev !== null) {
      this.vm.setSwingLfRig(dev, level);
    }
  }

  private isCurrentTileActive(col: string): boolean {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    return dev !== null && this.isFeatureTileActive(dev, col);
  }

  private handleFeatureTileClick(device: GreeDeviceModel, col: string): void {
    HapticUtil.tick();
    this.vm.toggleFeature(device.mac, col);
  }

  private handleCurrentTileClick(col: string): void {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    if (dev !== null) {
      this.handleFeatureTileClick(dev, col);
    }
  }

  private getCurrentMoreMenuItems(): MenuElement[] {
    return [
      {
        value: '刷新状态',
        action: () => {
          const dev: GreeDeviceModel | null = this.getCurrentDevice();
          if (dev !== null) {
            this.vm.refreshSingleDevice(dev.mac);
          }
        }
      },
      {
        value: '重命名设备',
        action: () => {
          const dev: GreeDeviceModel | null = this.getCurrentDevice();
          if (dev !== null) {
            this.renameInput = dev.name;
            this.showRenameModal = true;
          }
        }
      },
      {
        value: '同步到桌面卡片',
        action: () => {
          const dev: GreeDeviceModel | null = this.getCurrentDevice();
          if (dev !== null) {
            this.vm.bindDeviceToCards(dev.mac).then(() => {
              try {
                this.getUIContext().getPromptAction().showToast({
                  message: `已将「${dev.name}」同步到桌面卡片`,
                  duration: 1800
                });
              } catch {
              }
            }).catch(() => {});
          }
        }
      },
      {
        value: '设备信息',
        action: () => {
          if (this.getCurrentDevice() !== null) {
            this.showDeviceInfoModal = true;
          }
        }
      },
      {
        value: '移除设备',
        action: () => {
          if (this.getCurrentDevice() !== null) {
            this.showDeleteConfirmModal = true;
          }
        }
      }
    ];
  }

  private getDeviceModelText(): string {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    if (dev === null) {
      return '格力空调';
    }
    const joined: string = `${dev.brand} ${dev.model}`.trim();
    return joined.length > 0 ? joined : '格力空调';
  }

  private getDeviceMacText(): string {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    return dev !== null ? dev.mac : '--';
  }

  private getDeviceIpText(): string {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    if (dev !== null && dev.ip.length > 0) {
      return dev.ip;
    }
    return '未连接局域网';
  }

  private getDeviceVerText(): string {
    const dev: GreeDeviceModel | null = this.getCurrentDevice();
    if (dev !== null && dev.ver.length > 0) {
      return dev.ver;
    }
    return '--';
  }

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#666666')
      Blank()
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#182431')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '62%' })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 0 }) {
        // 顶部导航栏
        Row({ space: 12 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(20)
              .fontColor(['#182431'])
          }
          .width(40)
          .height(40)
          .backgroundColor('#B3FFFFFF')
          .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 })
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })

          Column({ space: 3 }) {
            Text(this.getDeviceName())
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#182431')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (this.getCurrentDevice() !== null) {
              Row({ space: 6 }) {
                Circle()
                  .width(6)
                  .height(6)
                  .fill(getChannelDotColor(this.getDeviceChannel()))
                Text(formatControlNavChannelText(this.getDeviceChannel()))
                  .fontSize(12)
                  .fontColor('#666666')
              }
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          if (this.getCurrentDevice() !== null) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.more'))
                .fontSize(20)
                .fontColor(['#182431'])
            }
            .width(40)
            .height(40)
            .backgroundColor('#B3FFFFFF')
            .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 })
            .bindMenu(this.getCurrentMoreMenuItems())
          } else {
            Blank()
              .width(40)
              .height(40)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })

        if (this.getCurrentDevice() === null) {
          Column({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(42)
              .fontColor(['#9AA3B2'])
            Text('未找到该设备或设备已被移除')
              .fontSize(15)
              .fontColor('#666666')
            Button('返回设备列表', { type: ButtonType.Capsule })
              .height(40)
              .backgroundColor('#0A59F7')
              .fontColor('#FFFFFF')
              .fontSize(14)
              .padding({ left: 22, right: 22 })
              .onClick(() => {
                this.getUIContext().getRouter().back();
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              if (this.isDeviceOffline()) {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.info_circle'))
                    .fontSize(16)
                    .fontColor(['#FA6400'])
                  Text('设备当前离线，请检查空调供电或无线网络连接')
                    .fontSize(12)
                    .fontColor('#B85000')
                    .layoutWeight(1)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .backgroundColor('#FFF5EC')
                .borderRadius(14)
              } else if (this.vm.statusBanner.length > 0) {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.info_circle'))
                    .fontSize(15)
                    .fontColor(['#E84026'])
                  Text(this.vm.statusBanner)
                    .fontSize(12)
                    .fontColor('#C42E1B')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .backgroundColor('#FFF0EE')
                .borderRadius(14)
              }

              // 核心温度、模式与风速控制区
              TempDialControl({
                device: this.getCurrentDevice() as GreeDeviceModel,
                onTogglePower: () => {
                  const dev: GreeDeviceModel | null = this.getCurrentDevice();
                  if (dev !== null) {
                    this.vm.togglePower(dev.mac);
                  }
                },
                onStepTemp: (delta: number) => {
                  const dev: GreeDeviceModel | null = this.getCurrentDevice();
                  if (dev !== null) {
                    this.vm.stepTargetTemperature(dev.mac, delta);
                  }
                },
                onSetTemp: (targetDisplayTemp: number) => {
                  const dev: GreeDeviceModel | null = this.getCurrentDevice();
                  if (dev !== null) {
                    this.vm.setTargetTemperatureDebounced(dev.mac, targetDisplayTemp);
                  }
                },
                onToggleUnit: () => {
                  const dev: GreeDeviceModel | null = this.getCurrentDevice();
                  if (dev !== null) {
                    this.vm.toggleTempUnit(dev.mac);
                  }
                },
                onSelectMode: (mode: GreeAcMode) => {
                  const dev: GreeDeviceModel | null = this.getCurrentDevice();
                  if (dev !== null) {
                    this.vm.setMode(dev.mac, mode);
                  }
                },
                onSelectFanSpeed: (speed: GreeFanSpeed) => {
                  const dev: GreeDeviceModel | null = this.getCurrentDevice();
                  if (dev !== null) {
                    this.vm.setFanSpeed(dev.mac, speed);
                  }
                }
              })

              // 独立风向调节卡片（上下风向 + 左右风向 7 档调节）
              Column({ space: 14 }) {
                // 上下风向
                Column({ space: 10 }) {
                  Row() {
                    Text('上下风向')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#182431')
                    Blank()
                    Text(this.isDeviceOn() ? this.formatSwingStatusText(this.getSwUpDnLevel()) : '未开启')
                      .fontSize(13)
                      .fontColor(this.isDeviceOn() ? this.getTheme().primaryColor : '#999999')
                  }
                  .width('100%')

                  Row({ space: 4 }) {
                    ForEach(SWING_OPTIONS, (item: SwingOption) => {
                      Column() {
                        Text(item.label)
                          .fontSize(12)
                          .fontWeight(this.isDeviceOn() && this.getSwUpDnLevel() === item.level
                            ? FontWeight.Medium : FontWeight.Regular)
                          .fontColor(this.isDeviceOn() && this.getSwUpDnLevel() === item.level
                            ? '#FFFFFF' : '#666666')
                          .maxLines(1)
                      }
                      .layoutWeight(1)
                      .height(34)
                      .justifyContent(FlexAlign.Center)
                      .borderRadius(12)
                      .backgroundColor(this.isDeviceOn() && this.getSwUpDnLevel() === item.level
                        ? this.getTheme().primaryColor : Color.Transparent)
                      .enabled(this.isDeviceOn())
                      .animation({ duration: 180, curve: Curve.EaseOut })
                      .onClick(() => {
                        this.handleSelectSwUpDn(item.level);
                      })
                    }, (item: SwingOption) => `ud_${item.level}`)
                  }
                  .width('100%')
                  .padding(4)
                  .backgroundColor('#F1F3F5')
                  .borderRadius(16)
                  .opacity(this.isDeviceOn() ? 1 : 0.45)
                }
                .width('100%')

                Divider().color('#F1F3F5')

                // 左右风向
                Column({ space: 10 }) {
                  Row() {
                    Text('左右风向')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#182431')
                    Blank()
                    Text(this.isDeviceOn() ? this.formatSwingStatusText(this.getSwingLfRigLevel()) : '未开启')
                      .fontSize(13)
                      .fontColor(this.isDeviceOn() ? this.getTheme().primaryColor : '#999999')
                  }
                  .width('100%')

                  Row({ space: 4 }) {
                    ForEach(SWING_OPTIONS, (item: SwingOption) => {
                      Column() {
                        Text(item.label)
                          .fontSize(12)
                          .fontWeight(this.isDeviceOn() && this.getSwingLfRigLevel() === item.level
                            ? FontWeight.Medium : FontWeight.Regular)
                          .fontColor(this.isDeviceOn() && this.getSwingLfRigLevel() === item.level
                            ? '#FFFFFF' : '#666666')
                          .maxLines(1)
                      }
                      .layoutWeight(1)
                      .height(34)
                      .justifyContent(FlexAlign.Center)
                      .borderRadius(12)
                      .backgroundColor(this.isDeviceOn() && this.getSwingLfRigLevel() === item.level
                        ? this.getTheme().primaryColor : Color.Transparent)
                      .enabled(this.isDeviceOn())
                      .animation({ duration: 180, curve: Curve.EaseOut })
                      .onClick(() => {
                        this.handleSelectSwingLfRig(item.level);
                      })
                    }, (item: SwingOption) => `lr_${item.level}`)
                  }
                  .width('100%')
                  .padding(4)
                  .backgroundColor('#F1F3F5')
                  .borderRadius(16)
                  .opacity(this.isDeviceOn() ? 1 : 0.45)
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .borderRadius(20)
              .shadow({ radius: 14, color: '#08000000', offsetX: 0, offsetY: 3 })

              // 4×2 附加功能网格卡片
              Column({ space: 12 }) {
                Row() {
                  Text('附加功能')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#182431')
                  Blank()
                  Text(this.isDeviceOn() ? '点击即可切换' : '未开启')
                    .fontSize(12)
                    .fontColor('#999999')
                }
                .width('100%')

                Grid() {
                  ForEach(FEATURE_GRID_ITEMS, (item: FeatureGridItem) => {
                    GridItem() {
                      Column({ space: 7 }) {
                        SymbolGlyph(item.symbol)
                          .fontSize(21)
                          .fontColor([
                            this.isDeviceOn() && this.isCurrentTileActive(item.col)
                              ? '#FFFFFF'
                              : '#555555'
                          ])
                        Text(item.title)
                          .fontSize(12)
                          .fontWeight(
                            this.isDeviceOn() && this.isCurrentTileActive(item.col)
                              ? FontWeight.Medium
                              : FontWeight.Regular
                          )
                          .fontColor(
                            this.isDeviceOn() && this.isCurrentTileActive(item.col)
                              ? '#FFFFFF'
                              : '#333333'
                          )
                          .maxLines(1)
                      }
                      .width('100%')
                      .height('100%')
                      .justifyContent(FlexAlign.Center)
                      .alignItems(HorizontalAlign.Center)
                      .borderRadius(14)
                      .backgroundColor(
                        this.isDeviceOn() && this.isCurrentTileActive(item.col)
                          ? this.getTheme().primaryColor
                          : '#F5F7FA'
                      )
                      .shadow(
                        this.isDeviceOn() && this.isCurrentTileActive(item.col)
                          ? { radius: 8, color: '#20000000', offsetX: 0, offsetY: 2 }
                          : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 }
                      )
                      .enabled(this.isDeviceOn())
                      .opacity(this.isDeviceOn() ? 1 : 0.45)
                      .animation({ duration: 180, curve: Curve.EaseOut })
                      .onClick(() => {
                        this.handleCurrentTileClick(item.col);
                      })
                    }
                  }, (item: FeatureGridItem) => item.col)
                }
                .columnsTemplate('1fr 1fr 1fr 1fr')
                .rowsTemplate('1fr 1fr')
                .rowsGap(10)
                .columnsGap(10)
                .width('100%')
                .height(170)
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .borderRadius(20)
              .shadow({ radius: 14, color: '#08000000', offsetX: 0, offsetY: 3 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 28 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 180,
        colors: [
          [this.getTheme().glowTopColor, 0.0],
          ['#F1F3F5', 0.42],
          ['#F1F3F5', 1.0]
        ]
      })
      .animation({ duration: 350, curve: Curve.EaseInOut })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 弹窗 1：设备信息详情（收纳硬件与网络技术参数）
      if (this.showDeviceInfoModal && this.getCurrentDevice() !== null) {
        Column() {
          Column({ space: 6 }) {
            Row() {
              Text('设备信息')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#182431')
              Blank()
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(15)
                  .fontColor(['#666666'])
              }
              .width(30)
              .height(30)
              .backgroundColor('#F1F3F5')
              .onClick(() => {
                this.showDeviceInfoModal = false;
              })
            }
            .width('100%')
            .margin({ bottom: 8 })

            this.infoRow('设备名称', this.getDeviceName())
            Divider().color('#F1F3F5')
            this.infoRow('连接状态', formatControlNavChannelText(this.getDeviceChannel()))
            Divider().color('#F1F3F5')
            this.infoRow('品牌型号', this.getDeviceModelText())
            Divider().color('#F1F3F5')
            this.infoRow('MAC 地址', this.getDeviceMacText())
            Divider().color('#F1F3F5')
            this.infoRow('局域网 IP', this.getDeviceIpText())
            Divider().color('#F1F3F5')
            this.infoRow('固件版本', this.getDeviceVerText())

            Button('知道了', { type: ButtonType.Capsule })
              .width('100%')
              .height(42)
              .backgroundColor('#0A59F7')
              .fontColor('#FFFFFF')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 14 })
              .onClick(() => {
                this.showDeviceInfoModal = false;
              })
          }
          .width('86%')
          .constraintSize({ maxWidth: 360 })
          .padding(22)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .shadow({ radius: 28, color: '#26000000', offsetX: 0, offsetY: 10 })
          .onClick(() => {
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#4D000000')
        .justifyContent(FlexAlign.Center)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => {
          this.showDeviceInfoModal = false;
        })
      }

      // 弹窗 2：重命名设备
      if (this.showRenameModal && this.getCurrentDevice() !== null) {
        Column() {
          Column({ space: 14 }) {
            Text('重命名设备')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#182431')
              .width('100%')

            TextInput({ placeholder: '请输入新的设备名称', text: this.renameInput })
              .height(46)
              .borderRadius(12)
              .backgroundColor('#F5F7FA')
              .fontSize(15)
              .padding({ left: 14, right: 14 })
              .onChange((val: string) => {
                this.renameInput = val;
              })

            Row({ space: 10 }) {
              Button('取消', { type: ButtonType.Capsule })
                .layoutWeight(1)
                .height(42)
                .backgroundColor('#F1F3F5')
                .fontColor('#182431')
                .fontSize(15)
                .onClick(() => {
                  this.showRenameModal = false;
                })

              Button('保存', { type: ButtonType.Capsule })
                .layoutWeight(1)
                .height(42)
                .backgroundColor('#0A59F7')
                .fontColor('#FFFFFF')
                .fontSize(15)
                .onClick(() => {
                  const dev: GreeDeviceModel | null = this.getCurrentDevice();
                  if (dev !== null) {
                    this.vm.renameDevice(dev.mac, this.renameInput);
                  }
                  this.showRenameModal = false;
                })
            }
            .width('100%')
          }
          .width('86%')
          .constraintSize({ maxWidth: 340 })
          .padding(22)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .shadow({ radius: 28, color: '#26000000', offsetX: 0, offsetY: 10 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#4D000000')
        .justifyContent(FlexAlign.Center)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }

      // 弹窗 3：移除设备二次确认
      if (this.showDeleteConfirmModal && this.getCurrentDevice() !== null) {
        Column() {
          Column({ space: 14 }) {
            Text('移除设备')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#182431')
              .width('100%')

            Text(`确定要移除「${this.getDeviceName()}」吗？移除后如需控制，可重新扫描局域网或同步云端设备。`)
              .fontSize(14)
              .fontColor('#555555')
              .lineHeight(20)
              .width('100%')

            Row({ space: 10 }) {
              Button('取消', { type: ButtonType.Capsule })
                .layoutWeight(1)
                .height(42)
                .backgroundColor('#F1F3F5')
                .fontColor('#182431')
                .fontSize(15)
                .onClick(() => {
                  this.showDeleteConfirmModal = false;
                })

              Button('确认移除', { type: ButtonType.Capsule })
                .layoutWeight(1)
                .height(42)
                .backgroundColor('#E84026')
                .fontColor('#FFFFFF')
                .fontSize(15)
                .onClick(async () => {
                  const dev: GreeDeviceModel | null = this.getCurrentDevice();
                  this.showDeleteConfirmModal = false;
                  if (dev !== null) {
                    await this.vm.removeDevice(dev.mac);
                  }
                  this.getUIContext().getRouter().back();
                })
            }
            .width('100%')
            .margin({ top: 4 })
          }
          .width('86%')
          .constraintSize({ maxWidth: 340 })
          .padding(22)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .shadow({ radius: 28, color: '#26000000', offsetX: 0, offsetY: 10 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#4D000000')
        .justifyContent(FlexAlign.Center)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    .width('100%')
    .height('100%')
  }
}
