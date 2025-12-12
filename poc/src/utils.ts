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
    ensRegistry: '0xC0c7f882c253AE7F0E97a8FaCD1c7DfE8aFFc608',
    baseRegistrar: '0xDfd8f8fB9E90dd30f907f4Ad2111429c76118925',
    registrarController: '0xBa24B58c0967F3dDD128Dec4B5a18711957a3cF4',
    bulkRenewal: '0x5AD7f19A127E4A8CC92cfca2c257731D8A50535c',
    publicResolver: '0xECC23874f673E54fd213b2AC4DC0345Df133043C',
    storeFactory: '0xaC9a350c92D8DEB2E1FC0951C604B18b472a767c',
    dotnsRegistrar: '0x36dBd7BdeF1f77247819Deeb1CFd2711347F8677',
    multicall: '0x45b60233e000EE7C7440E14fab57f598564addAd',
    StableOracle: '0x9b76A3d6A30c39E0020843D1a44E03A4AB42B6Bb',
    defaultReverseRegistrar: '0xC1D19E62E281bF948Dc59E1Fd69A35c57139CAAE',
    ethRPCURL: 'https://testnet-passet-hub-eth-rpc.polkadot.io',
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

export const PopStatus = {
  NoStatus: 0,
  PopLite: 1,
  PopFull: 2,
  Reserved: 3,
} as const;

export type PopStatus = (typeof PopStatus)[keyof typeof PopStatus];

export interface NameClassification {
  requirement: PopStatus;
  message: string;
  valid: boolean;
  error?: string;
}

export function countTrailingDigits(name: string): number {
  let count = 0;
  for (let i = name.length - 1; i >= 0; i--) {
    const char = name[i];
    if (char && char >= '0' && char <= '9') {
      count++;
    } else {
      break;
    }
  }
  return count;
}

export function classifyName(name: string): NameClassification {
  const len = name.length;
  const trailing = countTrailingDigits(name);

  if (len <= 5) {
    return {
      requirement: PopStatus.Reserved,
      message: 'Reserved for Governance',
      valid: false,
      error: 'Reserved for Governance',
    };
  }

  if (len >= 6 && len <= 8) {
    if (trailing >= 2) {
      return {
        requirement: PopStatus.PopLite,
        message: 'Requires Light personhood verification',
        valid: true,
      };
    }
    return {
      requirement: PopStatus.PopFull,
      message: 'Requires Full personhood verification',
      valid: true,
    };
  }

  if (trailing >= 2) {
    return {
      requirement: PopStatus.NoStatus,
      message: 'Available to all',
      valid: true,
    };
  }

  return {
    requirement: PopStatus.PopFull,
    message: 'Requires Full personhood verification',
    valid: true,
  };
}

export function canRegisterWithStatus(name: string, userStatus: PopStatus): boolean {
  const classification = classifyName(name);

  if (!classification.valid) {
    return false;
  }

  if (classification.requirement === PopStatus.Reserved) {
    return false;
  }

  if (classification.requirement === PopStatus.PopFull) {
    return userStatus === PopStatus.PopFull;
  }

  if (classification.requirement === PopStatus.PopLite) {
    return userStatus === PopStatus.PopLite || userStatus === PopStatus.PopFull;
  }

  if (classification.requirement === PopStatus.NoStatus) {
    return true;
  }

  return false;
}

export function getEligibilityMessage(name: string, userStatus: PopStatus): string {
  const classification = classifyName(name);

  if (!classification.valid) {
    return classification.error || 'Invalid name';
  }

  if (classification.requirement === PopStatus.Reserved) {
    return 'Reserved for Governance';
  }

  if (classification.requirement === PopStatus.PopFull) {
    if (userStatus === PopStatus.PopFull) {
      return 'Eligible: PopFull verified for PopFull name';
    }
    return 'Ineligible: Requires Full Personhood verification';
  }

  if (classification.requirement === PopStatus.PopLite) {
    if (userStatus === PopStatus.PopLite || userStatus === PopStatus.PopFull) {
      return 'Eligible: PoP verified for PopLite name';
    }
    return 'Ineligible: Requires Personhood Lite verification';
  }

  const trailingDigits = countTrailingDigits(name);

  if (trailingDigits > 0) {
    if (userStatus === PopStatus.PopLite) {
      return 'Eligible: PopLite for 9+ char name with suffix';
    } else if (userStatus === PopStatus.PopFull) {
      return 'Note: PopFull registering PopLite eligible name';
    }
    return 'Available: Standard pricing applies';
  } else {
    if (userStatus === PopStatus.PopFull) {
      return 'Eligible: PopFull for 9+ char name';
    } else if (userStatus === PopStatus.PopLite) {
      return 'Available: PopLite not optimal for alpha-only';
    }
    return 'Available: Standard pricing applies';
  }
}

export function validateName(name: string): { valid: boolean; error?: string } {
  if (!name || name.length === 0) {
    return { valid: false, error: 'Name cannot be empty' };
  }

  const classification = classifyName(name);

  if (!classification.valid) {
    return { valid: false, error: classification.error };
  }

  return { valid: true };
}

export const PopStatusLabels = {
  [PopStatus.NoStatus]: 'No Status',
  [PopStatus.PopLite]: 'Pop Lite',
  [PopStatus.PopFull]: 'Pop Full',
  [PopStatus.Reserved]: 'Reserved',
};
