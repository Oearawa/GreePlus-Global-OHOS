import {
  GreeAcMode,
  GreeFanSpeed,
  GreePowerState,
  GreeTempUnit,
  MAX_TEMP_C,
  MAX_TEMP_F,
  MIN_TEMP_C,
  MIN_TEMP_F
} from '../common/constants/GreeConstants';
import { AcModeThemePalette, getAcModeTheme, getModeSymbol } from '../common/theme/AcThemeHelper';
import { HapticUtil } from '../common/utils/HapticUtil';
import { GreeDeviceModel } from '../model/GreeDeviceModel';

interface ModeOption {
  mode: GreeAcMode;
  label: string;
  symbol: Resource;
}

interface FanOption {
  speed: GreeFanSpeed;
  label: string;
}

const MODE_OPTIONS: ModeOption[] = [
  { mode: GreeAcMode.AUTO, label: '自动', symbol: getModeSymbol(GreeAcMode.AUTO) },
  { mode: GreeAcMode.COOL, label: '制冷', symbol: getModeSymbol(GreeAcMode.COOL) },
  { mode: GreeAcMode.DRY, label: '除湿', symbol: getModeSymbol(GreeAcMode.DRY) },
  { mode: GreeAcMode.FAN, label: '送风', symbol: getModeSymbol(GreeAcMode.FAN) },
  { mode: GreeAcMode.HEAT, label: '制热', symbol: getModeSymbol(GreeAcMode.HEAT) }
];

const FAN_OPTIONS: FanOption[] = [
  { speed: GreeFanSpeed.AUTO, label: '自动' },
  { speed: GreeFanSpeed.LOW, label: '低' },
  { speed: GreeFanSpeed.MEDIUM_LOW, label: '中低' },
  { speed: GreeFanSpeed.MEDIUM, label: '中' },
  { speed: GreeFanSpeed.MEDIUM_HIGH, label: '中高' },
  { speed: GreeFanSpeed.HIGH, label: '高' }
];

/**
 * 空调核心控制面板组件（HarmonyOS Design 风格）
 * 包含温度调节主卡、运行模式选择与风速分段控制
 */
@ComponentV2
export struct TempDialControl {
  @Require @Param device: GreeDeviceModel;
  @Param onStepTemp: (delta: number) => void = (_delta: number): void => {};
  @Param onSetTemp: (targetDisplayTemp: number) => void = (_temp: number): void => {};
  @Param onToggleUnit: () => void = (): void => {};
  @Param onSelectMode: (mode: GreeAcMode) => void = (_mode: GreeAcMode): void => {};
  @Param onSelectFanSpeed: (speed: GreeFanSpeed) => void = (_speed: GreeFanSpeed): void => {};
  @Param onTogglePower: () => void = (): void => {};

  private lastSliderStep: number = -1;
  private tempTransition: NumericTextTransition = new NumericTextTransition({
    flipDirection: FlipDirection.DOWN,
    enableBlur: false
  });

  private isDeviceOn(): boolean {
    return this.device.pow === GreePowerState.ON;
  }

  private isFahrenheitUnit(): boolean {
    return this.device.temUn === GreeTempUnit.FAHRENHEIT;
  }

  private getMinTemp(): number {
    return this.isFahrenheitUnit() ? MIN_TEMP_F : MIN_TEMP_C;
  }

  private getMaxTemp(): number {
    return this.isFahrenheitUnit() ? MAX_TEMP_F : MAX_TEMP_C;
  }

  private getTheme(): AcModeThemePalette {
    return getAcModeTheme(this.device.pow, this.device.mod);
  }

  private getCurrentModeLabel(): string {
    for (let i = 0; i < MODE_OPTIONS.length; i++) {
      if (MODE_OPTIONS[i].mode === this.device.mod) {
        return MODE_OPTIONS[i].label;
      }
    }
    return '制冷';
  }

  private getCurrentFanLabel(): string {
    for (let i = 0; i < FAN_OPTIONS.length; i++) {
      if (FAN_OPTIONS[i].speed === this.device.wdSpd) {
        return FAN_OPTIONS[i].label;
      }
    }
    return '自动';
  }

  private handleSliderChange(val: number, mode: SliderChangeMode): void {
    const rounded: number = Math.round(val);
    const currentTarget: number = this.device.getDisplayTargetTemp();
    if ((this.lastSliderStep >= 0 && rounded !== this.lastSliderStep) ||
      (mode === SliderChangeMode.Click && rounded !== currentTarget)) {
      HapticUtil.tick();
    }
    this.lastSliderStep = rounded;
    this.onSetTemp(rounded);
    if (mode === SliderChangeMode.End) {
      this.lastSliderStep = -1;
    }
  }

