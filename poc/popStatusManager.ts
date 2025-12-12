import {
    createWalletClient,
    http,
    Address,
    publicActions,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { defineChain } from "viem";

const paseoTestnet = defineChain({
    id: 420420422,
    name: "Paseo Asset Hub Testnet",
    network: "paseo",
    nativeCurrency: {
        decimals: 18,
        name: "DOT",
        symbol: "DOT",
    },
    rpcUrls: {
        default: { http: ["https://testnet-passet-hub-eth-rpc.polkadot.io"] },
    },
});

const STABLE_PRICE_ORACLE_ABI =
    require("./abis/StableOracle.json").abi;

export enum PopStatus {
    NoStatus = 0,
    PopLite = 1,
    PopFull = 2,
    Reserved = 3,
}

const PopStatusLabels = {
    [PopStatus.NoStatus]: "No Status",
    [PopStatus.PopLite]: "Pop Lite",
    [PopStatus.PopFull]: "Pop Full",
    [PopStatus.Reserved]: "Reserved",
};

export class PopStatusManager {
    private walletClient;
    private oracleAddress: Address;

    constructor(
        oracleAddress: Address,
        privateKey: `0x${string}`,
        rpcUrl = "https://testnet-passet-hub-eth-rpc.polkadot.io"
    ) {
        this.oracleAddress = oracleAddress;

        this.walletClient = createWalletClient({
            chain: paseoTestnet,
            transport: http(rpcUrl),
            account: privateKeyToAccount(privateKey),
        }).extend(publicActions);

    }

    async setPopStatus(name: string, status: PopStatus) {
        const hash = await this.walletClient.writeContract({
            address: this.oracleAddress,
            abi: STABLE_PRICE_ORACLE_ABI,
            functionName: "setNamePopStatus",
            args: [name, status]
        });

        console.log(`✅ Transaction sent: ${hash}`);

        const receipt = await this.walletClient.waitForTransactionReceipt({
            hash,
        });
        console.log(`✅ Confirmed in block ${receipt.blockNumber}`);
        return hash;
    }

    async getPopStatus(name: string): Promise<PopStatus> {
        const status = await this.walletClient.readContract({
            address: this.oracleAddress,
            abi: STABLE_PRICE_ORACLE_ABI,
            functionName: "getNamePopStatus",
            args: [name]
        });
        return status as PopStatus
    }

    async classifyName(name: string) {
        const requirement = await this.walletClient.readContract({
            address: this.oracleAddress,
            abi: STABLE_PRICE_ORACLE_ABI,
            functionName: "classifyName",
            args: [name]
        });
        return requirement as any;
    }

    async displayNameInfo(name: string) {
        const currentStatus = await this.getPopStatus(name);
        const classification = await this.classifyName(name);

        console.log(`\n📋 ${name}`);
        console.log(`📊 Current: ${PopStatusLabels[currentStatus]}`);
        console.log(`🔍 Required: ${PopStatusLabels[classification[0] as PopStatus]}`);
        console.log(`💬 Message: ${classification[1]}\n`);
    }
}
