import assert from "node:assert/strict";
import test from "node:test";

import {
  AstralCreditClient,
  BPS,
  RAY,
  WAD,
  annualizedRate,
  healthFactor,
  keeperPlan,
  mulDivDown,
  mulDivUp,
  stressPosition,
  utilizationRay,
  valueOf,
  type Address,
  type ContractRead,
  type ReadTransport,
} from "./AstralCreditClient.ts";

test("fixed-point helpers preserve rounding direction", () => {
  assert.equal(mulDivDown(10n, 2n, 3n), 6n);
  assert.equal(mulDivUp(10n, 2n, 3n), 7n);
  assert.equal(healthFactor(80_000n * WAD, 82_000n * WAD), 975_609_756_097_560_975n);
});

test("asset value normalizes token and oracle decimals", () => {
  assert.equal(valueOf(2_500n * 10n ** 6n, 6, 1n * 10n ** 8n, 8), 2_500n * WAD);
  assert.equal(valueOf(3n * 10n ** 18n, 18, 2_000n * 10n ** 8n, 8), 6_000n * WAD);
});

test("stress model applies collateral shock, threshold and debt growth", () => {
  const result = stressPosition({
    collateralValue: 1_000_000n * WAD,
    debtValue: 600_000n * WAD,
    liquidationThresholdBps: 8_000n,
    collateralShockBps: 2_000n,
    debtGrowthBps: 500n,
  });
  assert.equal(result.stressedCollateralValue, 800_000n * WAD);
  assert.equal(result.stressedLiquidationValue, 640_000n * WAD);
  assert.equal(result.stressedDebtValue, 630_000n * WAD);
  assert.equal(result.shortfall, 0n);
  assert.ok(result.healthFactor > WAD);
});

test("stress model reports an economic shortfall", () => {
  const result = stressPosition({
    collateralValue: 100n,
    debtValue: 100n,
    liquidationThresholdBps: 8_000n,
    collateralShockBps: 2_500n,
    debtGrowthBps: 1_000n,
  });
  assert.equal(result.stressedLiquidationValue, 60n);
  assert.equal(result.stressedDebtValue, 110n);
  assert.equal(result.shortfall, 50n);
});

test("keeper plan respects gas, protocol and reserve limits", () => {
  const plan = keeperPlan(100, 4_000_000n, 80_000n, 1_000_000n, 250_000n, 64);
  assert.equal(plan.maxByGas, 50);
  assert.equal(plan.batchSize, 50);
  assert.equal(plan.estimatedGas, 4_000_000n);
  assert.equal(plan.deployableCash, 750_000n);
});

test("utilization and annualized rate use ray precision", () => {
  assert.equal(utilizationRay(600n, 400n, 0n), (400n * RAY) / 1_000n);
  assert.equal(annualizedRate(2n), 63_072_000n);
  assert.equal(BPS, 10_000n);
});

test("client delegates typed read calls", async () => {
  const requests: ContractRead[] = [];
  const transport: ReadTransport = {
    async read<T>(request: ContractRead): Promise<T> {
      requests.push(request);
      return 2n as T;
    },
  };
  const market = "0x1111111111111111111111111111111111111111" as Address;
  const risk = "0x2222222222222222222222222222222222222222" as Address;
  const client = new AstralCreditClient(transport, market, risk);
  assert.equal(await client.marketCount(), 2n);
  assert.deepEqual(requests[0], { address: market, functionName: "marketCount" });
});

test("client rejects malformed addresses", () => {
  const transport: ReadTransport = { async read<T>(): Promise<T> { return 0n as T; } };
  assert.throws(
    () => new AstralCreditClient(transport, "0x01" as Address, "0x02" as Address),
    /invalid contract address/,
  );
});
