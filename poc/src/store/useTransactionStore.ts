import { defineStore } from 'pinia';
import { ref } from 'vue';
import { createPublicClient, http, zeroHash, type Address, type Hash } from 'viem';
import type { Injected } from 'dedot/types';
import type { GenericTransaction } from '@/type';
import type { IClientWrapper } from '@/composables';
import type { PolkadotSigner } from 'polkadot-api';
import { useWalletStore } from './useWalletStore';

export const useTransactionStore = defineStore('useTransactionStore', () => {
  const walletStore = useWalletStore();
  const pendingTxs = ref<Map<Hash, { status: string; timestamp: number }>>(new Map());

  async function ethCall(
    client: IClientWrapper,
    from: Address,
    to: Address,
    data: `0x${string}`,
    value: bigint = 0n,
    withViem: boolean = false,
    ethRpcURL?: string
  ): Promise<`0x${string}`> {
    const fallback: `0x${string}` = zeroHash;
    try {
      if (withViem && ethRpcURL) {
        const viemTest = createPublicClient({
          transport: http(ethRpcURL),
        });
        const ethCallResult = await viemTest.call({
          to,
          account: from,
          data,
        });
        console.log('ethCallResult: ', ethCallResult);
        return ethCallResult.data ?? zeroHash;
      }
      walletStore.setIsLoading(true);
      if (!client) throw new Error('Client not initialised');

      const ethCallResult = await client.reviveCall(from, to, value, data);

      if (ethCallResult.result.isErr) {
        console.error('EVM call error:', ethCallResult.result);
        return fallback;
      }

      const responseData = ethCallResult?.result;

      if (!responseData.isOk || !responseData.success) {
        console.warn('No data in successful response:', responseData.value?.data);
        return fallback;
      }

      return (responseData.value?.data as `0x${string}`) || fallback;
    } catch (error) {
      console.error('[useTransactionStore]: ethCall exception:', error);
      return fallback;
    } finally {
      walletStore.setIsLoading(false);
    }
  }

  async function ethTransact(
    client: IClientWrapper,
    injected: Injected | PolkadotSigner,
    accountAddress: string,
    tx: GenericTransaction
  ): Promise<Hash> {
    let hash = zeroHash as Hash;
    try {
      if (!client) throw new Error('Client not initialised');
      if (!injected) throw new Error('No signer available');
      if (!tx.to) throw new Error('Transaction destination address required');
      if (!tx.data) throw new Error('Transaction data required');
      hash = await client.reviveTx(
        tx.to,
        tx.value || 0n,
        tx.data,
        accountAddress,
        injected,
        walletStore.setTransactionStatus
      );
    } catch (error) {
      console.error('[useTransactionStore]: ethTransact exception:', error);
      throw error;
    } finally {
      walletStore.setTransactionStatus('idle');
      return hash;
    }
  }

  async function mapAccount(
    client: IClientWrapper,
    injected: Injected | PolkadotSigner,
    accountAddress: string
  ): Promise<Hash | void> {
    try {
      return client.mapAccountTx(accountAddress, injected, walletStore.setTransactionStatus);
    } catch (error) {
      console.error('[useTransactionStore]: mapAccount exception:', error);
      throw error;
    } finally {
      walletStore.setTransactionStatus('idle');
    }
  }

  function clearPendingTx(txHash: Hash): void {
    pendingTxs.value.delete(txHash);
  }

  function getPendingTxStatus(txHash: Hash): string | null {
    return pendingTxs.value.get(txHash)?.status || null;
  }

  return {
    pendingTxs,
    ethCall,
    ethTransact,
    mapAccount,
    clearPendingTx,
    getPendingTxStatus,
  };
});
