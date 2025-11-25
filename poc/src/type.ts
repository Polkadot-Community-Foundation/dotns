import type { Address, Hash } from 'viem';

export type NetworkConfig = {
  chainId: number;
  chainName: string;
  nativeCurrency: {
    name: string;
    symbol: string;
    decimals: number;
  };
  rpcUrls: string[];
  blockExplorerUrls?: string[];
};

export type Deployment = {
  ensRegistry: Address;
  baseRegistrar: Address;
  registrarController: Address;
  bulkRenewal: Address;
  publicResolver: Address;
  oracle: Address;
  storeFactory: Address;
  dotnsRegistrar: Address;
  multicall: Address;
};
export type Registration = {
  label: string;
  owner: Address;
  duration: bigint;
  secret: Hash;
  resolver: Address;
  data: `0x${string}`[];
  reverseRecord: boolean;
  referrer: Hash;
};

export type TransactionResult = {
  hash: Hash;
  status?: boolean;
};
export type TextRecord = { key: string; value: string };
export type Commitment = { commitment: Hash; registration: Registration };
export type ProfileRecord = {
  twitter: string;
  github: string;
  description: string;
  url: string;
};
export type ResolverStatus = { needsResolver: boolean; fixed: boolean; needsReclaim: boolean };
export type MyDomain = {
  name: string;
  type: string;
  expiry: string;
  statusIcon: string;
  statusLabel: string;
  isOwner: boolean;
  needsResolver: boolean;
};
export type TransactionState = 'pending' | 'success' | 'failed';
export type Unit = 'minutes' | 'hours' | 'days' | 'years' | 'months';
export type DotNSStatus = 'taken' | 'available';
export type ENSPrice = { base: BigInt; premium: BigInt };
