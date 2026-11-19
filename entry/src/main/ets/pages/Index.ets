import { pasteboard } from '@kit.BasicServicesKit';
import { CardRefreshUtil } from '../common/utils/CardRefreshUtil';
import { HapticUtil } from '../common/utils/HapticUtil';
import { DeviceCard } from '../components/DeviceCard';
import { GreeDeviceModel } from '../model/GreeDeviceModel';
import { GreeCloudSyncResult } from '../model/GreeProtocolTypes';
import { ManualIpProbeResult } from '../service/GreeLocalService';
import { AcControlViewModel } from '../viewmodel/AcControlViewModel';

export interface DeviceControlRouteParams {
  mac: string;
}

interface ShortcutTemplate {
  title: string;
  uri: string;
}

const SHORTCUT_TEMPLATES: ShortcutTemplate[] = [
  { title: '打开空调（制冷 25°C）', uri: 'greeplus://control?power=on&temp=25&mode=cool' },
  { title: '关闭空调', uri: 'greeplus://control?power=off' },
  { title: '制热模式 26°C', uri: 'greeplus://control?power=on&temp=26&mode=heat' }
];

@Entry
@ComponentV2
struct Index {
  private readonly vm: AcControlViewModel = AcControlViewModel.getInstance();

  @Local private isPullRefreshing: boolean = false;
  @Local private showAddIpModal: boolean = false;
  @Local private manualIpInput: string = '192.168.1.';
  @Local private manualNameInput: string = '';
  @Local private manualErrorText: string = '';
  @Local private isProbingIp: boolean = false;
  @Local private showVoiceCardGuideSheet: boolean = false;

  aboutToAppear(): void {
    this.vm.refreshNetworkInfo();
  }

  private getHomeDisplayTitle(): string {
    if (this.vm.cloudSession !== null && this.vm.cloudSession.homeName.trim().length > 0) {
      return this.vm.cloudSession.homeName.trim();
    }
    return '我的家';
  }

  private buildHomeSubtitle(): string {
    const count: number = this.vm.devices.length;
    if (count === 0) {
      return '请登录账号或添加设备';
    }
    return `${count} 台设备`;
  }

  private getAddMenuItems(): MenuElement[] {
    return [
      {
        value: this.vm.isScanning ? '正在扫描...' : '扫描局域网',
        action: (): void => {
          HapticUtil.tick();
          this.vm.scanLan().catch(() => {});
        }
      },
      {
        value: '手动添加 IP',
        action: (): void => {
          this.manualErrorText = '';
          this.showAddIpModal = true;
        }
      },
      {
        value: this.vm.isSyncingCloud ? '正在同步...' : '同步云端设备',
        action: (): void => {
          HapticUtil.tick();
          if (this.vm.cloudSession === null) {
            this.openCloudLogin();
          } else {
            this.handleCloudSyncNow().catch(() => {});
          }
        }
      },
      {
        value: '桌面卡片与小艺语音',
        action: (): void => {
          this.showVoiceCardGuideSheet = true;
        }
      }
    ];
  }

