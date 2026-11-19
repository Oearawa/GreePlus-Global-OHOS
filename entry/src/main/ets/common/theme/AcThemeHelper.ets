import {
  GreeAcMode,
  GreeOnlineChannel,
  GreePowerState
} from '../constants/GreeConstants';

/**
 * Context-aware HarmonyOS Design color palette mapped from AC power & mode.
 */
export interface AcModeThemePalette {
  isOn: boolean;
  primaryColor: string;
  glowTopColor: string;
  softBgColor: string;
  borderColor: string;
  badgeTextColor: string;
  sliderTrackColor: string;
  pageBgBaseColor: string;
  modeSymbol: Resource;
}

const THEME_COOL: AcModeThemePalette = {
  isOn: true,
  primaryColor: '#0A59F7',
  glowTopColor: '#EBF3FF',
  softBgColor: '#EDF4FF',
  borderColor: '#CFE2FF',
  badgeTextColor: '#0A59F7',
  sliderTrackColor: '#D6E6FF',
  pageBgBaseColor: '#F1F3F5',
  modeSymbol: $r('sys.symbol.snowflake')
};

const THEME_HEAT: AcModeThemePalette = {
  isOn: true,
  primaryColor: '#FA6400',
  glowTopColor: '#FFF2EC',
  softBgColor: '#FFF3EB',
  borderColor: '#FFD9C2',
  badgeTextColor: '#E84026',
  sliderTrackColor: '#FFE0CC',
  pageBgBaseColor: '#F1F3F5',
  modeSymbol: $r('sys.symbol.flame_fill')
};

const THEME_DRY: AcModeThemePalette = {
  isOn: true,
  primaryColor: '#008A60',
  glowTopColor: '#E8F8F3',
  softBgColor: '#EAF8F3',
  borderColor: '#C2EBDD',
  badgeTextColor: '#008A60',
  sliderTrackColor: '#C7EFE1',
  pageBgBaseColor: '#F1F3F5',
  modeSymbol: $r('sys.symbol.drop_fill')
};

const THEME_FAN: AcModeThemePalette = {
  isOn: true,
  primaryColor: '#007DFF',
  glowTopColor: '#EDF6FF',
  softBgColor: '#EEF7FF',
  borderColor: '#CCE6FF',
  badgeTextColor: '#007DFF',
  sliderTrackColor: '#CCE6FF',
  pageBgBaseColor: '#F1F3F5',
  modeSymbol: $r('sys.symbol.wind')
};

const THEME_AUTO: AcModeThemePalette = {
  isOn: true,
  primaryColor: '#4B4EFC',
  glowTopColor: '#F0F0FF',
  softBgColor: '#F1F1FF',
  borderColor: '#D6D7FF',
  badgeTextColor: '#4B4EFC',
  sliderTrackColor: '#DBD8FF',
  pageBgBaseColor: '#F1F3F5',
  modeSymbol: $r('sys.symbol.wand_and_stars')
};

const THEME_OFF: AcModeThemePalette = {
  isOn: false,
  primaryColor: '#8A94A6',
  glowTopColor: '#F1F3F5',
  softBgColor: '#F1F3F5',
  borderColor: '#E5E8EF',
  badgeTextColor: '#6E7787',
  sliderTrackColor: '#E2E6ED',
  pageBgBaseColor: '#F1F3F5',
  modeSymbol: $r('sys.symbol.power')
};

export function getAcModeTheme(pow: number, mod: number): AcModeThemePalette {
  if (pow !== GreePowerState.ON) {
    return THEME_OFF;
  }
  switch (mod) {
    case GreeAcMode.HEAT:
      return THEME_HEAT;
    case GreeAcMode.DRY:
      return THEME_DRY;
    case GreeAcMode.FAN:
      return THEME_FAN;
    case GreeAcMode.AUTO:
      return THEME_AUTO;
    case GreeAcMode.COOL:
    default:
      return THEME_COOL;
  }
}

export function getModeSymbol(mod: number): Resource {
  switch (mod) {
    case GreeAcMode.HEAT:
      return $r('sys.symbol.flame_fill');
    case GreeAcMode.DRY:
      return $r('sys.symbol.drop_fill');
    case GreeAcMode.FAN:
      return $r('sys.symbol.wind');
    case GreeAcMode.AUTO:
      return $r('sys.symbol.wand_and_stars');
    case GreeAcMode.COOL:
    default:
      return $r('sys.symbol.snowflake');
  }
}

export function formatShortChannelText(channel: GreeOnlineChannel): string {
  switch (channel) {
    case GreeOnlineChannel.LAN:
      return '本地';
    case GreeOnlineChannel.CLOUD:
      return '云端';
    case GreeOnlineChannel.OFFLINE:
    default:
      return '离线';
  }
}

export function formatControlNavChannelText(channel: GreeOnlineChannel): string {
  switch (channel) {
    case GreeOnlineChannel.LAN:
      return '本地直连';
    case GreeOnlineChannel.CLOUD:
      return '云端在线';
    case GreeOnlineChannel.OFFLINE:
    default:
      return '设备离线';
  }
}

export function getChannelDotColor(channel: GreeOnlineChannel): string {
  switch (channel) {
    case GreeOnlineChannel.LAN:
      return '#17A94E';
    case GreeOnlineChannel.CLOUD:
      return '#0A59F7';
    case GreeOnlineChannel.OFFLINE:
    default:
      return '#9CA3AF';
  }
}

export function getChannelPillBg(channel: GreeOnlineChannel): string {
  switch (channel) {
    case GreeOnlineChannel.LAN:
      return '#EAF9F0';
    case GreeOnlineChannel.CLOUD:
      return '#ECF3FF';
    case GreeOnlineChannel.OFFLINE:
    default:
      return '#F2F4F7';
  }
}
