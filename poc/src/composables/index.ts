import type { PaseoAssetHubApi } from '@dedot/chaintypes';
import type { Paseo } from '@polkadot-api/descriptors';
import type { DedotClient } from 'dedot';
import { Binary, type PolkadotSigner, type TypedApi } from 'polkadot-api';
import type { Injected, InjectedSigner } from 'dedot/types';
import type { EthCallResult, GasLimit, TransactionStatus } from '@/type';
import { isAddress, zeroHash, type Address, type Hash } from 'viem';
import type { SpWeightsWeightV2Weight } from '@dedot/chaintypes/substrate';
import { accountIsMapped } from '@/utils';

export interface IClientWrapper {
  reviveCall(
    from: Address,
    to: Address,
    value: bigint,
    data: `0x${string}`
  ): Promise<EthCallResult>;

  estimateGas(
    from: Address,
    to: Address,
    value: bigint,
    data: `0x${string}`
  ): Promise<{
    gasConsumed: SpWeightsWeightV2Weight;
    storageDeposit: bigint;
  }>;

  reviveTx(
    dest: Address,
    value: bigint,
    data: `0x${string}`,
    accountAddress: string,
    injected: Injected | PolkadotSigner,
    setTransactionStatus: (status: TransactionStatus) => void
  ): Promise<Hash>;
  evmAddress(accountAddress: string): Promise<Address>;
  substrateAddress(evm: Address): Promise<string>;
  mapAccountTx(
    accountAddress: string,
    injected: Injected | PolkadotSigner,
    setTransactionStatus: (status: TransactionStatus) => void
  ): Promise<Hash>;
}

export type DedotClientType = DedotClient<PaseoAssetHubApi>;
export type PolkadotApiType = TypedApi<Paseo>;

export class ClientWrapper implements IClientWrapper {
  private client: DedotClientType | PolkadotApiType;

  constructor(client: DedotClientType | PolkadotApiType) {
    this.client = client;
  }

  private isDedot(client: DedotClientType | PolkadotApiType): client is DedotClientType {
    return 'rpc' in client && typeof (client as any).rpc?.system === 'object';
  }

  async reviveCall(
    from: Address,
    to: Address,
    value: bigint,
    data: `0x${string}`
  ): Promise<EthCallResult> {
    try {
      if (this.isDedot(this.client)) {
        return (await this.client.call.reviveApi.call(
          from,
          to,
          value,
          undefined,
          undefined,
          data
        )) as EthCallResult;
      }

      const ethResults = await this.client.apis.ReviveApi.call(
        await this.substrateAddress(from),
        Binary.fromHex(to),
        value,
        undefined,
        undefined,
        Binary.fromHex(data)
      );
      const originalValue = ethResults.result?.value ?? { data: undefined, flags: {} as any };
      const dataField = (originalValue as any)?.data;
      const dataHex =
        dataField && typeof (dataField as any)?.asHex === 'function'
          ? (dataField as any).asHex()
          : dataField;

      return {
        gasConsumed: ethResults.gas_consumed as unknown as SpWeightsWeightV2Weight,
        gasRequired: ethResults.gas_required as unknown as SpWeightsWeightV2Weight,
        storageDeposit: ethResults.storage_deposit,
        result: {
          ...ethResults.result,
          isErr: !ethResults.result.success,
          isOk: ethResults.result.success,
          value: { ...(originalValue as any), data: dataHex },
        },
      };
    } catch (error: any) {
      console.error('[ClientWrapper] reviveCall error:', error);
      throw error;
    }
  }

  async estimateGas(from: Address, to: Address, value: bigint, data: `0x${string}`) {
    try {
      const result = await this.reviveCall(from, to, value, data);
      return {
        success: result.result.isOk,
        gasConsumed: result.gasConsumed,
        storageDeposit: result.storageDeposit.value,
        gasRequired: result.gasRequired,
      };
    } catch (error: any) {
      console.error('[ClientWrapper] estimateGas error:', error);
      throw error;
    }
  }

  private async ensureMapped(
    accountAddress: string,
    injected: Injected | PolkadotSigner,
    setTransactionStatus: (status: TransactionStatus) => void
  ): Promise<void> {
    const substrateAddress = await this.substrateAddress(accountAddress as Address);
    const mapped = await accountIsMapped(this.client, substrateAddress);
    if (mapped) return;
    await this.mapAccountTx(accountAddress, injected, setTransactionStatus);
  }