  private async copyShortcutUri(uri: string): Promise<void> {
    try {
      const pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, uri);
      await pasteboard.getSystemPasteboard().setData(pasteData);
      this.getUIContext().getPromptAction().showToast({
        message: '已复制快捷指令',
        duration: 1800
      });
    } catch {
    }
  }

  private async handleRefreshWidgetsNow(): Promise<void> {
    try {
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext !== undefined) {
        await CardRefreshUtil.refreshAllCards(hostContext);
      }
      this.getUIContext().getPromptAction().showToast({
        message: '已刷新桌面卡片状态',
        duration: 1800
      });
    } catch {
    }
  }

  @Builder
  voiceAndCardGuideSheet() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 10 }) {
          Text('桌面万能卡片')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#182431')
            .width('100%')

          Text('支持 2×2 快捷开关与 2×4 调温大卡片：长按桌面应用图标选择「服务卡片」，或双指捏合桌面添加「空调控制」卡片。')
            .fontSize(13)
            .fontColor('#555555')
            .lineHeight(20)
            .width('100%')

          Button('立即同步桌面卡片状态', { type: ButtonType.Capsule })
            .width('100%')
            .height(40)
            .backgroundColor('#EDF4FF')
            .fontColor('#0A59F7')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              this.handleRefreshWidgetsNow();
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(18)

        Column({ space: 10 }) {
          Text('小艺语音快捷指令')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#182431')
            .width('100%')

          Text('复制下方指令后，在「小艺 -> 我的 -> 快捷指令」中添加语音口令并关联「打开链接」，即可语音控温。')
            .fontSize(13)
            .fontColor('#555555')
            .lineHeight(20)
            .width('100%')

          ForEach(SHORTCUT_TEMPLATES, (item: ShortcutTemplate) => {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text(item.title)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#182431')
                Text(item.uri)
                  .fontSize(11)
                  .fontColor('#8A94A6')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Button('复制', { type: ButtonType.Capsule })
                .height(30)
                .fontSize(12)
                .fontColor('#0A59F7')
                .backgroundColor('#EDF4FF')
                .padding({ left: 12, right: 12 })
                .onClick(() => {
                  this.copyShortcutUri(item.uri);
                })
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#F5F7FA')
            .borderRadius(12)
          }, (item: ShortcutTemplate) => item.uri)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(18)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
    .scrollBar(BarState.Off)
  }

  private openDeviceControl(device: GreeDeviceModel): void {
    this.vm.selectDevice(device.mac).catch(() => {});
    const routeParams: DeviceControlRouteParams = { mac: device.mac };
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/DeviceControlPage',
      params: routeParams
    }).catch(() => {});
  }

  private openCloudLogin(): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/CloudLoginPage'
    }).catch(() => {});
  }

  private async handleCloudSyncNow(): Promise<void> {
    const res: GreeCloudSyncResult = await this.vm.syncCloudDevicesNow();
    if (res.tokenExpired) {
      this.openCloudLogin();
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message: res.success ? `已同步 ${res.syncedCount} 台设备` : res.message,
        duration: 2200
      });
    } catch {
    }
  }

  private async handleManualIpSubmit(): Promise<void> {
    if (this.isProbingIp) {
      return;
    }
    this.manualErrorText = '';
    this.isProbingIp = true;
    try {
      const result: ManualIpProbeResult = await this.vm.addManualIp(this.manualIpInput, this.manualNameInput);
      if (result.device === null) {
        this.manualErrorText = result.message;
        return;
      }
      this.showAddIpModal = false;
      this.manualNameInput = '';
      try {
        this.getUIContext().getPromptAction().showToast({
          message: `已添加 ${result.device.name}`,
          duration: 2200
        });
      } catch {
      }
    } finally {
      this.isProbingIp = false;
    }
  }

  build() {
    Stack() {
      Column({ space: 0 }) {
        // Immersive HarmonyOS Home Header
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text(this.getHomeDisplayTitle())
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor('#182431')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.buildHomeSubtitle())
              .fontSize(13)
              .fontColor('#6E7787')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          // Account / Cloud Action Circle Button
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
              .fontSize(20)
              .fontColor([this.vm.needRelogin
                ? '#E84026'
                : (this.vm.cloudSession !== null ? '#0A59F7' : '#182431')])
          }
          .width(40)
          .height(40)
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 10, color: '#0F000000', offsetX: 0, offsetY: 2 })
          .onClick(() => {
            this.openCloudLogin();
          })

          // Add / Scan Menu Circle Button
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(20)
              .fontColor(['#182431'])
          }
          .width(40)
          .height(40)
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 10, color: '#0F000000', offsetX: 0, offsetY: 2 })
          .bindMenu(this.getAddMenuItems())
          .bindSheet($$this.showVoiceCardGuideSheet, this.voiceAndCardGuideSheet(), {
            height: SheetSize.MEDIUM,
            showClose: true,
            title: { title: '桌面卡片与小艺语音' }
          })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 14 })
        .alignItems(VerticalAlign.Center)

        if (this.vm.needRelogin) {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(16)
              .fontColor(['#E84026'])
            Text('云端登录已过期，请重新登录以恢复远程控制')
              .fontSize(12)
              .fontColor('#B91C1C')
              .layoutWeight(1)
            Text('去登录')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#0A59F7')
              .onClick(() => {
                this.openCloudLogin();
              })
          }
          .width('90%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .margin({ bottom: 10 })
          .borderRadius(14)
          .backgroundColor('#FFF1F0')
        }

        // Device Grid / Pull-to-refresh List
        Refresh({ refreshing: $$this.isPullRefreshing }) {
          if (this.vm.devices.length === 0) {
            Scroll() {
              Column({ space: 20 }) {
                Column({ space: 16 }) {
                  Stack() {
                    SymbolGlyph($r('sys.symbol.snowflake'))
                      .fontSize(34)
                      .fontColor(['#0A59F7'])
                  }
                  .width(72)
                  .height(72)
                  .borderRadius(24)
                  .backgroundColor('#EDF4FF')
                  .alignContent(Alignment.Center)

                  Column({ space: 8 }) {
                    Text(this.vm.cloudSession === null ? '欢迎使用 Gree+ 智控' : '暂无可用空调设备')
                      .fontSize(20)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#182431')

                    Text(this.vm.cloudSession === null
                      ? '登录您的 Gree+ 海外账号即可自动同步家中空调，也可通过右上角 + 号发现局域网设备'
                      : '下拉刷新同步云端空调，或点击右上角 + 号搜索同一 Wi-Fi 下的设备')
                      .fontSize(13)
                      .fontColor('#6E7787')
                      .textAlign(TextAlign.Center)
                      .lineHeight(20)
                      .padding({ left: 12, right: 12 })
                  }
                  .alignItems(HorizontalAlign.Center)

                  Button(this.vm.cloudSession === null ? '登录 Gree+ 账号' : '同步云端设备')
                    .type(ButtonType.Capsule)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#FFFFFF')
                    .backgroundColor('#0A59F7')
                    .height(44)
                    .padding({ left: 28, right: 28 })
                    .onClick(() => {
                      HapticUtil.tick();
                      if (this.vm.cloudSession === null) {
                        this.openCloudLogin();
                      } else {
                        this.handleCloudSyncNow();
                      }
                    })
                }
                .width('100%')
                .padding({ top: 36, bottom: 36, left: 20, right: 20 })
                .backgroundColor('#FFFFFF')
                .borderRadius(24)
                .shadow({ radius: 16, color: '#0B000000', offsetX: 0, offsetY: 4 })
                .alignItems(HorizontalAlign.Center)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 44, bottom: 80 })
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
          } else {
            List({ space: 12 }) {
              ForEach(this.vm.devices, (device: GreeDeviceModel) => {
                ListItem() {
                  DeviceCard({
                    device: device,
                    onOpenControl: (): void => {
                      this.openDeviceControl(device);
                    },
                    onTogglePower: (): void => {
                      this.vm.togglePower(device.mac);
                    }
                  })
                }
              }, (device: GreeDeviceModel) => device.mac)
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
            .padding({ left: 16, right: 16, top: 4, bottom: 28 })
          }
        }
        .layoutWeight(1)
        .onRefreshing(() => {
          const refreshTask: Promise<void> = this.vm.cloudSession !== null
            ? this.vm.syncCloudDevicesNow().then(() => {})
            : this.vm.scanLan();
          refreshTask.finally(() => {
            setTimeout(() => {
              this.isPullRefreshing = false;
            }, 600);
          });
        })
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 180,
        colors: [['#E8EFF9', 0.0], ['#F1F3F5', 0.28], ['#F1F3F5', 1.0]]
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // Manual IP Add Dialog
      if (this.showAddIpModal) {
        Column() {
          Column({ space: 14 }) {
            Text('手动添加设备')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#182431')
              .width('100%')

            Text('若空调未自动出现在列表中，可输入设备在路由器中分配的局域网地址进行连接。')
              .fontSize(13)
              .fontColor('#6E7787')
              .lineHeight(19)
              .width('100%')

            TextInput({ placeholder: '设备局域网地址（例如 192.168.1.100）', text: this.manualIpInput })
              .height(46)
              .borderRadius(12)
              .backgroundColor('#F5F7FA')
              .onChange((val: string) => {
                this.manualIpInput = val;
              })

            TextInput({ placeholder: '设备名称（可选，如 客厅空调）', text: this.manualNameInput })
              .height(46)
              .borderRadius(12)
              .backgroundColor('#F5F7FA')
              .onChange((val: string) => {
                this.manualNameInput = val;
              })

            if (this.manualErrorText.length > 0) {
              Text(this.manualErrorText)
                .fontSize(12)
                .fontColor('#E84026')
                .width('100%')
            }

            Row({ space: 10 }) {
              Button('取消')
                .type(ButtonType.Capsule)
                .fontSize(14)
                .fontColor('#4E5969')
                .backgroundColor('#F1F3F5')
                .height(42)
                .layoutWeight(1)
                .onClick(() => {
                  this.showAddIpModal = false;
                })

              Button(this.isProbingIp ? '连接中...' : '添加')
                .type(ButtonType.Capsule)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .backgroundColor('#0A59F7')
                .height(42)
                .layoutWeight(1)
                .enabled(!this.isProbingIp)
                .onClick(() => {
                  this.handleManualIpSubmit();
                })
            }
            .width('100%')
          }
          .width('88%')
          .padding(22)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .shadow({ radius: 28, color: '#28000000', offsetX: 0, offsetY: 10 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#59000000')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
