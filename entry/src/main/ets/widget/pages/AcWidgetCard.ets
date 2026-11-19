const widgetStorage: LocalStorage = new LocalStorage();

@Entry(widgetStorage)
@Component
struct AcWidgetCard {
  @LocalStorageProp('formId') formId: string = '';
  @LocalStorageProp('hasDevice') hasDevice: boolean = false;
  @LocalStorageProp('deviceCount') deviceCount: number = 0;
  @LocalStorageProp('mac') mac: string = '';
  @LocalStorageProp('name') name: string = '格力空调';
  @LocalStorageProp('isOn') isOn: boolean = false;
  @LocalStorageProp('modeText') modeText: string = '未添加设备';
  @LocalStorageProp('fanText') fanText: string = '自动';
  @LocalStorageProp('swingOn') swingOn: boolean = false;
  @LocalStorageProp('swingText') swingText: string = '定格';
  @LocalStorageProp('setTempText') setTempText: string = '--';
  @LocalStorageProp('indoorTempText') indoorTempText: string = '--';
  @LocalStorageProp('unitSymbol') unitSymbol: string = '°C';
  @LocalStorageProp('primaryColor') primaryColor: string = '#0A59F7';
  @LocalStorageProp('softBgColor') softBgColor: string = '#EDF4FF';
  @LocalStorageProp('dimension') dimension: number = 2;