  build() {
    Column({ space: 12 }) {
      // 1. 温度主控 Hero 卡片
      Column() {
        // 顶部室内温度与温标切换胶囊
        Row() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.thermometer'))
              .fontSize(15)
              .fontColor([this.isDeviceOn() ? this.getTheme().primaryColor : '#8A94A6'])
            Text(`室内 ${this.device.getDisplayIndoorTemp()}${this.device.getTempUnitSymbol()}`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#666666')
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor('#F5F7FA')
          .borderRadius(12)

          Blank()

          Button({ type: ButtonType.Capsule }) {
            Text(this.isFahrenheitUnit() ? '°F 华氏度' : '°C 摄氏度')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#555555')
              .padding({ left: 12, right: 12 })
          }
          .height(28)
          .backgroundColor('#F5F7FA')
          .onClick(() => {
            HapticUtil.tick();
            this.onToggleUnit();
          })
        }
        .width('100%')

        // 核心温度显示与圆形加减按钮
        Row() {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.minus'))
              .fontSize(22)
              .fontColor([this.isDeviceOn() && this.device.getDisplayTargetTemp() > this.getMinTemp()
                ? '#182431' : '#CCCCCC'])
          }
          .width(52)
          .height(52)
          .backgroundColor('#F2F4F7')
          .enabled(this.isDeviceOn() && this.device.getDisplayTargetTemp() > this.getMinTemp())
          .stateStyles({
            pressed: {
              .scale({ x: 0.94, y: 0.94 })
            },
            normal: {
              .scale({ x: 1, y: 1 })
            }
          })
          .animation({ duration: 150, curve: Curve.EaseOut })
          .onClick(() => {
            HapticUtil.tick();
            this.onStepTemp(-1);
          })

          Column({ space: 4 }) {
            Row({ space: 2 }) {
              Text(`${this.device.getDisplayTargetTemp()}`)
                .fontSize(72)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isDeviceOn() ? '#182431' : '#9AA3B2')
                .lineHeight(76)
                .contentTransition(this.tempTransition)

              Text(this.device.getTempUnitSymbol())
                .fontSize(22)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isDeviceOn() ? '#666666' : '#AEB6C2')
                .margin({ top: 10 })
            }
            .alignItems(VerticalAlign.Top)

            Text(this.isDeviceOn() ? `${this.getCurrentModeLabel()}设定温度` : '设备已关机')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isDeviceOn() ? this.getTheme().primaryColor : '#999999')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(22)
              .fontColor([this.isDeviceOn() && this.device.getDisplayTargetTemp() < this.getMaxTemp()
                ? '#182431' : '#CCCCCC'])
          }
          .width(52)
          .height(52)
          .backgroundColor('#F2F4F7')
          .enabled(this.isDeviceOn() && this.device.getDisplayTargetTemp() < this.getMaxTemp())
          .stateStyles({
            pressed: {
              .scale({ x: 0.94, y: 0.94 })
            },
            normal: {
              .scale({ x: 1, y: 1 })
            }
          })
          .animation({ duration: 150, curve: Curve.EaseOut })
          .onClick(() => {
            HapticUtil.tick();
            this.onStepTemp(1);
          })
        }
        .width('100%')
        .margin({ top: 20, bottom: 16 })
        .alignItems(VerticalAlign.Center)

        // 温度滑动条
        Slider({
          value: this.device.getDisplayTargetTemp(),
          min: this.getMinTemp(),
          max: this.getMaxTemp(),
          step: 1,
          style: SliderStyle.OutSet
        })
          .width('100%')
          .trackThickness(8)
          .trackColor('#EBEEF3')
          .selectedColor(this.isDeviceOn() ? this.getTheme().primaryColor : '#C2C9D4')
          .blockColor('#FFFFFF')
          .enabled(this.isDeviceOn())
          .opacity(this.isDeviceOn() ? 1 : 0.45)
          .onChange((val: number, mode: SliderChangeMode) => {
            this.handleSliderChange(val, mode);
          })

        Row() {
          Text(`${this.getMinTemp()}${this.device.getTempUnitSymbol()}`)
            .fontSize(11)
            .fontColor('#999999')
          Blank()
          Text(`${this.getMaxTemp()}${this.device.getTempUnitSymbol()}`)
            .fontSize(11)
            .fontColor('#999999')
        }
        .width('100%')
        .padding({ left: 6, right: 6 })
        .margin({ bottom: 18 })

        // 嵌入式底部电源胶囊开关
        Button({ type: ButtonType.Capsule }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.power'))
              .fontSize(18)
              .fontColor([this.isDeviceOn() ? '#E84026' : '#FFFFFF'])
            Text(this.isDeviceOn() ? '关闭空调' : '开启空调')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isDeviceOn() ? '#182431' : '#FFFFFF')
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
        }
        .width('100%')
        .height(46)
        .backgroundColor(this.isDeviceOn() ? '#F2F4F7' : '#0A59F7')
        .stateStyles({
          pressed: {
            .scale({ x: 0.98, y: 0.98 })
          },
          normal: {
            .scale({ x: 1, y: 1 })
          }
        })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          HapticUtil.tick();
          this.onTogglePower();
        })
      }
      .width('100%')
      .padding({ top: 18, bottom: 20, left: 18, right: 18 })
      .backgroundColor('#FFFFFF')
      .borderRadius(24)
      .shadow({ radius: 22, color: '#0A000000', offsetX: 0, offsetY: 6 })

      // 2. 运行模式卡片
      Column({ space: 12 }) {
        Row() {
          Text('运行模式')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#182431')
          Blank()
          Text(this.isDeviceOn() ? this.getCurrentModeLabel() : '未开启')
            .fontSize(13)
            .fontColor(this.isDeviceOn() ? this.getTheme().primaryColor : '#999999')
        }
        .width('100%')

        Row({ space: 8 }) {
          ForEach(MODE_OPTIONS, (item: ModeOption) => {
            Column({ space: 6 }) {
              SymbolGlyph(item.symbol)
                .fontSize(20)
                .fontColor([this.isDeviceOn() && this.device.mod === item.mode ? '#FFFFFF' : '#555555'])
              Text(item.label)
                .fontSize(12)
                .fontWeight(this.isDeviceOn() && this.device.mod === item.mode
                  ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.isDeviceOn() && this.device.mod === item.mode ? '#FFFFFF' : '#666666')
            }
            .layoutWeight(1)
            .padding({ top: 12, bottom: 12 })
            .borderRadius(14)
            .backgroundColor(this.isDeviceOn() && this.device.mod === item.mode
              ? this.getTheme().primaryColor : '#F5F7FA')
            .shadow(this.isDeviceOn() && this.device.mod === item.mode
              ? { radius: 10, color: '#24000000', offsetX: 0, offsetY: 3 }
              : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
            .enabled(this.isDeviceOn())
            .opacity(this.isDeviceOn() ? 1 : 0.45)
            .animation({ duration: 200, curve: Curve.EaseOut })
            .onClick(() => {
              HapticUtil.tick();
              this.onSelectMode(item.mode);
            })
          }, (item: ModeOption) => `${item.mode}`)
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(20)
      .shadow({ radius: 14, color: '#08000000', offsetX: 0, offsetY: 3 })

      // 3. 风速调节分段胶囊卡片
      Column({ space: 12 }) {
        Row() {
          Text('风速调节')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#182431')
          Blank()
          Text(this.isDeviceOn() ? this.getCurrentFanLabel() : '未开启')
            .fontSize(13)
            .fontColor(this.isDeviceOn() ? this.getTheme().primaryColor : '#999999')
        }
        .width('100%')

        Row({ space: 4 }) {
          ForEach(FAN_OPTIONS, (item: FanOption) => {
            Column() {
              Text(item.label)
                .fontSize(12)
                .fontWeight(this.device.wdSpd === item.speed ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.isDeviceOn() && this.device.wdSpd === item.speed
                  ? this.getTheme().primaryColor : '#666666')
                .maxLines(1)
            }
            .layoutWeight(1)
            .height(34)
            .justifyContent(FlexAlign.Center)
            .borderRadius(12)
            .backgroundColor(this.isDeviceOn() && this.device.wdSpd === item.speed
              ? '#FFFFFF' : Color.Transparent)
            .shadow(this.isDeviceOn() && this.device.wdSpd === item.speed
              ? { radius: 6, color: '#14000000', offsetX: 0, offsetY: 2 }
              : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
            .enabled(this.isDeviceOn())
            .animation({ duration: 180, curve: Curve.EaseOut })
            .onClick(() => {
              HapticUtil.tick();
              this.onSelectFanSpeed(item.speed);
            })
          }, (item: FanOption) => `${item.speed}`)
        }
        .width('100%')
        .padding(4)
        .backgroundColor('#F1F3F5')
        .borderRadius(16)
        .opacity(this.isDeviceOn() ? 1 : 0.45)
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(20)
      .shadow({ radius: 14, color: '#08000000', offsetX: 0, offsetY: 3 })
    }
    .width('100%')
  }
}
