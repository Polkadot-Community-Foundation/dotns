import { zeroAddress } from 'viem';
import type { Deployment, NetworkConfig, Unit } from './type';
import { normalize } from 'viem/ens';

export const SUPPORTED_NETWORKS: Record<number, NetworkConfig & Partial<Deployment>> = {
  420420422: {
    chainId: 420420422,
    chainName: 'Polkadot Hub TestNet',
    nativeCurrency: {
      name: 'Paseo',
      symbol: 'PAS',
      decimals: 18,
    },
    rpcUrls: ['https://testnet-passet-hub-eth-rpc.polkadot.io'],
    blockExplorerUrls: ['https://blockscout-passet-hub.parity-testnet.parity.io/'],
    ensRegistry: '0xe2fB8d393D3A257F709A3a96d234950d00626fa5',
    baseRegistrar: '0xaD5EE06411D18A1Cd1051ED87eAebEE9CD154C64',
    registrarController: '0xfc9FC0f9C67271a84d5Ee1Bd6f14D8527533Bb64',
    bulkRenewal: '0x092b689ed3c08F194EbcB7Fcc7c63d482AaEf2c9',
    publicResolver: '0x41df0d983C94ff742811649278faAa7fBfeb923D',
    oracle: '0x313d4B1c0e4C487A61da6F8ebf00AA01f56be145',
    storeFactory: '0xD1ba8f9dD2218859b4113Fb7eF5C2Ac6D46794f4',
    dotnsRegistrar: '0xa312DA532a0da1F843b09a0172611c2538944b16',
    multicall: '0xe83DCEE30d0b5848D1e74aDb638F3357f9E4766B',
  },
};

export const SPECIAL_CHAR_REGEX = /[&^%$*+~=`{}|\\<>\/\[\]"]+/;
export const TOKEN_UNIT = 'PAS';
export const DEFAULT_NETWORK_ID = 420420420;
export const BLOCK_EXPLORER = 'https://blockscout-passet-hub.parity-testnet.parity.io/';
export function getFirstDeployedNetwork(): (NetworkConfig & Partial<Deployment>) | undefined {
  return Object.values(SUPPORTED_NETWORKS).find(network => network.ensRegistry !== zeroAddress);
}

export function toFixed(value: string, decimals = 8): string {
  const num = parseFloat(value);
  return num.toFixed(decimals);
}

export function addPercentage(value: bigint, percent: number): bigint {
  return (value * BigInt(100 + percent)) / 100n;
}

export function generateDummyDomains(count = 20): string[] {
  const tlds = ['dot', 'eth', 'xyz', 'dao'];
  const secondLevel = ['alpha', 'beta', 'gamma', 'delta', 'omega', 'kappa'];
  const prefixes = ['user', 'dev', 'team', 'node', 'player', 'agent'];

  const domains: string[] = [];

  for (let i = 0; i < count; i++) {
    const level = Math.floor(Math.random() * 3) + 1;
    const tld = tlds[Math.floor(Math.random() * tlds.length)];
    const name = secondLevel[Math.floor(Math.random() * secondLevel.length)];
    const prefix = prefixes[Math.floor(Math.random() * prefixes.length)];

    if (level === 1) {
      domains.push(`${tld}`);
    } else if (level === 2) {
      domains.push(`${name}.${tld}`);
    } else {
      domains.push(`${prefix}.${name}.${tld}`);
    }
  }

  return [...new Set(domains)];
}

export function getSecondsForUnit(unit: Unit): bigint {
  switch (unit) {
    case 'minutes':
      return 60n;
    case 'days':
      return 60n * 60n * 24n;
    case 'months':
      return 60n * 60n * 24n * 30n;
    case 'years':
      return 60n * 60n * 24n * 365n;
    default:
      return 60n;
  }
}

export function formatTimestamp(ts: bigint | string | null): string {
  if (!ts) return '—';
  try {
    const num = typeof ts === 'bigint' ? Number(ts) : parseInt(ts);
    const date = new Date(num * 1000);
    return date.toLocaleString('en-GB', {
      year: 'numeric',
      month: 'short',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  } catch {
    return '—';
  }
}

export function validateENSName(label: string, minLabelLength = 3, maxLabelLength = 63): string {
  if (!label || typeof label !== 'string') {
    throw new Error('Label must be a non-empty string');
  }

  const normalized = normalize(label);

  if (normalized.length < minLabelLength) {
    throw new Error(`Label too short: minimum is ${minLabelLength}, got ${normalized.length}`);
  }
  if (normalized.length > maxLabelLength) {
    throw new Error(`Label too long: maximum is ${maxLabelLength}, got ${normalized.length}`);
  }

  if (normalized.startsWith('-') || normalized.endsWith('-')) {
    throw new Error('Label must not start or end with a hyphen');
  }
  if (normalized.length >= 4 && normalized.slice(2, 4) === '--') {
    throw new Error("Label must not contain '--' at position 3–4");
  }

  if (SPECIAL_CHAR_REGEX.test(normalized)) {
    throw new Error('Label contains disallowed special characters');
  }

  const asciiAllowedRegex = /^[a-z0-9\-]+$/;
  if (!asciiAllowedRegex.test(normalized)) {
    throw new Error(
      'Label contains characters outside allowed ASCII (a-z, 0-9, hyphen) or allowed Unicode'
    );
  }

  return normalized;
}

export function normalizeDomainName(name: string): string {
  return name.replace(/\.dot$/, '');
}
