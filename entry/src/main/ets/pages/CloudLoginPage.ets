import { GREE_MQTT_TLS_PORT } from '../common/constants/GreeConstants';
import {
  CountryLetterGroup,
  getCountryGroups,
  getCountryIndexLetters,
  GreeCountryItem,
  searchCountries
} from '../common/constants/GreeCountryConfig';
import { GreeCloudSyncResult } from '../model/GreeProtocolTypes';
import { AcControlViewModel } from '../viewmodel/AcControlViewModel';

@Entry
@ComponentV2
struct CloudLoginPage {
  private readonly vm: AcControlViewModel = AcControlViewModel.getInstance();
  private readonly countryGroups: CountryLetterGroup[] = getCountryGroups();
  private readonly countryIndexLetters: string[] = getCountryIndexLetters();
  private readonly countryListScroller: Scroller = new Scroller();

  @Local private showCountrySheet: boolean = false;
  @Local private countrySearchQuery: string = '';
  @Local private selectedIndexPos: number = 0;
  @Local private accountInput: string = '';
  @Local private passwordInput: string = '';
  @Local private showPassword: boolean = false;
  @Local private resultBanner: string = '';
  @Local private resultIsError: boolean = false;

  @Local private showAdvancedServer: boolean = false;
  @Local private customOverrideEnabled: boolean = false;
  @Local private customApiUrlInput: string = '';
  @Local private customMqttHostInput: string = '';
  @Local private customMqttPortInput: string = '';
  @Local private customAppIdInput: string = '';
  @Local private customAppKeyInput: string = '';

  aboutToAppear(): void {
    if (this.vm.cloudSession !== null) {
      this.accountInput = this.vm.cloudSession.account;
    }
    if (this.vm.customOverride !== null) {
      this.customOverrideEnabled = this.vm.customOverride.enabled;
      this.customApiUrlInput = this.vm.customOverride.apiBaseUrl;
      this.customMqttHostInput = this.vm.customOverride.mqttHost;
      this.customMqttPortInput = this.vm.customOverride.mqttPort > 0
        ? String(this.vm.customOverride.mqttPort)
        : '';
      this.customAppIdInput = this.vm.customOverride.appId ?? '';
      this.customAppKeyInput = this.vm.customOverride.appKey ?? '';
    }
    if (this.vm.selectedCountryCode.length > 0) {
      this.vm.refreshCountryRoute(this.vm.selectedCountryCode).catch(() => {});
    }
  }

  private getCountryDisplayText(): string {
    const selected: GreeCountryItem | null = this.vm.getSelectedCountry();
    if (selected === null) {
      return '请选择国家/地区';
    }
    return `${selected.nameZh} (${selected.dialCode})`;
  }

  private isCountrySelected(): boolean {
    return this.vm.getSelectedCountry() !== null;
  }

  private getFilteredCountries(): GreeCountryItem[] {
    return searchCountries(this.countrySearchQuery);
  }

  private async handleSelectCountry(country: GreeCountryItem): Promise<void> {
    this.showCountrySheet = false;
    this.countrySearchQuery = '';
    await this.vm.selectCountry(country.code);
  }

