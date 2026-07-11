import { once } from "node:events";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  createPublicClient,
  createWalletClient,
  getFunctionSelector,
  http,
  type Abi,
  type Address,
  type Hex,
  type TransactionReceipt,
} from "viem";
import { foundry } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { createAllocationService } from "./service.js";
import { createServer } from "./server.js";
import { computeIntentCommitment } from "./commitment.js";
import type { PlainIntent } from "./types.js";

const ROOT = resolve(import.meta.dirname, "../..");
const RPC_URL = process.env.ANVIL_RPC_URL ?? "http://127.0.0.1:8545";
const OWNER_PRIVATE_KEY = (process.env.ANVIL_PRIVATE_KEY
  ?? "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80") as Hex;
const SIGNER_PRIVATE_KEY = (process.env.SIGNER_PRIVATE_KEY
  ?? "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d") as Hex;

interface Artifact {
  abi: Abi;
  bytecode: { object: Hex };
}

interface RecordedTransaction {
  hash: Hex;
  blockNumber: string;
}

interface VaultTEEResult {
  user: Address;
  vault: Address;
  intentCommitment: Hex;
  allocation: {
    upshiftBps: number;
    firelightBps: number;
    sparkdexBps: number;
    idleBps: number;
  };
  nonce: bigint;
  deadline: bigint;
  ftsoPriceTimestamp: bigint;
  chainId: bigint;
  resultHash: Hex;
}

interface AdapterPositions {
  upshift: bigint;
  firelight: bigint;
  sparkdex: bigint;
  idle: bigint;
  routerLiquid: bigint;
  vaultLiquid: bigint;
}

const RESULT_ALREADY_EXECUTED_SELECTOR = getFunctionSelector("ResultAlreadyExecuted()");

function isResultAlreadyExecutedError(error: unknown): boolean {
  if (error instanceof Error && error.message.includes("ResultAlreadyExecuted")) return true;
  const candidate = error as {
    data?: unknown;
    cause?: { data?: unknown; errorName?: string; message?: string };
  };
  if (candidate.cause?.errorName === "ResultAlreadyExecuted") return true;
  if (candidate.cause?.message?.includes("ResultAlreadyExecuted")) return true;
  const data = candidate.data ?? candidate.cause?.data;
  if (
    typeof data === "string"
    && data.toLowerCase().startsWith(RESULT_ALREADY_EXECUTED_SELECTOR.toLowerCase())
  ) {
    return true;
  }
  return false;
}

async function artifact(source: string, name: string): Promise<Artifact> {
  return JSON.parse(await readFile(resolve(ROOT, "out", source, `${name}.json`), "utf8")) as Artifact;
}

function successful(receipt: TransactionReceipt): TransactionReceipt {
  if (receipt.status !== "success") throw new Error(`transaction ${receipt.transactionHash} reverted`);
  return receipt;
}