  private signExtrinsic(
    extrinsic: any,
    account: Address,
    signer: InjectedSigner | PolkadotSigner,
    isDedot: boolean,
    setTransactionStatus: (status: TransactionStatus) => void
  ): Promise<Hash> {
    if (isDedot) {
      return new Promise<Hash>((resolve, reject) => {
        try {
          extrinsic
            .signAndSend(account, { signer }, (event: any) => {
              const status = event.status;
              const txHash = event.txHash?.toString();

              if ('type' in status) {
                switch (status.type) {
                  case 'Broadcasting':
                    setTransactionStatus('broadcasting');
                    break;
                  case 'BestChainBlockIncluded':
                    setTransactionStatus('included');
                    break;
                  case 'Finalized':
                    setTransactionStatus('finalized');
                    resolve(txHash as Hash);
                    return;
                  case 'Drop':
                    setTransactionStatus('failed');
                    reject(new Error('Transaction dropped'));
                    return;
                  case 'Invalid':
                    setTransactionStatus('failed');
                    reject(new Error('Transaction invalid'));
                    return;
                  case 'NoLongerInBestChain':
                    setTransactionStatus('failed');
                    break;
                }
              }

              if (event.dispatchError) {
                reject(new Error(event.dispatchError.toString()));
              }
            })
            .catch(reject);
        } catch (error) {
          reject(error);
        }
      });
    }

    return new Promise<Hash>((resolve, reject) => {
      try {
        extrinsic.signSubmitAndWatch(signer).subscribe({
          next: (event: any) => {
            const txHash = event.txHash?.toString();

            if (event.type === 'signed') setTransactionStatus('signing');
            else if (event.type === 'broadcasted') setTransactionStatus('broadcasting');
            else if (event.type === 'txBestBlocksState') setTransactionStatus('included');
            else if (event.type === 'finalized') {
              setTransactionStatus('finalized');
              resolve(txHash as Hash);
              return;
            }
          },
          error: reject,
        });
      } catch (error) {
        reject(error);
      }
    });
  }

  async reviveTx(
    dest: Address,
    value: bigint,
    data: `0x${string}`,
    accountAddress: string,
    injected: Injected | PolkadotSigner,
    setTransactionStatus: (status: TransactionStatus) => void
  ): Promise<Hash> {
    let txHash: Hash = zeroHash;

    try {
      await this.ensureMapped(accountAddress, injected, setTransactionStatus);
      const isDedot = this.isDedot(this.client);
      const estimatedGas = await this.estimateGas(accountAddress as Address, dest, value, data);

      if (!estimatedGas.success) return zeroHash;

      if (isDedot) {
        const extrinsic = (this.client as DedotClientType).tx.revive.call(
          dest,
          value,
          estimatedGas.gasConsumed,
          estimatedGas.storageDeposit,
          data
        );

        const signer = (injected as Injected).signer as InjectedSigner;

        return await this.signExtrinsic(
          extrinsic,
          accountAddress as Address,
          signer,
          true,
          setTransactionStatus
        );
      }

      const gas = estimatedGas.gasRequired as unknown as GasLimit;

      const extrinsic = (this.client as PolkadotApiType).tx.Revive.call({
        dest: Binary.fromHex(dest),
        value,
        gas_limit: {
          proof_size: gas.proof_size + gas.proof_size / 10n,
          ref_time: gas.ref_time + gas.ref_time / 10n,
        },
        storage_deposit_limit: estimatedGas.storageDeposit,
        data: Binary.fromHex(data),
      });

      const signer = injected as PolkadotSigner;

      txHash = await this.signExtrinsic(
        extrinsic,
        accountAddress as Address,
        signer,
        false,
        setTransactionStatus
      );
    } catch (error: any) {
      console.error('[ClientWrapper] error in reviveTX:', error);
    }

    return txHash;
  }

  async mapAccountTx(
    accountAddress: string,
    injected: Injected | PolkadotSigner,
    setTransactionStatus: (status: TransactionStatus) => void
  ): Promise<Hash> {
    try {
      const isDedot = this.isDedot(this.client);

      if (isDedot) {
        const extrinsic = (this.client as DedotClientType).tx.revive.mapAccount();
        const signer = (injected as Injected).signer as InjectedSigner;

        return await this.signExtrinsic(
          extrinsic,
          accountAddress as Address,
          signer,
          true,
          setTransactionStatus
        );
      }

      const extrinsic = (this.client as PolkadotApiType).tx.Revive.map_account();
      const signer = injected as PolkadotSigner;

      return await this.signExtrinsic(
        extrinsic,
        accountAddress as Address,
        signer,
        false,
        setTransactionStatus
      );
    } catch (error: any) {
      console.error('[ClientWrapper] mapAccountTx error:', error);
      throw error;
    }
  }

  async evmAddress(accountId32: string): Promise<Address> {
    try {
      if (isAddress(accountId32)) {
        return accountId32;
      }
      if (this.isDedot(this.client)) {
        return (await (this.client as DedotClientType).call.reviveApi.address(
          accountId32
        )) as Address;
      }
      const address = await (this.client as PolkadotApiType).apis.ReviveApi.address(accountId32);
      return address.asHex() as Address;
    } catch (error: any) {
      console.error('[ClientWrapper] evmAddress error:', error);
      throw error;
    }
  }

  async substrateAddress(evm: Address): Promise<string> {
    try {
      if (this.isDedot(this.client)) {
        const call = (this.client as DedotClientType).call;

        if (!call || !call.reviveApi || typeof call.reviveApi.account !== 'function') {
          throw new Error('reviveApi.account is not available on Dedot client');
        }

        const acc = await call.reviveApi.account(evm);
        return acc.toString();
      }

      return await (this.client as PolkadotApiType).apis.ReviveApi.account_id(Binary.fromHex(evm));
    } catch (error: any) {
      console.error('[ClientWrapper] substrateAddress error:', error);
      throw error;
    }
  }
}
