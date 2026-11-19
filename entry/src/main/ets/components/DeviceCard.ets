import {
  GreePowerState
} from '../common/constants/GreeConstants';
import {
  AcModeThemePalette,
  formatShortChannelText,
  getAcModeTheme,
  getChannelDotColor,
  getChannelPillBg
} from '../common/theme/AcThemeHelper';
import { HapticUtil } from '../common/utils/HapticUtil';
import {
  formatFanSpeedLabel,
  formatModeLabel,
  GreeDeviceModel
} from '../model/GreeDeviceModel';

/**
 * HarmonyOS Design compliant home device card displaying clean device status,
 * context-aware mode accent colors, numeric temperature transition, and circular power toggle.
 */
@ComponentV2
export struct DeviceCard {
  @Param @Require device: GreeDeviceModel;
  @Param onOpenControl: () => void = (): void => {};
  @Param onTogglePower: () => void = (): void => {};

  private readonly tempTransition: ContentTransition = new NumericTextTransition({
    flipDirection: FlipDirection.DOWN,
    enableBlur: false
  });

  private buildTelemetrySubtitle(): string {
    const indoorText: string = `室温 ${this.device.getDisplayIndoorTemp()}${this.device.getTempUnitSymbol()}`;
    if (this.device.pow !== GreePowerState.ON) {
      return indoorText;
    }
    return `${formatModeLabel(this.device.mod)} · ${formatFanSpeedLabel(this.device.wdSpd)} · ${indoorText}`;
  }

  private getTheme(): AcModeThemePalette {
    return getAcModeTheme(this.device.pow, this.device.mod);
  }

  build() {
    Column({ space: 16 }) {
      // Top Row: Mode Icon Badge + Device Name + Minimalist Online Dot Pill
      Row({ space: 10 }) {
        Stack() {
          SymbolGlyph(this.getTheme().modeSymbol)
            .fontSize(20)
            .fontColor([this.getTheme().primaryColor])
        }
        .width(40)
        .height(40)
        .borderRadius(12)
        .backgroundColor(this.getTheme().softBgColor)
        .alignContent(Alignment.Center)

        Text(this.device.name)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#182431')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Row({ space: 5 }) {
          Circle({ width: 6, height: 6 })
            .fill(getChannelDotColor(this.device.onlineChannel))
          Text(formatShortChannelText(this.device.onlineChannel))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4E5969')
        }
        .padding({ left: 9, right: 9, top: 4, bottom: 4 })
        .borderRadius(999)
        .backgroundColor(getChannelPillBg(this.device.onlineChannel))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // Bottom Row: Temperature/State + Circular Independent Power Button
      Row() {
        Column({ space: 4 }) {
          if (this.device.pow === GreePowerState.ON) {
            Row({ space: 2 }) {
              Text(`${this.device.getDisplayTargetTemp()}`)
                .fontSize(34)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.getTheme().primaryColor)
                .contentTransition(this.tempTransition)
              Text(this.device.getTempUnitSymbol())
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.getTheme().primaryColor)
                .margin({ top: 6 })
            }
            .alignItems(VerticalAlign.Top)
          } else {
            Text('已关机')
              .fontSize(22)
              .fontWeight(FontWeight.Medium)
              .fontColor('#8A94A6')
          }

          Text(this.buildTelemetrySubtitle())
            .fontSize(12)
            .fontColor('#6E7787')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.power'))
            .fontSize(20)
            .fontColor([this.device.pow === GreePowerState.ON ? '#FFFFFF' : '#5C6675'])
        }
        .width(44)
        .height(44)
        .backgroundColor(this.device.pow === GreePowerState.ON ? this.getTheme().primaryColor : '#F1F3F5')
        .shadow(this.device.pow === GreePowerState.ON
          ? { radius: 10, color: '#260A59F7', offsetX: 0, offsetY: 4 }
          : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
        .onClick(() => {
          HapticUtil.tick();
          this.onTogglePower();
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
    .border({
      width: 0.8,
      color: this.device.pow === GreePowerState.ON ? this.getTheme().borderColor : '#ECEFF3'
    })
    .shadow({
      radius: 14,
      color: '#0D000000',
      offsetX: 0,
      offsetY: 4
    })
    .stateStyles({
      normal: {
        .scale({ x: 1, y: 1 })
      },
      pressed: {
        .scale({ x: 0.98, y: 0.98 })
      }
    })
    .animation({ duration: 180, curve: Curve.EaseOut })
    .onClick(() => {
      this.onOpenControl();
    })
  }
}
