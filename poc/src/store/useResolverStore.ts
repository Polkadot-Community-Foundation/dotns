import { defineStore } from 'pinia';
import {
  encodeFunctionData,
  decodeAbiParameters,
  namehash,
  zeroAddress,
  type Address,
  type Hash,
} from 'viem';
import { CID } from 'multiformats/cid';
import { useNetworkStore } from './useNetworkStore';
import { useTransactionStore } from './useTransactionStore';
import { useAbiStore } from './useAbiStore';
import { normalizeDomainName } from '../utils';
import type { TextRecord, TransactionResult, MulticallCall, ResolverStatus } from '@/type';
import { zeroHash } from 'viem';
import { useWalletStore } from './useWalletStore';

export const useResolverStore = defineStore('useResolverStore', () => {
  const networkStore = useNetworkStore();
  const transactionStore = useTransactionStore();
  const abiStore = useAbiStore();
  const walletStore = useWalletStore();

  async function resolveAddressToName(targetAddress: Address): Promise<string | null> {
    try {
      networkStore.ensureClient();
      const network = networkStore.currentNetwork;
      if (!network?.publicResolver) {
        throw new Error('Public resolver not configured');
      }

      const client = await networkStore.getClient();

      const reverseNode = namehash(`${targetAddress.substring(2).toLowerCase()}.addr.reverse`);

      const nameData = encodeFunctionData({
        abi: abiStore.getABI('PublicResolver'),
        functionName: 'name',
        args: [reverseNode],
      });

      const nameResult = await transactionStore.ethCall(
        client,
        zeroAddress,
        network.publicResolver,
        nameData
      );

      const nameDecoded = decodeAbiParameters([{ type: 'string' }], nameResult);
      const name = nameDecoded[0];

      if (!name || name === '' || name === 'true' || name === 'false') {
        return null;
      }

      return name as string;
    } catch (error) {
      console.error('[ResolverStore:resolveAddressToName]', error);
      return null;
    }
  }

  async function resolveNameToAddress(name: string): Promise<Address | null> {
    try {
      networkStore.ensureClient();
      const network = networkStore.currentNetwork;
      if (!network?.publicResolver || !network?.ensRegistry) {
        throw new Error('Contracts not configured');
      }

      const client = await networkStore.getClient();

      name = normalizeDomainName(name);
      const node = name.includes('.dot') ? namehash(name) : namehash(`${name}.dot`);

      const resolverData = encodeFunctionData({
        abi: abiStore.getABI('ENSRegistry'),
        functionName: 'resolver',
        args: [node],
      });

      const resolverResult = await transactionStore.ethCall(
        client,
        zeroAddress,
        network.ensRegistry,
        resolverData
      );

      const resolverDecoded = decodeAbiParameters([{ type: 'address' }], resolverResult);
      const resolverAddress = resolverDecoded[0];

      if (resolverAddress === zeroAddress) {
        return null;
      }

      const addrData = encodeFunctionData({
        abi: abiStore.getABI('PublicResolver'),
        functionName: 'addr',
        args: [node],
      });

      const addrResult = await transactionStore.ethCall(
        client,
        zeroAddress,
        network.publicResolver,
        addrData
      );

      const addrDecoded = decodeAbiParameters([{ type: 'address' }], addrResult);
      const address = addrDecoded[0];

      if (address === zeroAddress) {
        return null;
      }

      return address as Address;
    } catch (error) {
      console.error('[ResolverStore:resolveNameToAddress]', error);
      return null;
    }
  }

  async function setAddressForName(name: string, targetAddress: Address): Promise<Hash> {
    try {
      const network = networkStore.currentNetwork;
      if (!network?.publicResolver) {
        throw new Error('Public resolver not configured');
      }

      const client = await networkStore.getClient();

      name = normalizeDomainName(name);
      const node = namehash(`${name}.dot`);

      const data = encodeFunctionData({
        abi: abiStore.getABI('PublicResolver'),
        functionName: 'setAddr',
        args: [node, targetAddress],
      });

      return await transactionStore.ethTransact(
        client,
        walletStore.getInjected(),
        walletStore.address!,
        {
          to: network.publicResolver,
          data,
        }
      );
    } catch (error) {
      console.error('[ResolverStore:setAddressForName]', error);
      throw error;
    }
  }

  async function getText(name: string, key: string): Promise<string | null> {
    try {
      networkStore.ensureClient();
      const network = networkStore.currentNetwork;
      if (!network?.publicResolver) {
        throw new Error('Public resolver not configured');
      }

      const client = await networkStore.getClient();

      name = normalizeDomainName(name);
      const node = namehash(`${name}.dot`);

      const data = encodeFunctionData({
        abi: abiStore.getABI('PublicResolver'),
        functionName: 'text',
        args: [node, key],
      });

      const result = await transactionStore.ethCall(
        client,
        zeroAddress,
        network.publicResolver,
        data
      );

      const decoded = decodeAbiParameters([{ type: 'string' }], result);
      const value = decoded[0];

      if (!value || value === '' || value === 'true' || value === 'false') {
        return null;
      }

      return value as string;
    } catch (error) {
      console.error('[ResolverStore:getText]', error);
      return null;
    }
  }

  async function setText(name: string, key: string, value: string): Promise<void> {
    try {
      const network = networkStore.currentNetwork;
      if (!network?.publicResolver) {
        throw new Error('Public resolver not configured');
      }

      const client = await networkStore.getClient();

      name = normalizeDomainName(name);
      const node = namehash(`${name}.dot`);

      const data = encodeFunctionData({
        abi: abiStore.getABI('PublicResolver'),
        functionName: 'setText',
        args: [node, key, value],
      });

      await transactionStore.ethTransact(client, walletStore.getInjected(), walletStore.address!, {
        to: network.publicResolver,
        data,
      });
    } catch (error) {
      console.error('[ResolverStore:setText]', error);
      throw error;
    }
  }

  async function setProfileRecordsMulticall(
    name: string,
    records: TextRecord[]
  ): Promise<TransactionResult> {
    try {
      const network = networkStore.currentNetwork;
      await abiStore.ensureAbis();
      if (!network?.publicResolver || !network?.multicall) {
        throw new Error('Public resolver or multicall not configured');
      }

      const client = await networkStore.getClient();

      name = normalizeDomainName(name);
      const node = namehash(`${name}.dot`);
      const entries = records.filter(r => r.value && r.value.length > 0);

      if (entries.length === 0) {
        return { status: false, hash: zeroHash };
      }

      const approvalCheckData = encodeFunctionData({
        abi: abiStore.getABI('PublicResolver'),
        functionName: 'isApprovedForAll',
        args: [walletStore.address!, network.multicall],
      });

      const approvalResult = await transactionStore.ethCall(
        client,
        walletStore.address!,
        network.publicResolver,
        approvalCheckData
      );

      const approvalDecoded = decodeAbiParameters([{ type: 'bool' }], approvalResult);
      const approved = approvalDecoded[0];

      if (!approved) {
        const approveData = encodeFunctionData({
          abi: abiStore.getABI('PublicResolver'),
          functionName: 'setApprovalForAll',
          args: [network.multicall, true],
        });

        await transactionStore.ethTransact(
          client,
          walletStore.getInjected(),
          walletStore.address!,
          {
            to: network.publicResolver,
            data: approveData,
          }
        );
      }

      const calls: MulticallCall[] = entries.map(r => ({
        target: network.publicResolver!,
        callData: encodeFunctionData({
          abi: abiStore.getABI('PublicResolver'),
          functionName: 'setText',
          args: [node, r.key, r.value],
        }),
      }));

      const multicallData = encodeFunctionData({
        abi: abiStore.getABI('MultiCall'),
        functionName: 'aggregate',
        args: [calls],
      });

      const multicallTx = await transactionStore.ethTransact(
        client,
        walletStore.getInjected(),
        walletStore.address!,
        {
          to: network.multicall,
          data: multicallData,
        }
      );

      const revokeData = encodeFunctionData({
        abi: abiStore.getABI('PublicResolver'),
        functionName: 'setApprovalForAll',
        args: [network.multicall, false],
      });

      await transactionStore.ethTransact(client, walletStore.getInjected(), walletStore.address!, {
        to: network.publicResolver,
        data: revokeData,
      });

      return { hash: multicallTx, status: true };
    } catch (error) {
      console.error('[ResolverStore:setProfileRecordsMulticall]', error);
      return { status: false, hash: zeroHash };
    }
  }

  async function setContentHash(name: string, ipfsHash: string): Promise<TransactionResult> {
    try {
      const network = networkStore.currentNetwork;
      await abiStore.ensureAbis();
      if (!network?.publicResolver) {
        throw new Error('Public resolver not configured');
      }

      const client = await networkStore.getClient();

      name = normalizeDomainName(name);
      const node = namehash(`${name}.dot`);
      const cid = CID.parse(ipfsHash);

      const cidBytes = new Uint8Array(cid.multihash.bytes);
      const hexString = Array.from(cidBytes)
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
      const contentHash: `0x${string}` = `0xe301${hexString}`;

      const data = encodeFunctionData({
        abi: abiStore.getABI('PublicResolver'),
        functionName: 'setContenthash',
        args: [node, contentHash],
      });

      const hash = await transactionStore.ethTransact(
        client,
        walletStore.getInjected(),
        walletStore.address!,
        {
          to: network.publicResolver,
          data,
        }
      );

      return { hash, status: true };
    } catch (error) {
      console.error('[ResolverStore:setContentHash]', error);
      throw error;
    }
  }

  async function setResolverForName(name: string): Promise<TransactionResult> {
    try {
      const network = networkStore.currentNetwork;
      await abiStore.ensureAbis();
      if (!network?.ensRegistry || !network?.publicResolver) {
        throw new Error('ENS registry or public resolver not configured');
      }

      const client = await networkStore.getClient();

      name = normalizeDomainName(name);
      const node = namehash(`${name}.dot`);

      const data = encodeFunctionData({
        abi: abiStore.getABI('ENSRegistry'),
        functionName: 'setResolver',
        args: [node, network.publicResolver],
      });

      const hash = await transactionStore.ethTransact(
        client,
        walletStore.getInjected(),
        walletStore.address!,
        {
          to: network.ensRegistry,
          data,
        }
      );

      return { hash, status: true };
    } catch (error) {
      console.error('[ResolverStore:setResolverForName]', error);
      throw error;
    }
  }

  async function checkDomainSetup(name: string): Promise<ResolverStatus> {
    try {
      networkStore.ensureClient();
      await abiStore.ensureAbis();
      const network = networkStore.currentNetwork;

      if (!network?.ensRegistry || !network?.baseRegistrar) {
        throw new Error('ENS registry or base registrar not configured');
      }

      const client = await networkStore.getClient();

      name = normalizeDomainName(name);
      const node = namehash(`${name}.dot`);

      const ownerData = encodeFunctionData({
        abi: abiStore.getABI('ENSRegistry'),
        functionName: 'owner',
        args: [node],
      });

      const ownerResult = await transactionStore.ethCall(
        client,
        walletStore.address!,
        network.ensRegistry,
        ownerData
      );

      const ownerDecoded = decodeAbiParameters([{ type: 'address' }], ownerResult);
      const registryOwner = ownerDecoded[0];

      if (
        !registryOwner ||
        (registryOwner as Address) === zeroAddress ||
        (registryOwner as Address) === network.baseRegistrar
      ) {
        return { needsReclaim: true, needsResolver: true, fixed: true };
      }

      const resolverData = encodeFunctionData({
        abi: abiStore.getABI('ENSRegistry'),
        functionName: 'resolver',
        args: [node],
      });

      const resolverResult = await transactionStore.ethCall(
        client,
        walletStore.address!,
        network.ensRegistry,
        resolverData
      );

      const resolverDecoded = decodeAbiParameters([{ type: 'address' }], resolverResult);
      const resolver = resolverDecoded[0];

      return {
        needsReclaim: false,
        needsResolver: !resolver || (resolver as Address) === zeroAddress,
        fixed: true,
      };
    } catch (error) {
      console.error('[ResolverStore:checkDomainSetup]', error);
      throw error;
    }
  }

  return {
    resolveAddressToName,
    resolveNameToAddress,
    setAddressForName,
    getText,
    setText,
    setProfileRecordsMulticall,
    setContentHash,
    setResolverForName,
    checkDomainSetup,
  };
});