async function main(): Promise<void> {
  const account = privateKeyToAccount(OWNER_PRIVATE_KEY);
  const signer = privateKeyToAccount(SIGNER_PRIVATE_KEY);
  const publicClient = createPublicClient({ chain: foundry, transport: http(RPC_URL) });
  const wallet = createWalletClient({ account, chain: foundry, transport: http(RPC_URL) });
  const chainId = await publicClient.getChainId();
  if (chainId !== 31_337) throw new Error(`expected Anvil chain 31337, received ${chainId}`);

  const artifacts = {
    token: await artifact("MockERC20.sol", "MockERC20"),
    verifier: await artifact("IntentVerifier.sol", "IntentVerifier"),
    router: await artifact("StrategyRouter.sol", "StrategyRouter"),
    adapter: await artifact("MockStrategyAdapter.sol", "MockStrategyAdapter"),
    idle: await artifact("IdleAdapter.sol", "IdleAdapter"),
    vault: await artifact("SignalVault.sol", "SignalVault"),
  };
  const transactions: Record<string, RecordedTransaction> = {};

  async function deploy(name: string, item: Artifact, args: readonly unknown[]): Promise<Address> {
    const hash = await wallet.deployContract({ abi: item.abi, bytecode: item.bytecode.object, args });
    const receipt = successful(await publicClient.waitForTransactionReceipt({ hash }));
    if (!receipt.contractAddress) throw new Error(`${name} receipt has no contract address`);
    transactions[name] = { hash, blockNumber: receipt.blockNumber.toString() };
    return receipt.contractAddress;
  }

  async function write(name: string, address: Address, abi: Abi, functionName: string, args: readonly unknown[]) {
    const hash = await wallet.writeContract({ address, abi, functionName, args });
    const receipt = successful(await publicClient.waitForTransactionReceipt({ hash }));
    transactions[name] = { hash, blockNumber: receipt.blockNumber.toString() };
  }

  const fxrp = await deploy("fxrp", artifacts.token, ["Local FXRP", "FXRP"]);
  const verifier = await deploy("verifier", artifacts.verifier, [signer.address]);
  const router = await deploy("router", artifacts.router, [fxrp]);
  const upshift = await deploy("upshift", artifacts.adapter, [fxrp, router, "Upshift Simulation", 20n]);
  const firelight = await deploy("firelight", artifacts.adapter, [fxrp, router, "Firelight Simulation", 35n]);
  const sparkdex = await deploy("sparkdex", artifacts.adapter, [fxrp, router, "SparkDEX Simulation", 70n]);
  const idle = await deploy("idle", artifacts.idle, [fxrp, router]);
  const adapters = [upshift, firelight, sparkdex, idle] as const;
  if (new Set(adapters.map((value) => value.toLowerCase())).size !== 4) throw new Error("adapters are not unique");
  await write("configureAdapters", router, artifacts.router.abi, "configureAdapters", adapters);
  const vault = await deploy("vault", artifacts.vault, [fxrp, router, verifier, account.address]);
  await write("bindVault", router, artifacts.router.abi, "bindVault", [vault]);

  const routerAsset = await publicClient.readContract({ address: router, abi: artifacts.router.abi, functionName: "asset" }) as Address;
  if (routerAsset.toLowerCase() !== fxrp.toLowerCase()) {
    throw new Error(`router asset mismatch: expected ${fxrp} got ${routerAsset}`);
  }
  const routerVault = await publicClient.readContract({ address: router, abi: artifacts.router.abi, functionName: "vault" }) as Address;
  if (routerVault.toLowerCase() !== vault.toLowerCase()) {
    throw new Error(`router vault mismatch: expected ${vault} got ${routerVault}`);
  }

  const signerServer = createServer(createAllocationService({
    privateKey: SIGNER_PRIVATE_KEY,
    signer: signer.address,
    chainId: BigInt(chainId),
    vault,
    verifier,
    ftsoMaxAgeSeconds: 120n,
    resultTtlSeconds: 300n,
    logPlaintextIntent: false,
  }));
  signerServer.listen(0, "127.0.0.1");
  await once(signerServer, "listening");
  const address = signerServer.address();
  if (!address || typeof address === "string") throw new Error("local signer did not bind TCP");
  const endpoint = `http://127.0.0.1:${address.port}/allocate`;

  async function readBalance(holder: Address): Promise<bigint> {
    return (await publicClient.readContract({
      address: fxrp,
      abi: artifacts.token.abi,
      functionName: "balanceOf",
      args: [holder],
    })) as bigint;
  }

  async function readAdapterPositions(): Promise<AdapterPositions> {
    const [upshiftBal, firelightBal, sparkdexBal, idleBal, routerLiquid, vaultLiquid] = await Promise.all([
      readBalance(upshift),
      readBalance(firelight),
      readBalance(sparkdex),
      readBalance(idle),
      readBalance(router),
      readBalance(vault),
    ]);
    return {
      upshift: upshiftBal,
      firelight: firelightBal,
      sparkdex: sparkdexBal,
      idle: idleBal,
      routerLiquid,
      vaultLiquid,
    };
  }

  function assertPositions(
    label: string,
    positions: AdapterPositions,
    expected: { upshift: bigint; firelight: bigint; sparkdex: bigint; idle: bigint },
  ): void {
    const nav =
      positions.upshift
      + positions.firelight
      + positions.sparkdex
      + positions.idle
      + positions.routerLiquid
      + positions.vaultLiquid;
    console.info(
      `${label}: upshift=${positions.upshift} firelight=${positions.firelight} sparkdex=${positions.sparkdex}`
        + ` idle=${positions.idle} routerLiquid=${positions.routerLiquid} vaultLiquid=${positions.vaultLiquid} nav=${nav}`,
    );
    if (positions.upshift !== expected.upshift)
      throw new Error(`${label}: upshift expected ${expected.upshift} got ${positions.upshift}`);
    if (positions.firelight !== expected.firelight)
      throw new Error(`${label}: firelight expected ${expected.firelight} got ${positions.firelight}`);
    if (positions.sparkdex !== expected.sparkdex)
      throw new Error(`${label}: sparkdex expected ${expected.sparkdex} got ${positions.sparkdex}`);
    if (positions.idle !== expected.idle)
      throw new Error(`${label}: idle expected ${expected.idle} got ${positions.idle}`);
    if (positions.routerLiquid !== 0n)
      throw new Error(`${label}: routerLiquid expected 0 got ${positions.routerLiquid}`);
    if (positions.vaultLiquid !== 0n)
      throw new Error(`${label}: vaultLiquid expected 0 got ${positions.vaultLiquid}`);
    if (nav !== 101n) throw new Error(`${label}: NAV expected 101 got ${nav}`);
  }

  async function allocation(
    nonce: bigint,
    plainIntent: PlainIntent,
  ): Promise<{ result: VaultTEEResult; signature: Hex }> {
    const commitment = computeIntentCommitment(account.address, plainIntent, nonce, BigInt(chainId));
    await write(`intent${nonce}`, vault, artifacts.vault.abi, "submitPrivateIntent", ["0xc0ffee", commitment, nonce]);
    const timestamp = BigInt(Math.floor(Date.now() / 1000));
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        user: account.address,
        vault,
        intentVerifier: verifier,
        chainId: chainId.toString(),
        nonce: nonce.toString(),
        intentCommitment: commitment,
        plainIntent,
        ftso: { price: "100000", timestamp: timestamp.toString() },
      }),
    });
    if (!response.ok) throw new Error(`/allocate returned ${response.status}: ${await response.text()}`);
    const output = await response.json() as { result: Record<string, string | number>; signature: Hex };
    const result: VaultTEEResult = {
      user: output.result.user as Address,
      vault: output.result.vault as Address,
      intentCommitment: output.result.intentCommitment as Hex,
      allocation: {
        upshiftBps: Number(output.result.upshiftBps),
        firelightBps: Number(output.result.firelightBps),
        sparkdexBps: Number(output.result.sparkdexBps),
        idleBps: Number(output.result.idleBps),
      },
      nonce: BigInt(output.result.nonce as string),
      deadline: BigInt(output.result.deadline as string),
      ftsoPriceTimestamp: BigInt(output.result.ftsoPriceTimestamp as string),
      chainId: BigInt(output.result.chainId as string),
      resultHash: output.result.resultHash as Hex,
    };
    await write(`allocation${nonce}`, vault, artifacts.vault.abi, "executeTEEAllocation", [result, output.signature]);
    return { result, signature: output.signature };
  }

  try {
    await write("mint", fxrp, artifacts.token.abi, "mint", [account.address, 101n]);
    await write("approve", fxrp, artifacts.token.abi, "approve", [vault, 2n ** 256n - 1n]);
    await write("deposit", vault, artifacts.vault.abi, "deposit", [101n]);

    await allocation(1n, {
      riskLevel: 1,
      targetAprBps: 800,
      maxDrawdownBps: 500,
      rebalanceWindow: 3600,
      salt: `0x${"11".repeat(32)}`,
    });
    assertPositions("after allocation 1", await readAdapterPositions(), {
      upshift: 50n,
      firelight: 20n,
      sparkdex: 10n,
      idle: 21n,
    });

    const second = await allocation(2n, {
      riskLevel: 0,
      targetAprBps: 500,
      maxDrawdownBps: 100,
      rebalanceWindow: 3600,
      salt: `0x${"22".repeat(32)}`,
    });
    assertPositions("after allocation 2", await readAdapterPositions(), {
      upshift: 40n,
      firelight: 20n,
      sparkdex: 0n,
      idle: 41n,
    });

    let replayReverted = false;
    try {
      await publicClient.simulateContract({
        account,
        address: vault,
        abi: artifacts.vault.abi,
        functionName: "executeTEEAllocation",
        args: [second.result, second.signature],
      });
    } catch (error) {
      if (isResultAlreadyExecutedError(error)) {
        replayReverted = true;
      } else {
        throw error;
      }
    }
    if (!replayReverted) throw new Error("replay should have reverted with ResultAlreadyExecuted");
    console.info("replay rejected with ResultAlreadyExecuted as expected");
    const navAfterReplay = await publicClient.readContract({
      address: vault,
      abi: artifacts.vault.abi,
      functionName: "totalAssets",
    });
    if (navAfterReplay !== 101n) throw new Error(`NAV after replay expected 101 got ${navAfterReplay}`);
    assertPositions("after replay", await readAdapterPositions(), {
      upshift: 40n,
      firelight: 20n,
      sparkdex: 0n,
      idle: 41n,
    });

    const totalAssets = await publicClient.readContract({
      address: vault,
      abi: artifacts.vault.abi,
      functionName: "totalAssets",
    });
    if (totalAssets !== 101n) throw new Error(`rebalance changed NAV to ${totalAssets}`);
    await write("partialWithdrawal", vault, artifacts.vault.abi, "withdraw", [33n]);
    await write("fullWithdrawal", vault, artifacts.vault.abi, "withdraw", [68n]);
    const ownerBalance = await publicClient.readContract({
      address: fxrp,
      abi: artifacts.token.abi,
      functionName: "balanceOf",
      args: [account.address],
    });
    const routerAssets = await publicClient.readContract({
      address: router,
      abi: artifacts.router.abi,
      functionName: "totalAssets",
    });
    if (ownerBalance !== 101n || routerAssets !== 0n) {
      throw new Error("full withdrawal did not recover bounded dust");
    }
  } finally {
    signerServer.close();
    await once(signerServer, "close");
    console.info("E2E cleanup complete");
  }

  const deployment = {
    chainId,
    network: "anvil",
    fxrp,
    verifier,
    router,
    vault,
    adapters: { upshift, firelight, sparkdex, idle },
    transactions,
    deployedAt: new Date().toISOString(),
  };
  await writeFile(resolve(ROOT, "deployments/anvil.json"), `${JSON.stringify(deployment, null, 2)}\n`);
  console.info(
    "Anvil HTTP /allocate E2E passed: two allocations, adapter position checks, replay rejection, partial withdrawal, full dust recovery",
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
