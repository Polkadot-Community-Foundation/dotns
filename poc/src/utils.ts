import { formatUnits, keccak256, zeroAddress } from 'viem';
import type { Deployment, NetworkConfig, Unit } from './type';
import { normalize } from 'viem/ens';
import { hexToU8a, isHex } from '@polkadot/util';
import type { Paseo } from '@polkadot-api/descriptors';
import { type TypedApi, type SS58String, AccountId, Binary } from 'polkadot-api';
import type { PaseoAssetHubApi } from '@dedot/chaintypes';
import type { DedotClient } from 'dedot';
import { decodeAddress, encodeAddress } from '@polkadot/util-crypto';

export const SUPPORTED_NETWORKS: Record<number, NetworkConfig & Partial<Deployment>> = {
  420420422: {
    chainId: 420420422,
    chainName: 'Polkadot Hub TestNet',
    nativeCurrency: {
      name: 'Paseo',
      symbol: 'PAS',
      decimals: 18,
    },
    rpcUrls: [
      'wss://passet-hub-paseo.dotters.network',
      'wss://testnet-passet-hub.polkadot.io',
      'wss://passet-hub-paseo.ibp.network',
    ],
    blockExplorerUrls: ['https://passet-hub.subscan.io/'],
    ensRegistry: '0xe2fB8d393D3A257F709A3a96d234950d00626fa5',
    baseRegistrar: '0xaD5EE06411D18A1Cd1051ED87eAebEE9CD154C64',
    registrarController: '0xfc9FC0f9C67271a84d5Ee1Bd6f14D8527533Bb64',
    bulkRenewal: '0x092b689ed3c08F194EbcB7Fcc7c63d482AaEf2c9',
    publicResolver: '0x41df0d983C94ff742811649278faAa7fBfeb923D',
    oracle: '0x313d4B1c0e4C487A61da6F8ebf00AA01f56be145',
    storeFactory: '0xD1ba8f9dD2218859b4113Fb7eF5C2Ac6D46794f4',
    dotnsRegistrar: '0xa312DA532a0da1F843b09a0172611c2538944b16',
    multicall: '0xe83DCEE30d0b5848D1e74aDb638F3357f9E4766B',
    defaultReverseRegistrar: '0x7547f128d60e8DFcefE2517Bc55176b860933644',
  },
};

export const GAS_LIMIT = 10000000n;
export const MAX_WEIGHT = {
  refTime: BigInt('18446744073709551615'),
  proofSize: BigInt('18446744073709551615'),
};
const PAS_DECIMALS = 10;
export const SPECIAL_CHAR_REGEX = /[&^%$*+~=`{}|\\<>\/\[\]"]+/;
export const TOKEN_UNIT = 'PAS';
export const DEFAULT_NETWORK_ID = 420420420;
export const BLOCK_EXPLORER = 'https://passet-hub.subscan.io/';
export function getFirstDeployedNetwork(): (NetworkConfig & Partial<Deployment>) | undefined {
  return Object.values(SUPPORTED_NETWORKS).find(network => network.ensRegistry !== zeroAddress);
}

export function toFixed(value: string, decimals = 8): string {
  const num = parseFloat(value);
  return num.toFixed(decimals);
}

export function formatPas(raw: bigint): string {
  return formatUnits(raw, PAS_DECIMALS);
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

export function extractBytes(result: any): Uint8Array | string | null {
  if (!result) return null;

  const core =
    result.result ??
    result.ok ??
    result.asOk ??
    (Array.isArray(result) ? result[1] : null) ??
    result;

  if (!core) return null;

  if (core.isOk && core.asOk) return unwrap(core.asOk);
  if (core.ok) return unwrap(core.ok);

  if (core.toHuman) {
    const human = core.toHuman();
    const v = human?.Ok ?? human?.ok;
    if (typeof v === 'string') return v;
  }

  return unwrap(core);
}

export function unwrap(v: any): Uint8Array | string | null {
  if (!v) return null;
  if (typeof v === 'string') return v;
  if (v instanceof Uint8Array) return v;
  if (v.toU8a) return v.toU8a();
  return null;
}

export const ss58ToEthereum = (address: SS58String): Binary =>
  Binary.fromBytes(hexToU8a(keccak256(AccountId().enc(address))).slice(12));

export const isMappedTypedApi = async (
  api: TypedApi<Paseo>,
  address: SS58String
): Promise<boolean> => {
  const key = ss58ToEthereum(address);
  const result = await api.query.Revive.OriginalAccount.getValue(key);
  return result != null;
};

export const isMappedDedot = async (
  api: DedotClient<PaseoAssetHubApi>,
  address: SS58String
): Promise<boolean> => {
  const evm = await api.call.reviveApi.address(address);
  return evm !== zeroAddress && evm != null;
};

export const accountIsMapped = async (
  client: DedotClient<PaseoAssetHubApi> | TypedApi<Paseo>,
  address: SS58String
): Promise<boolean> => {
  const isDedot = 'rpc' in client;

  if (isDedot) {
    return await isMappedDedot(client as DedotClient<PaseoAssetHubApi>, address);
  }

  return await isMappedTypedApi(client as TypedApi<Paseo>, address);
};

export const isValidSubstrateAddress = (address: string, ss58Format = 42): boolean => {
  try {
    if (isHex(address)) return false;

    const decoded = decodeAddress(address);

    const checksummed = encodeAddress(decoded, ss58Format);

    return address === checksummed;
  } catch {
    return false;
  }
};
