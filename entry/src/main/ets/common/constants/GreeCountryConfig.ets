import { GREE_MQTT_TLS_PORT } from './GreeConstants';

/**
 * Overseas Gree+ country/region catalog mapped 1:1 to live verified regional REST & MQTT servers
 * (East/South Asia uses `mqtt-hk.gree.com`, verified via DNS & TLS handshake).
 */
export interface GreeCountryItem {
  code: string;
  nameZh: string;
  nameEn: string;
  pinyin: string;
  pinyinInitials: string;
  initial: string;
  dialCode: string;
  clusterId: string;
  defaultApiBaseUrl: string;
  defaultMqttHost: string;
  defaultMqttPort: number;
}

export interface CountryLetterGroup {
  initial: string;
  items: GreeCountryItem[];
}

export interface GreeRegionalCluster {
  clusterId: string;
  apiBaseUrl: string;
  mqttHost: string;
  mqttPort: number;
}

export const DEFAULT_COUNTRY_CODE: string = '';

export const GREE_ALL_CLOUD_CLUSTERS: GreeRegionalCluster[] = [
  {
    clusterId: 'East South Asia',
    apiBaseUrl: 'https://hkgrih.gree.com',
    mqttHost: 'mqtt-hk.gree.com',
    mqttPort: GREE_MQTT_TLS_PORT
  },
  {
    clusterId: 'China Mainland',
    apiBaseUrl: 'https://grih.gree.com',
    mqttHost: 'mqtt.gree.com',
    mqttPort: GREE_MQTT_TLS_PORT
  },
  {
    clusterId: 'North American',
    apiBaseUrl: 'https://nagrih.gree.com',
    mqttHost: 'mqtt-na.gree.com',
    mqttPort: GREE_MQTT_TLS_PORT
  },
  {
    clusterId: 'Europe',
    apiBaseUrl: 'https://eugrih.gree.com',
    mqttHost: 'mqtt-eu.gree.com',
    mqttPort: GREE_MQTT_TLS_PORT
  },
  {
    clusterId: 'Australia',
    apiBaseUrl: 'https://augrih.gree.com',
    mqttHost: 'mqtt-au.gree.com',
    mqttPort: GREE_MQTT_TLS_PORT
  },
  {
    clusterId: 'Middle East',
    apiBaseUrl: 'https://megrih.gree.com',
    mqttHost: 'mqtt-me.gree.com',
    mqttPort: GREE_MQTT_TLS_PORT
  },
  {
    clusterId: 'India',
    apiBaseUrl: 'https://ingrih.gree.com',
    mqttHost: 'mqtt-in.gree.com',
    mqttPort: GREE_MQTT_TLS_PORT
  },
  {
    clusterId: 'Latin American',
    apiBaseUrl: 'https://lagrih.gree.com',
    mqttHost: 'mqtt-na.gree.com',
    mqttPort: GREE_MQTT_TLS_PORT
  },
  {
    clusterId: 'South American',
    apiBaseUrl: 'https://sagrih.gree.com',
    mqttHost: 'mqtt-sa.gree.com',
    mqttPort: GREE_MQTT_TLS_PORT
  },
  {
    clusterId: 'Russia',
    apiBaseUrl: 'https://rugrih.gree.com',
    mqttHost: 'mqtt-ru.gree.com',
    mqttPort: GREE_MQTT_TLS_PORT
  }
];

