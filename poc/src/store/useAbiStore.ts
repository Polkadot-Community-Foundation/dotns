import { defineStore } from 'pinia';
import type { Abi } from 'viem';

export const useAbiStore = defineStore('useAbiStore', () => {
  let ETHRegistrarControllerABI: Abi;
  let ENSRegistryABI: Abi;
  let StaticBulkRenewalABI: Abi;
  let BaseRegistrarABI: Abi;
  let DummyOracleABI: Abi;
  let StoreFactoryABI: Abi;
  let StoreABI: Abi;
  let PublicResolverABI: Abi;
  let MultiCallABI: Abi;
  let ReverseRegistrarABI: Abi;

  async function loadABIs(): Promise<void> {
    if (ETHRegistrarControllerABI) return;

    const [
      ETHRegistrarController,
      ENSRegistry,
      StaticBulkRenewal,
      BaseRegistrarImplementation,
      DummyOracle,
      StoreFactory,
      Store,
      PublicResolver,
      MultiCall,
      DefaultReverseRegistrar,
    ] = await Promise.all([
      import('../../abis/ETHRegistrarController.json'),
      import('../../abis/ENSRegistry.json'),
      import('../../abis/StaticBulkRenewal.json'),
      import('../../abis/BaseRegistrarImplementation.json'),
      import('../../abis/DummyOracle.json'),
      import('../../abis/StoreFactory.json'),
      import('../../abis/Store.json'),
      import('../../abis/PublicResolver.json'),
      import('../../abis/Multicall3.json'),
      import('../../abis/DefaultReverseRegistrar.json'),
    ]);

    ETHRegistrarControllerABI = ETHRegistrarController.abi as Abi;
    ENSRegistryABI = ENSRegistry.abi as Abi;
    StaticBulkRenewalABI = StaticBulkRenewal.abi as Abi;
    BaseRegistrarABI = BaseRegistrarImplementation.abi as Abi;
    DummyOracleABI = DummyOracle.abi as Abi;
    StoreFactoryABI = StoreFactory.abi as Abi;
    StoreABI = Store.abi as Abi;
    PublicResolverABI = PublicResolver.abi as Abi;
    MultiCallABI = MultiCall.abi as Abi;
    ReverseRegistrarABI = DefaultReverseRegistrar.abi as Abi;
  }

  function getABI(name: string): Abi {
    const abis: Record<string, Abi> = {
      ETHRegistrarController: ETHRegistrarControllerABI,
      ENSRegistry: ENSRegistryABI,
      StaticBulkRenewal: StaticBulkRenewalABI,
      BaseRegistrar: BaseRegistrarABI,
      DummyOracle: DummyOracleABI,
      StoreFactory: StoreFactoryABI,
      Store: StoreABI,
      PublicResolver: PublicResolverABI,
      MultiCall: MultiCallABI,
      ReverseRegistrar: ReverseRegistrarABI,
    };
    const abi = abis[name];
    if (!abi) {
      throw new Error(`ABI not found: ${name}`);
    }
    return abi;
  }

  async function ensureAbis(): Promise<void> {
    if (!ETHRegistrarControllerABI) {
      await loadABIs();
    }
  }
  return {
    loadABIs,
    getABI,
    ensureAbis,
  };
});