  private async handleLoginAndSync(): Promise<void> {
    if (this.vm.getSelectedCountry() === null) {
      this.resultBanner = '请先选择国家/地区';
      this.resultIsError = true;
      this.showCountrySheet = true;
      return;
    }
    this.resultBanner = '';
    const res: GreeCloudSyncResult = await this.vm.loginCloudAndSync(
      this.accountInput,
      this.passwordInput,
      this.vm.selectedCountryCode
    );
    this.resultBanner = res.message;
    this.resultIsError = !res.success;
    if (res.success) {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: res.message,
          duration: 2000
        });
      } catch {
      }
      this.getUIContext().getRouter().back();
    }
  }

  private async handleSaveCustomOverride(): Promise<void> {
    const parsedPort: number = Number(this.customMqttPortInput.trim());
    const effectivePort: number = !Number.isNaN(parsedPort) && parsedPort > 0 && parsedPort <= 65535
      ? Math.floor(parsedPort)
      : GREE_MQTT_TLS_PORT;
    await this.vm.saveCustomServerOverride(
      this.customOverrideEnabled,
      this.customApiUrlInput,
      this.customMqttHostInput,
      effectivePort,
      this.customAppIdInput,
      this.customAppKeyInput
    );
    this.showAdvancedServer = false;
    try {
      this.getUIContext().getPromptAction().showToast({
        message: this.customOverrideEnabled ? '已应用自定义服务器配置' : '已恢复默认服务器路由',
        duration: 1800
      });
    } catch {
    }
  }

  private async handleClearCustomOverride(): Promise<void> {
    this.customOverrideEnabled = false;
    this.customApiUrlInput = '';
    this.customMqttHostInput = '';
    this.customMqttPortInput = '';
    this.customAppIdInput = '';
    this.customAppKeyInput = '';
    await this.vm.clearCustomServerOverride();
    this.showAdvancedServer = false;
    try {
      this.getUIContext().getPromptAction().showToast({
        message: '已恢复默认服务器配置',
        duration: 1800
      });
    } catch {
    }
  }

  @Builder
  letterGroupHeader(letter: string) {
    Row() {
      Text(letter)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor('#5C6B7F')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  countryRowItem(item: GreeCountryItem) {
    Row() {
      Column({ space: 2 }) {
        Text(item.nameZh)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.vm.selectedCountryCode === item.code ? '#0A59F7' : '#182431')
        Text(item.nameEn)
          .fontSize(12)
          .fontColor('#8A94A6')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 8 }) {
        Text(item.dialCode)
          .fontSize(13)
          .fontColor('#5C6B7F')
        if (this.vm.selectedCountryCode === item.code) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(18)
            .fontColor(['#0A59F7'])
        }
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .borderRadius(12)
    .backgroundColor(this.vm.selectedCountryCode === item.code ? '#EDF4FF' : '#F8F9FA')
    .onClick(() => {
      this.handleSelectCountry(item);
    })
  }

  @Builder
  countryPickerSheet() {
    Column({ space: 12 }) {
      Row({ space: 6 }) {
        TextInput({ placeholder: '搜索国家/地区、拼音、英文或区号', text: this.countrySearchQuery })
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Color.Transparent)
          .fontColor('#182431')
          .placeholderColor('#8A94A6')
          .caretColor('#0A59F7')
          .fontSize(14)
          .padding({ left: 14, right: 4 })
          .onChange((val: string) => {
            this.countrySearchQuery = val;
          })

        if (this.countrySearchQuery.length > 0) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(14)
              .fontColor(['#5C6B7F'])
          }
          .width(30)
          .height(30)
          .backgroundColor('#E5E7EB')
          .margin({ right: 8 })
          .onClick(() => {
            this.countrySearchQuery = '';
          })
        }
      }
      .width('100%')
      .height(44)
      .backgroundColor('#F1F3F5')
      .borderRadius(12)
      .alignItems(VerticalAlign.Center)

      if (this.countrySearchQuery.trim().length === 0) {
        Stack({ alignContent: Alignment.End }) {
          List({ space: 0, scroller: this.countryListScroller }) {
            ForEach(this.countryGroups, (group: CountryLetterGroup) => {
              ListItemGroup({ header: this.letterGroupHeader(group.initial), space: 6 }) {
                ForEach(group.items, (item: GreeCountryItem) => {
                  ListItem() {
                    this.countryRowItem(item)
                  }
                }, (item: GreeCountryItem) => item.code)
              }
              .margin({ bottom: 6 })
            }, (group: CountryLetterGroup) => group.initial)
          }
          .width('100%')
          .height('100%')
          .padding({ right: 24 })
          .sticky(StickyStyle.Header)
          .scrollBar(BarState.Off)
          .onScrollIndex((firstIndex: number) => {
            this.selectedIndexPos = firstIndex;
          })

          AlphabetIndexer({ arrayValue: this.countryIndexLetters, selected: this.selectedIndexPos })
            .selectedColor('#FFFFFF')
            .selectedBackgroundColor('#0A59F7')
            .usingPopup(true)
            .onSelect((index: number) => {
              this.selectedIndexPos = index;
              this.countryListScroller.scrollToIndex(index);
            })
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.getFilteredCountries().length === 0) {
        Column({ space: 8 }) {
          Text('未找到匹配的国家或地区')
            .fontSize(14)
            .fontColor('#8A94A6')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 6 }) {
          ForEach(this.getFilteredCountries(), (item: GreeCountryItem) => {
            ListItem() {
              this.countryRowItem(item)
            }
          }, (item: GreeCountryItem) => item.code)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 0 }) {
        // 顶部导航栏
        Row() {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(20)
              .fontColor(['#182431'])
          }
          .width(40)
          .height(40)
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 })
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })

          Blank()

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(19)
              .fontColor([this.customOverrideEnabled ? '#0A59F7' : '#555555'])
          }
          .width(40)
          .height(40)
          .backgroundColor('#FFFFFF')
          .shadow({ radius: 8, color: '#0A000000', offsetX: 0, offsetY: 2 })
          .onClick(() => {
            this.showAdvancedServer = true;
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })

        Scroll() {
          Column({ space: 18 }) {
            // 品牌与标题区
            Column({ space: 10 }) {
              Column() {
                SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
                  .fontSize(36)
                  .fontColor(['#0A59F7'])
              }
              .width(64)
              .height(64)
              .borderRadius(18)
              .backgroundColor('#FFFFFF')
              .justifyContent(FlexAlign.Center)
              .shadow({ radius: 14, color: '#0E0A59F7', offsetX: 0, offsetY: 4 })

              Text('登录 Gree+ 账号')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor('#182431')

              Text('同步您的家庭与空调设备，随时随地远程控制')
                .fontSize(13)
                .fontColor('#666666')
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .margin({ top: 8, bottom: 4 })

            // 当前已登录会话卡片
            if (this.vm.cloudSession !== null) {
              Column({ space: 12 }) {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle'))
                    .fontSize(18)
                    .fontColor(['#008A60'])
                  Text('当前已登录')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#182431')
                  Blank()
                  Text(this.vm.cloudSession.countryNameZh)
                    .fontSize(12)
                    .fontColor('#008A60')
                    .backgroundColor('#E8F8F0')
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .borderRadius(12)
                }
                .width('100%')

                Text(`${this.vm.cloudSession.account} · ${this.vm.cloudSession.homeName}`)
                  .fontSize(13)
                  .fontColor('#666666')
                  .width('100%')

                Row({ space: 10 }) {
                  Button(this.vm.isSyncingCloud ? '同步中...' : '同步设备', { type: ButtonType.Capsule })
                    .layoutWeight(1)
                    .height(40)
                    .backgroundColor('#EDF4FF')
                    .fontColor('#0A59F7')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .enabled(!this.vm.isSyncingCloud)
                    .onClick(() => {
                      this.vm.syncCloudDevicesNow().then((res: GreeCloudSyncResult) => {
                        this.resultBanner = res.message;
                        this.resultIsError = !res.success;
                        if (res.success) {
                          this.getUIContext().getRouter().back();
                        }
                      });
                    })

                  Button('退出登录', { type: ButtonType.Capsule })
                    .layoutWeight(1)
                    .height(40)
                    .backgroundColor('#FFF0EE')
                    .fontColor('#E84026')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .onClick(() => {
                      this.vm.logoutCloud();
                      this.resultBanner = '已退出当前云端账号';
                      this.resultIsError = false;
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(18)
              .backgroundColor('#FFFFFF')
              .borderRadius(20)
              .shadow({ radius: 14, color: '#08000000', offsetX: 0, offsetY: 3 })
            }

            // 登录表单卡片
            Column({ space: 14 }) {
              // 国家/地区选择行
              Row() {
                Text('国家/地区')
                  .fontSize(14)
                  .fontColor('#555555')
                Blank()
                Row({ space: 6 }) {
                  Text(this.getCountryDisplayText())
                    .fontSize(14)
                    .fontWeight(this.isCountrySelected() ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.isCountrySelected() ? '#182431' : '#8A94A6')
                  Text(this.isCountrySelected() ? '切换' : '选择')
                    .fontSize(13)
                    .fontColor('#0A59F7')
                }
              }
              .width('100%')
              .height(48)
              .padding({ left: 14, right: 14 })
              .backgroundColor('#F5F7FA')
              .borderRadius(12)
              .onClick(() => {
                this.showCountrySheet = true;
              })
              .bindSheet($$this.showCountrySheet, this.countryPickerSheet(), {
                height: SheetSize.LARGE,
                showClose: true,
                title: { title: '选择国家或地区' }
              })

              TextInput({ placeholder: '邮箱或手机号', text: this.accountInput })
                .height(48)
                .borderRadius(12)
                .backgroundColor('#F1F3F5')
                .fontColor('#182431')
                .placeholderColor('#8A94A6')
                .caretColor('#0A59F7')
                .fontSize(15)
                .padding({ left: 14, right: 14 })
                .onChange((val: string) => {
                  this.accountInput = val;
                })

              Row({ space: 4 }) {
                TextInput({ placeholder: '登录密码', text: this.passwordInput })
                  .layoutWeight(1)
                  .height(48)
                  .backgroundColor(Color.Transparent)
                  .fontColor('#182431')
                  .placeholderColor('#8A94A6')
                  .caretColor('#0A59F7')
                  .fontSize(15)
                  .padding({ left: 14, right: 4 })
                  .type(InputType.Password)
                  .showPasswordIcon(false)
                  .showPassword(this.showPassword)
                  .onChange((val: string) => {
                    this.passwordInput = val;
                  })

                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph(this.showPassword ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'))
                    .fontSize(18)
                    .fontColor(['#5C6B7F'])
                }
                .width(38)
                .height(38)
                .backgroundColor(Color.Transparent)
                .margin({ right: 6 })
                .onClick(() => {
                  this.showPassword = !this.showPassword;
                })
              }
              .width('100%')
              .height(48)
              .backgroundColor('#F1F3F5')
              .borderRadius(12)
              .alignItems(VerticalAlign.Center)

              if (this.resultBanner.length > 0) {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.info_circle'))
                    .fontSize(16)
                    .fontColor([this.resultIsError ? '#E84026' : '#008A60'])
                  Text(this.resultBanner)
                    .fontSize(13)
                    .fontColor(this.resultIsError ? '#C42E1B' : '#00734F')
                    .layoutWeight(1)
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .backgroundColor(this.resultIsError ? '#FFF0EE' : '#E8F8F0')
                .borderRadius(12)
              }

              Button(this.vm.isSyncingCloud ? '正在登录...' : '登录', { type: ButtonType.Capsule })
                .width('100%')
                .height(48)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .backgroundColor('#0A59F7')
                .margin({ top: 4 })
                .enabled(!this.vm.isSyncingCloud)
                .onClick(() => {
                  this.handleLoginAndSync();
                })
            }
            .width('100%')
            .padding(20)
            .backgroundColor('#FFFFFF')
            .borderRadius(20)
            .shadow({ radius: 18, color: '#0A000000', offsetX: 0, offsetY: 5 })

            Text('同一账号在同一时间仅支持在单个设备端保持登录状态')
              .fontSize(12)
              .fontColor('#999999')
              .textAlign(TextAlign.Center)
              .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 28 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 180,
        colors: [
          ['#EDF4FF', 0.0],
          ['#F1F3F5', 0.36],
          ['#F1F3F5', 1.0]
        ]
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 高级服务器设置弹窗（仅点击右上角设置图标时展开）
      if (this.showAdvancedServer) {
        Column() {
          Column({ space: 12 }) {
            Row() {
              Text('高级服务器设置')
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
                this.showAdvancedServer = false;
              })
            }
            .width('100%')

            Row() {
              Text('启用自定义服务器地址')
                .fontSize(14)
                .fontColor('#182431')
                .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.customOverrideEnabled })
                .onChange((isOn: boolean) => {
                  this.customOverrideEnabled = isOn;
                })
            }
            .width('100%')

            TextInput({ placeholder: 'API 地址（如 https://hkgrih.gree.com）', text: this.customApiUrlInput })
              .height(42)
              .borderRadius(10)
              .backgroundColor('#F1F3F5')
              .fontColor('#182431')
              .placeholderColor('#8A94A6')
              .caretColor('#0A59F7')
              .fontSize(14)
              .onChange((val: string) => {
                this.customApiUrlInput = val;
              })

            TextInput({ placeholder: 'MQTT 域名（可选）', text: this.customMqttHostInput })
              .height(42)
              .borderRadius(10)
              .backgroundColor('#F1F3F5')
              .fontColor('#182431')
              .placeholderColor('#8A94A6')
              .caretColor('#0A59F7')
              .fontSize(14)
              .onChange((val: string) => {
                this.customMqttHostInput = val;
              })

            TextInput({ placeholder: 'MQTT 端口（默认 1984）', text: this.customMqttPortInput })
              .height(42)
              .borderRadius(10)
              .backgroundColor('#F1F3F5')
              .fontColor('#182431')
              .placeholderColor('#8A94A6')
              .caretColor('#0A59F7')
              .fontSize(14)
              .type(InputType.Number)
              .onChange((val: string) => {
                this.customMqttPortInput = val;
              })

            TextInput({ placeholder: '自定义 AppId（可选）', text: this.customAppIdInput })
              .height(42)
              .borderRadius(10)
              .backgroundColor('#F1F3F5')
              .fontColor('#182431')
              .placeholderColor('#8A94A6')
              .caretColor('#0A59F7')
              .fontSize(14)
              .onChange((val: string) => {
                this.customAppIdInput = val;
              })

            TextInput({ placeholder: '自定义 AppHash（可选）', text: this.customAppKeyInput })
              .height(42)
              .borderRadius(10)
              .backgroundColor('#F1F3F5')
              .fontColor('#182431')
              .placeholderColor('#8A94A6')
              .caretColor('#0A59F7')
              .fontSize(14)
              .onChange((val: string) => {
                this.customAppKeyInput = val;
              })

            Row({ space: 10 }) {
              Button('恢复默认', { type: ButtonType.Capsule })
                .layoutWeight(1)
                .height(40)
                .backgroundColor('#F1F3F5')
                .fontColor('#182431')
                .fontSize(14)
                .onClick(() => {
                  this.handleClearCustomOverride();
                })

              Button('应用', { type: ButtonType.Capsule })
                .layoutWeight(1)
                .height(40)
                .backgroundColor('#0A59F7')
                .fontColor('#FFFFFF')
                .fontSize(14)
                .onClick(() => {
                  this.handleSaveCustomOverride();
                })
            }
            .width('100%')
            .margin({ top: 4 })
          }
          .width('88%')
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
          this.showAdvancedServer = false;
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