const RAW_COUNTRY_LIST: GreeCountryItem[] = [
  {
    code: 'AE',
    nameZh: '阿联酋',
    nameEn: 'United Arab Emirates',
    pinyin: 'alianqiu',
    pinyinInitials: 'alq',
    initial: 'A',
    dialCode: '+971',
    clusterId: 'Middle East',
    defaultApiBaseUrl: 'https://megrih.gree.com',
    defaultMqttHost: 'mqtt-me.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'AU',
    nameZh: '澳大利亚',
    nameEn: 'Australia',
    pinyin: 'aodaliya',
    pinyinInitials: 'adly',
    initial: 'A',
    dialCode: '+61',
    clusterId: 'Australia',
    defaultApiBaseUrl: 'https://augrih.gree.com',
    defaultMqttHost: 'mqtt-au.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'BR',
    nameZh: '巴西',
    nameEn: 'Brazil',
    pinyin: 'baxi',
    pinyinInitials: 'bx',
    initial: 'B',
    dialCode: '+55',
    clusterId: 'South American',
    defaultApiBaseUrl: 'https://sagrih.gree.com',
    defaultMqttHost: 'mqtt-sa.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'PL',
    nameZh: '波兰',
    nameEn: 'Poland',
    pinyin: 'bolan',
    pinyinInitials: 'bl',
    initial: 'B',
    dialCode: '+48',
    clusterId: 'Europe',
    defaultApiBaseUrl: 'https://eugrih.gree.com',
    defaultMqttHost: 'mqtt-eu.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'DE',
    nameZh: '德国',
    nameEn: 'Germany',
    pinyin: 'deguo',
    pinyinInitials: 'dg',
    initial: 'D',
    dialCode: '+49',
    clusterId: 'Europe',
    defaultApiBaseUrl: 'https://eugrih.gree.com',
    defaultMqttHost: 'mqtt-eu.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'RU',
    nameZh: '俄罗斯',
    nameEn: 'Russia',
    pinyin: 'eluosi',
    pinyinInitials: 'els',
    initial: 'E',
    dialCode: '+7',
    clusterId: 'Russia',
    defaultApiBaseUrl: 'https://rugrih.gree.com',
    defaultMqttHost: 'mqtt-ru.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'FR',
    nameZh: '法国',
    nameEn: 'France',
    pinyin: 'faguo',
    pinyinInitials: 'fg',
    initial: 'F',
    dialCode: '+33',
    clusterId: 'Europe',
    defaultApiBaseUrl: 'https://eugrih.gree.com',
    defaultMqttHost: 'mqtt-eu.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'PH',
    nameZh: '菲律宾',
    nameEn: 'Philippines',
    pinyin: 'feilvbin',
    pinyinInitials: 'flb',
    initial: 'F',
    dialCode: '+63',
    clusterId: 'East South Asia',
    defaultApiBaseUrl: 'https://hkgrih.gree.com',
    defaultMqttHost: 'mqtt-hk.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'KR',
    nameZh: '韩国',
    nameEn: 'South Korea',
    pinyin: 'hanguo',
    pinyinInitials: 'hg',
    initial: 'H',
    dialCode: '+82',
    clusterId: 'East South Asia',
    defaultApiBaseUrl: 'https://hkgrih.gree.com',
    defaultMqttHost: 'mqtt-hk.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'NL',
    nameZh: '荷兰',
    nameEn: 'Netherlands',
    pinyin: 'helan',
    pinyinInitials: 'hl',
    initial: 'H',
    dialCode: '+31',
    clusterId: 'Europe',
    defaultApiBaseUrl: 'https://eugrih.gree.com',
    defaultMqttHost: 'mqtt-eu.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'CA',
    nameZh: '加拿大',
    nameEn: 'Canada',
    pinyin: 'jianada',
    pinyinInitials: 'jnd',
    initial: 'J',
    dialCode: '+1',
    clusterId: 'North American',
    defaultApiBaseUrl: 'https://nagrih.gree.com',
    defaultMqttHost: 'mqtt-na.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'KH',
    nameZh: '柬埔寨',
    nameEn: 'Cambodia',
    pinyin: 'jianpuzhai',
    pinyinInitials: 'jpz',
    initial: 'J',
    dialCode: '+855',
    clusterId: 'East South Asia',
    defaultApiBaseUrl: 'https://hkgrih.gree.com',
    defaultMqttHost: 'mqtt-hk.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'LA',
    nameZh: '老挝',
    nameEn: 'Laos',
    pinyin: 'laowo',
    pinyinInitials: 'lw',
    initial: 'L',
    dialCode: '+856',
    clusterId: 'East South Asia',
    defaultApiBaseUrl: 'https://hkgrih.gree.com',
    defaultMqttHost: 'mqtt-hk.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'MY',
    nameZh: '马来西亚',
    nameEn: 'Malaysia',
    pinyin: 'malaixiya',
    pinyinInitials: 'mlxy',
    initial: 'M',
    dialCode: '+60',
    clusterId: 'East South Asia',
    defaultApiBaseUrl: 'https://hkgrih.gree.com',
    defaultMqttHost: 'mqtt-hk.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'US',
    nameZh: '美国',
    nameEn: 'United States',
    pinyin: 'meiguo',
    pinyinInitials: 'mg',
    initial: 'M',
    dialCode: '+1',
    clusterId: 'North American',
    defaultApiBaseUrl: 'https://nagrih.gree.com',
    defaultMqttHost: 'mqtt-na.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'MM',
    nameZh: '缅甸',
    nameEn: 'Myanmar',
    pinyin: 'miandian',
    pinyinInitials: 'md',
    initial: 'M',
    dialCode: '+95',
    clusterId: 'East South Asia',
    defaultApiBaseUrl: 'https://hkgrih.gree.com',
    defaultMqttHost: 'mqtt-hk.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'MX',
    nameZh: '墨西哥',
    nameEn: 'Mexico',
    pinyin: 'moxige',
    pinyinInitials: 'mxg',
    initial: 'M',
    dialCode: '+52',
    clusterId: 'Latin American',
    defaultApiBaseUrl: 'https://lagrih.gree.com',
    defaultMqttHost: 'mqtt-na.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'ZA',
    nameZh: '南非',
    nameEn: 'South Africa',
    pinyin: 'nanfei',
    pinyinInitials: 'nf',
    initial: 'N',
    dialCode: '+27',
    clusterId: 'Europe',
    defaultApiBaseUrl: 'https://eugrih.gree.com',
    defaultMqttHost: 'mqtt-eu.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'JP',
    nameZh: '日本',
    nameEn: 'Japan',
    pinyin: 'riben',
    pinyinInitials: 'rb',
    initial: 'R',
    dialCode: '+81',
    clusterId: 'East South Asia',
    defaultApiBaseUrl: 'https://hkgrih.gree.com',
    defaultMqttHost: 'mqtt-hk.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'SA',
    nameZh: '沙特阿拉伯',
    nameEn: 'Saudi Arabia',
    pinyin: 'shatealabo',
    pinyinInitials: 'stalb',
    initial: 'S',
    dialCode: '+966',
    clusterId: 'Middle East',
    defaultApiBaseUrl: 'https://megrih.gree.com',
    defaultMqttHost: 'mqtt-me.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'TH',
    nameZh: '泰国',
    nameEn: 'Thailand',
    pinyin: 'taiguo',
    pinyinInitials: 'tg',
    initial: 'T',
    dialCode: '+66',
    clusterId: 'East South Asia',
    defaultApiBaseUrl: 'https://hkgrih.gree.com',
    defaultMqttHost: 'mqtt-hk.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'TR',
    nameZh: '土耳其',
    nameEn: 'Turkey',
    pinyin: 'tuerqi',
    pinyinInitials: 'teq',
    initial: 'T',
    dialCode: '+90',
    clusterId: 'Europe',
    defaultApiBaseUrl: 'https://eugrih.gree.com',
    defaultMqttHost: 'mqtt-eu.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'BN',
    nameZh: '文莱',
    nameEn: 'Brunei',
    pinyin: 'wenlai',
    pinyinInitials: 'wl',
    initial: 'W',
    dialCode: '+673',
    clusterId: 'East South Asia',
    defaultApiBaseUrl: 'https://hkgrih.gree.com',
    defaultMqttHost: 'mqtt-hk.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'ES',
    nameZh: '西班牙',
    nameEn: 'Spain',
    pinyin: 'xibanya',
    pinyinInitials: 'xby',
    initial: 'X',
    dialCode: '+34',
    clusterId: 'Europe',
    defaultApiBaseUrl: 'https://eugrih.gree.com',
    defaultMqttHost: 'mqtt-eu.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'GR',
    nameZh: '希腊',
    nameEn: 'Greece',
    pinyin: 'xila',
    pinyinInitials: 'xl',
    initial: 'X',
    dialCode: '+30',
    clusterId: 'Europe',
    defaultApiBaseUrl: 'https://eugrih.gree.com',
    defaultMqttHost: 'mqtt-eu.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'SG',
    nameZh: '新加坡',
    nameEn: 'Singapore',
    pinyin: 'xinjiapo',
    pinyinInitials: 'xjp',
    initial: 'X',
    dialCode: '+65',
    clusterId: 'East South Asia',
    defaultApiBaseUrl: 'https://hkgrih.gree.com',
    defaultMqttHost: 'mqtt-hk.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'NZ',
    nameZh: '新西兰',
    nameEn: 'New Zealand',
    pinyin: 'xinxilan',
    pinyinInitials: 'xxl',
    initial: 'X',
    dialCode: '+64',
    clusterId: 'Australia',
    defaultApiBaseUrl: 'https://augrih.gree.com',
    defaultMqttHost: 'mqtt-au.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'IT',
    nameZh: '意大利',
    nameEn: 'Italy',
    pinyin: 'yidali',
    pinyinInitials: 'ydl',
    initial: 'Y',
    dialCode: '+39',
    clusterId: 'Europe',
    defaultApiBaseUrl: 'https://eugrih.gree.com',
    defaultMqttHost: 'mqtt-eu.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'IN',
    nameZh: '印度',
    nameEn: 'India',
    pinyin: 'yindu',
    pinyinInitials: 'yd',
    initial: 'Y',
    dialCode: '+91',
    clusterId: 'India',
    defaultApiBaseUrl: 'https://ingrih.gree.com',
    defaultMqttHost: 'mqtt-in.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'ID',
    nameZh: '印度尼西亚',
    nameEn: 'Indonesia',
    pinyin: 'yindunixiya',
    pinyinInitials: 'ydnxy',
    initial: 'Y',
    dialCode: '+62',
    clusterId: 'East South Asia',
    defaultApiBaseUrl: 'https://hkgrih.gree.com',
    defaultMqttHost: 'mqtt-hk.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'GB',
    nameZh: '英国',
    nameEn: 'United Kingdom',
    pinyin: 'yingguo',
    pinyinInitials: 'yg',
    initial: 'Y',
    dialCode: '+44',
    clusterId: 'Europe',
    defaultApiBaseUrl: 'https://eugrih.gree.com',
    defaultMqttHost: 'mqtt-eu.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'VN',
    nameZh: '越南',
    nameEn: 'Vietnam',
    pinyin: 'yuenan',
    pinyinInitials: 'yn',
    initial: 'Y',
    dialCode: '+84',
    clusterId: 'East South Asia',
    defaultApiBaseUrl: 'https://hkgrih.gree.com',
    defaultMqttHost: 'mqtt-hk.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  },
  {
    code: 'CN',
    nameZh: '中国大陆',
    nameEn: 'China Mainland',
    pinyin: 'zhongguodalu',
    pinyinInitials: 'zgdl',
    initial: 'Z',
    dialCode: '+86',
    clusterId: 'China Mainland',
    defaultApiBaseUrl: 'https://grih.gree.com',
    defaultMqttHost: 'mqtt.gree.com',
    defaultMqttPort: GREE_MQTT_TLS_PORT
  }
];

function compareCountryAlpha(a: GreeCountryItem, b: GreeCountryItem): number {
  const initCmp: number = a.initial.localeCompare(b.initial);
  if (initCmp !== 0) {
    return initCmp;
  }
  return a.pinyin.localeCompare(b.pinyin);
}

export const GREE_COUNTRY_LIST: GreeCountryItem[] = RAW_COUNTRY_LIST.slice().sort(compareCountryAlpha);

export function getCountryByCode(code: string): GreeCountryItem | null {
  const upper: string = code.trim().toUpperCase();
  if (upper.length === 0) {
    return null;
  }
  for (let i: number = 0; i < GREE_COUNTRY_LIST.length; i++) {
    if (GREE_COUNTRY_LIST[i].code === upper) {
      return GREE_COUNTRY_LIST[i];
    }
  }
  return null;
}

export function getCountryGroups(): CountryLetterGroup[] {
  const groups: CountryLetterGroup[] = [];
  for (let i: number = 0; i < GREE_COUNTRY_LIST.length; i++) {
    const item: GreeCountryItem = GREE_COUNTRY_LIST[i];
    const lastGroup: CountryLetterGroup | null = groups.length > 0 ? groups[groups.length - 1] : null;
    if (lastGroup !== null && lastGroup.initial === item.initial) {
      lastGroup.items.push(item);
    } else {
      groups.push({
        initial: item.initial,
        items: [item]
      });
    }
  }
  return groups;
}

export function getCountryIndexLetters(): string[] {
  const groups: CountryLetterGroup[] = getCountryGroups();
  const letters: string[] = [];
  for (let i: number = 0; i < groups.length; i++) {
    letters.push(groups[i].initial);
  }
  return letters;
}

export function isFuzzyMatch(target: string, pattern: string): boolean {
  if (pattern.length === 0) {
    return true;
  }
  if (pattern.length > target.length) {
    return false;
  }
  let pIdx: number = 0;
  for (let tIdx: number = 0; tIdx < target.length && pIdx < pattern.length; tIdx++) {
    if (target.charAt(tIdx) === pattern.charAt(pIdx)) {
      pIdx++;
    }
  }
  return pIdx === pattern.length;
}

interface ScoredCountryItem {
  item: GreeCountryItem;
  score: number;
}

function scoreCountryMatch(item: GreeCountryItem, cleanQuery: string, noPlusQuery: string): number {
  const codeLower: string = item.code.toLowerCase();
  const dialWithPlus: string = item.dialCode.toLowerCase();
  const dialNoPlus: string = dialWithPlus.startsWith('+') ? dialWithPlus.slice(1) : dialWithPlus;
  const zhLower: string = item.nameZh.toLowerCase();
  const enLower: string = item.nameEn.toLowerCase();
  const enCompact: string = enLower.replace(/\s+/g, '');
  const pyLower: string = item.pinyin.toLowerCase();
  const pyInitLower: string = item.pinyinInitials.toLowerCase();

  // 1. 精确匹配（最高优先级）
  if (
    codeLower === noPlusQuery ||
    dialWithPlus === cleanQuery ||
    dialNoPlus === noPlusQuery ||
    zhLower === cleanQuery ||
    enLower === cleanQuery ||
    enCompact === noPlusQuery ||
    pyLower === noPlusQuery ||
    pyInitLower === noPlusQuery
  ) {
    return 1000;
  }

  // 2. 前缀匹配
  if (
    zhLower.startsWith(cleanQuery) ||
    pyLower.startsWith(noPlusQuery) ||
    pyInitLower.startsWith(noPlusQuery) ||
    enLower.startsWith(cleanQuery) ||
    enCompact.startsWith(noPlusQuery) ||
    codeLower.startsWith(noPlusQuery) ||
    dialNoPlus.startsWith(noPlusQuery)
  ) {
    return 700;
  }

  // 3. 子串包含匹配
  if (
    zhLower.includes(cleanQuery) ||
    pyLower.includes(noPlusQuery) ||
    pyInitLower.includes(noPlusQuery) ||
    enLower.includes(cleanQuery) ||
    enCompact.includes(noPlusQuery) ||
    codeLower.includes(noPlusQuery) ||
    dialNoPlus.includes(noPlusQuery)
  ) {
    return 400;
  }

  // 4. 有序模糊子序列匹配（Fuzzy Subsequence）
  if (
    noPlusQuery.length >= 2 && (
      isFuzzyMatch(zhLower, noPlusQuery) ||
      isFuzzyMatch(pyLower, noPlusQuery) ||
      isFuzzyMatch(pyInitLower, noPlusQuery) ||
      isFuzzyMatch(enCompact, noPlusQuery)
    )
  ) {
    return 150;
  }

  return 0;
}

export function searchCountries(query: string): GreeCountryItem[] {
  const cleanQuery: string = query.trim().toLowerCase().replace(/\s+/g, ' ');
  const noPlusQuery: string = cleanQuery.replace(/[\s+]/g, '');
  if (noPlusQuery.length === 0) {
    return GREE_COUNTRY_LIST;
  }

  const scored: ScoredCountryItem[] = [];
  for (let i: number = 0; i < GREE_COUNTRY_LIST.length; i++) {
    const item: GreeCountryItem = GREE_COUNTRY_LIST[i];
    const score: number = scoreCountryMatch(item, cleanQuery, noPlusQuery);
    if (score > 0) {
      scored.push({ item: item, score: score });
    }
  }

  scored.sort((a: ScoredCountryItem, b: ScoredCountryItem): number => {
    if (b.score !== a.score) {
      return b.score - a.score;
    }
    return compareCountryAlpha(a.item, b.item);
  });

  const results: GreeCountryItem[] = [];
  for (let i: number = 0; i < scored.length; i++) {
    results.push(scored[i].item);
  }
  return results;
}

export function getClusterDefaultMqttHost(apiBaseUrl: string): string {
  const normalizedApi: string = apiBaseUrl.trim().toLowerCase();
  for (let i: number = 0; i < GREE_ALL_CLOUD_CLUSTERS.length; i++) {
    if (GREE_ALL_CLOUD_CLUSTERS[i].apiBaseUrl.toLowerCase() === normalizedApi) {
      return GREE_ALL_CLOUD_CLUSTERS[i].mqttHost;
    }
  }
  return 'mqtt-hk.gree.com';
}

/**
 * Migrates legacy non-existent hostnames saved by earlier builds (`mqtt-as.gree.com` / `mqtt-la.gree.com`)
 * to live DNS-verified brokers (`mqtt-hk.gree.com` / `mqtt-na.gree.com`) while preserving real dynamic hosts.
 */
export function normalizeMqttBrokerHost(rawHost: string, apiBaseUrl: string): string {
  const clean: string = rawHost.trim().toLowerCase();
  if (clean.length === 0) {
    return apiBaseUrl.trim().length > 0 ? getClusterDefaultMqttHost(apiBaseUrl) : '';
  }
  if (clean === 'mqtt-as.gree.com') {
    return 'mqtt-hk.gree.com';
  }
  if (clean === 'mqtt-la.gree.com') {
    return 'mqtt-na.gree.com';
  }
  return rawHost.trim();
}
