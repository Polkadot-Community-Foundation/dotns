import type { SpWeightsWeightV2Weight } from '@dedot/chaintypes/substrate';
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
  storeFactory: Address;
  dotnsRegistrar: Address;
  multicall: Address;
  defaultReverseRegistrar: Address;
  StableOracle: Address;
  ethRPCURL: string;
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

export type EthCallResult = {
  gasConsumed: SpWeightsWeightV2Weight;
  gasRequired: SpWeightsWeightV2Weight;
  storageDeposit: {
    type: 'Charge' | 'Refund';
    value: bigint;
  };
  result: Result;
};

export type Result = {
  success: boolean;
  isErr: boolean;
  isOk: boolean;
  value?: {
    data: `0x${string}` | any;
    flags?: any;
  };
};
export type GenericTransaction = {
  accessList?: AccessList | null;
  authorizationList?: AuthorizationListEntry[];
  blobVersionedHashes?: `0x${string}`[];
  blobs?: `0x${string}`[];
  chainId?: bigint | null;
  from?: Address | null;
  gas?: bigint | null;
  gasPrice?: bigint | null;
  input?: `0x${string}`;
  maxFeePerBlobGas?: bigint | null;
  maxFeePerGas?: bigint | null;
  maxPriorityFeePerGas?: bigint | null;
  nonce?: bigint | null;
  to?: Address | null;
  type?: number | null;
  value?: bigint | null;
  data: `0x${string}` | null;
};

export type AccessList = {
  address: Address;
  storageKeys: `0x${string}`[];
}[];

export type AuthorizationListEntry = {
  address: Address;
  nonce: bigint;
  chainId: bigint;
  r: `0x${string}`;
  s: `0x${string}`;
  yParity: number;
};

export type MulticallCall = {
  target: Address;
  callData: `0x${string}`;
};

export type DotnsAvailability = {
  owner: Address;
  available: boolean;
  name: string | null;
};
export type RenewHandle = { handle: string; duration: bigint; unit: Unit };
export type GasLimit = { ref_time: bigint; proof_size: bigint };
export type ENSPrice = { base: BigInt; premium: BigInt };
export type TransactionState = 'pending' | 'success' | 'failed';
export type Unit = 'minutes' | 'hours' | 'days' | 'years' | 'months';
export type DotNSStatus = 'taken' | 'available';
export type TransactionStatus =
  | 'idle'
  | 'signing'
  | 'broadcasting'
  | 'included'
  | 'finalized'
  | 'failed';
export type SignerMode = 'papi' | 'legacy';