  private triggerRouterToControl(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        targetPage: 'pages/DeviceControlPage',
        mac: this.mac
      }
    });
  }

  private triggerMessageControl(controlAction: string): void {
    postCardAction(this, {
      action: 'message',
      params: {
        action: controlAction,
        formId: this.formId,
        mac: this.mac
      }
    });
  }

  @Builder
  powerIcon(iconColor: string, size: number = 18) {
    Stack({ alignContent: Alignment.Center }) {
      Circle({ width: size - 2, height: size - 2 })
        .fill(Color.Transparent)
        .stroke(iconColor)
        .strokeWidth(1.8)
      Rect({ width: 2, height: (size - 2) * 0.48 })
        .fill(iconColor)
        .radius(1)
        .margin({ bottom: (size - 2) * 0.42 })
    }
    .width(size)
    .height(size)
  }

  build() {
    Column() {
      if (this.dimension === 3) {
        // 2*4 宽幅卡片：3 层紧凑控制布局（外层容器不绑 onClick，避免抢占按钮事件）
        Column({ space: 6 }) {
          // 第一行：顶部标题区（点击跳详情页） + 切换设备按钮 + 圆形电源键
          Row({ space: 6 }) {
            Row({ space: 6 }) {
              Circle({ width: 8, height: 8 })
                .fill(this.isOn ? this.primaryColor : '#9AA3B2')
              Text(this.name)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor('#182431')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .layoutWeight(1)
            .height(34)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.triggerRouterToControl();
            })

            if (this.deviceCount > 1) {
              Button() {
                Text('⇄')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#0A59F7')
              }
              .type(ButtonType.Circle)
              .width(34)
              .height(34)
              .backgroundColor('#EBF3FF')
              .enabled(true)
              .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
              .onClick(() => {
                this.triggerMessageControl('next_device');
              })
            }

            Button() {
              this.powerIcon(this.isOn ? '#FFFFFF' : '#182431', 16)
            }
            .type(ButtonType.Circle)
            .width(36)
            .height(36)
            .backgroundColor(this.isOn ? this.primaryColor : '#F2F4F7')
            .enabled(true)
            .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
            .onClick(() => {
              this.triggerMessageControl('toggle_power');
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          // 第二行：左侧大温度 + 状态副文案；右侧 36x36 - / + 圆形按钮
          Row() {
            Column({ space: 2 }) {
              Row({ space: 2 }) {
                Text(this.hasDevice ? this.setTempText : '--')
                  .fontSize(34)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isOn ? '#182431' : '#8A94A6')
                  .lineHeight(36)
                Text(this.unitSymbol)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isOn ? '#555555' : '#9AA3B2')
                  .margin({ top: 4 })
              }
              .alignItems(VerticalAlign.Top)

              Text(this.hasDevice
                ? `${this.modeText} · 室温 ${this.indoorTempText}${this.unitSymbol}`
                : '点击顶部名称打开应用')
                .fontSize(11)
                .fontColor('#666666')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Row({ space: 10 }) {
              Button() {
                Text('−')
                  .fontSize(20)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.hasDevice && this.isOn ? '#182431' : '#999999')
              }
              .type(ButtonType.Circle)
              .width(36)
              .height(36)
              .backgroundColor('#FFFFFF')
              .enabled(true)
              .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
              .onClick(() => {
                this.triggerMessageControl('temp_down');
              })

              Button() {
                Text('+')
                  .fontSize(20)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.hasDevice && this.isOn ? '#182431' : '#999999')
              }
              .type(ButtonType.Circle)
              .width(36)
              .height(36)
              .backgroundColor('#FFFFFF')
              .enabled(true)
              .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
              .onClick(() => {
                this.triggerMessageControl('temp_up');
              })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          // 第三行：模式 / 风速 / 上下摆风 3 枚并排快捷胶囊
          Row({ space: 8 }) {
            Button() {
              Text(this.isOn ? `模式 · ${this.modeText}` : '模式')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.hasDevice && this.isOn ? '#182431' : '#8A94A6')
                .maxLines(1)
            }
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .height(34)
            .backgroundColor('#FFFFFF')
            .enabled(true)
            .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
            .onClick(() => {
              this.triggerMessageControl('cycle_mode');
            })

            Button() {
              Text(`风速 · ${this.fanText}`)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.hasDevice && this.isOn ? '#182431' : '#8A94A6')
                .maxLines(1)
            }
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .height(34)
            .backgroundColor('#FFFFFF')
            .enabled(true)
            .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
            .onClick(() => {
              this.triggerMessageControl('cycle_fan');
            })

            Button() {
              Text(`摆风 · ${this.swingText}`)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.hasDevice && this.isOn && this.swingOn ? '#FFFFFF' : '#555555')
                .maxLines(1)
            }
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .height(34)
            .backgroundColor(this.hasDevice && this.isOn && this.swingOn ? this.primaryColor : '#FFFFFF')
            .enabled(true)
            .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
            .onClick(() => {
              this.triggerMessageControl('toggle_swing');
            })
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      } else {
        // 2*2 小卡片：顶部标题区点击跳详情页，底部独立 34x34 控制按钮
        Column() {
          Row({ space: 4 }) {
            Row({ space: 5 }) {
              Circle({ width: 7, height: 7 })
                .fill(this.isOn ? this.primaryColor : '#9AA3B2')
              Text(this.name)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor('#182431')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .layoutWeight(1)
            .height(34)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.triggerRouterToControl();
            })

            if (this.deviceCount > 1) {
              Button() {
                Text('⇄')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#0A59F7')
              }
              .type(ButtonType.Circle)
              .width(34)
              .height(34)
              .backgroundColor('#EBF3FF')
              .enabled(true)
              .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
              .onClick(() => {
                this.triggerMessageControl('next_device');
              })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Blank()

          Column({ space: 2 }) {
            Row({ space: 2 }) {
              Text(this.hasDevice ? this.setTempText : '--')
                .fontSize(26)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isOn ? '#182431' : '#8A94A6')
                .lineHeight(28)
              Text(this.unitSymbol)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isOn ? '#555555' : '#9AA3B2')
                .margin({ top: 3 })
            }
            .alignItems(VerticalAlign.Top)

            Text(this.hasDevice ? this.modeText : '未添加设备')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isOn ? this.primaryColor : '#666666')
              .maxLines(1)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Blank()

          Row() {
            Button() {
              this.powerIcon(this.isOn ? '#FFFFFF' : '#182431', 15)
            }
            .type(ButtonType.Circle)
            .width(34)
            .height(34)
            .backgroundColor(this.isOn ? this.primaryColor : '#F2F4F7')
            .enabled(true)
            .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
            .onClick(() => {
              this.triggerMessageControl('toggle_power');
            })

            Blank()

            Row({ space: 6 }) {
              Button() {
                Text('−')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.hasDevice && this.isOn ? '#182431' : '#999999')
              }
              .type(ButtonType.Circle)
              .width(34)
              .height(34)
              .backgroundColor('#FFFFFF')
              .enabled(true)
              .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
              .onClick(() => {
                this.triggerMessageControl('temp_down');
              })

              Button() {
                Text('+')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.hasDevice && this.isOn ? '#182431' : '#999999')
              }
              .type(ButtonType.Circle)
              .width(34)
              .height(34)
              .backgroundColor('#FFFFFF')
              .enabled(true)
              .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
              .onClick(() => {
                this.triggerMessageControl('temp_up');
              })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor(this.isOn ? this.softBgColor : '#FFFFFF')
    .borderRadius(20)
  }
}
