export const WAD = 10n ** 18n;
export const RAY = 10n ** 27n;
export const BPS = 10_000n;
export const SECONDS_PER_YEAR = 365n * 24n * 60n * 60n;

export type Address = `0x${string}`;

export interface ContractRead {
  address: Address;
  functionName: string;
  args?: readonly unknown[];
}

export interface ReadTransport {
  read<T>(request: ContractRead): Promise<T>;
}

export interface MarketState {
  totalSupplyAssets: bigint;
  totalBorrowAssets: bigint;
  totalReserves: bigint;
  borrowIndex: bigint;
  supplyIndex: bigint;
  lastAccrual: bigint;
}

export interface MarketConfig {
  supplyToken: Address;
  priceOracle: Address;
  rateModel: Address;
  supplyCap: bigint;
  borrowCap: bigint;
  priceMaxAge: bigint;
  loanToValueBps: bigint;
  liquidationThresholdBps: bigint;
  liquidationBonusBps: bigint;
  reserveFactorBps: bigint;
  closeFactorBps: bigint;
  borrowingEnabled: boolean;
  collateralEnabled: boolean;
}

export interface MarketSnapshot {
  asset: Address;
  state: MarketState;
  config: MarketConfig;
  cash: bigint;
  utilizationRay: bigint;
  availableLiquidity: bigint;
  supplyRoom: bigint;
  borrowRoom: bigint;
}

export interface AccountLiquidity {
  collateralValue: bigint;
  borrowCapacity: bigint;
  liquidationCollateralValue: bigint;
  debtValue: bigint;
  availableBorrow: bigint;
  healthFactor: bigint;
}

export interface KeeperPlan {
  remainingAccounts: number;
  maxByGas: number;
  batchSize: number;
  estimatedGas: bigint;
  reserveBuffer: bigint;
  deployableCash: bigint;
}

export interface StressInput {
  collateralValue: bigint;
  debtValue: bigint;
  liquidationThresholdBps: bigint;
  collateralShockBps: bigint;
  debtGrowthBps: bigint;
}

export interface StressResult {
  stressedCollateralValue: bigint;
  stressedLiquidationValue: bigint;
  stressedDebtValue: bigint;
  healthFactor: bigint;
  shortfall: bigint;
}

function requireNonNegative(...values: bigint[]): void {
  if (values.some((value) => value < 0n)) {
    throw new RangeError("values must be non-negative");
  }
}

function requireBps(value: bigint): void {
  if (value < 0n || value > BPS) throw new RangeError("basis points out of range");
}

export function mulDivDown(value: bigint, multiplier: bigint, denominator: bigint): bigint {
  requireNonNegative(value, multiplier, denominator);
  if (denominator === 0n) throw new RangeError("division by zero");
  return (value * multiplier) / denominator;
}

export function mulDivUp(value: bigint, multiplier: bigint, denominator: bigint): bigint {
  requireNonNegative(value, multiplier, denominator);
  if (denominator === 0n) throw new RangeError("division by zero");
  if (value === 0n || multiplier === 0n) return 0n;
  return (value * multiplier + denominator - 1n) / denominator;
}

export function valueOf(
  amount: bigint,
  assetDecimals: number,
  price: bigint,
  priceDecimals: number,
): bigint {
  if (!Number.isInteger(assetDecimals) || !Number.isInteger(priceDecimals)) {
    throw new TypeError("decimals must be integers");
  }
  if (assetDecimals < 0 || priceDecimals < 0 || assetDecimals > 36 || priceDecimals > 36) {
    throw new RangeError("decimals out of range");
  }
  requireNonNegative(amount, price);
  return mulDivDown(amount, price * WAD, 10n ** BigInt(assetDecimals + priceDecimals));
}

export function healthFactor(liquidationValue: bigint, debtValue: bigint): bigint {
  requireNonNegative(liquidationValue, debtValue);
  return debtValue === 0n ? (2n ** 256n - 1n) : mulDivDown(liquidationValue, WAD, debtValue);
}

export function stressPosition(input: StressInput): StressResult {
  requireBps(input.liquidationThresholdBps);
  requireBps(input.collateralShockBps);
  requireBps(input.debtGrowthBps);
  requireNonNegative(input.collateralValue, input.debtValue);
  const stressedCollateralValue = mulDivDown(
    input.collateralValue,
    BPS - input.collateralShockBps,
    BPS,
  );
  const stressedLiquidationValue = mulDivDown(
    stressedCollateralValue,
    input.liquidationThresholdBps,
    BPS,
  );
  const stressedDebtValue = mulDivDown(input.debtValue, BPS + input.debtGrowthBps, BPS);
  return {
    stressedCollateralValue,
    stressedLiquidationValue,
    stressedDebtValue,
    healthFactor: healthFactor(stressedLiquidationValue, stressedDebtValue),
    shortfall:
      stressedDebtValue > stressedLiquidationValue
        ? stressedDebtValue - stressedLiquidationValue
        : 0n,
  };
}

export function annualizedRate(perSecondRay: bigint): bigint {
  requireNonNegative(perSecondRay);
  return perSecondRay * SECONDS_PER_YEAR;
}

export function utilizationRay(cash: bigint, borrows: bigint, reserves: bigint): bigint {
  requireNonNegative(cash, borrows, reserves);
  const gross = cash + borrows;
  const availableBase = gross > reserves ? gross - reserves : 0n;
  return availableBase === 0n ? 0n : mulDivDown(borrows, RAY, availableBase);
}

export function keeperPlan(
  remainingAccounts: number,
  gasBudget: bigint,
  gasPerAccount: bigint,
  liquidCash: bigint,
  reserveBuffer: bigint,
  protocolCap = 64,
): KeeperPlan {
  if (!Number.isInteger(remainingAccounts) || remainingAccounts < 0) {
    throw new RangeError("remainingAccounts must be a non-negative integer");
  }
  if (!Number.isInteger(protocolCap) || protocolCap <= 0) {
    throw new RangeError("protocolCap must be a positive integer");
  }
  requireNonNegative(gasBudget, gasPerAccount, liquidCash, reserveBuffer);
  if (gasPerAccount === 0n) throw new RangeError("gasPerAccount must be positive");
  const maxByGasBig = gasBudget / gasPerAccount;
  const maxByGas = Number(maxByGasBig > BigInt(Number.MAX_SAFE_INTEGER) ? BigInt(Number.MAX_SAFE_INTEGER) : maxByGasBig);
  const batchSize = Math.min(remainingAccounts, protocolCap, maxByGas);
  return {
    remainingAccounts,
    maxByGas,
    batchSize,
    estimatedGas: BigInt(batchSize) * gasPerAccount,
    reserveBuffer,
    deployableCash: liquidCash > reserveBuffer ? liquidCash - reserveBuffer : 0n,
  };
}

export class AstralCreditClient {
  readonly market: Address;
  readonly riskEngine: Address;
  readonly #transport: ReadTransport;

  constructor(transport: ReadTransport, market: Address, riskEngine: Address) {
    if (!/^0x[0-9a-fA-F]{40}$/.test(market) || !/^0x[0-9a-fA-F]{40}$/.test(riskEngine)) {
      throw new TypeError("invalid contract address");
    }
    this.#transport = transport;
    this.market = market;
    this.riskEngine = riskEngine;
  }

  marketCount(): Promise<bigint> {
    return this.#transport.read({ address: this.market, functionName: "marketCount" });
  }

  marketAt(index: bigint): Promise<Address> {
    requireNonNegative(index);
    return this.#transport.read({ address: this.market, functionName: "marketAt", args: [index] });
  }

  accountLiquidity(account: Address): Promise<AccountLiquidity> {
    return this.#transport.read({
      address: this.riskEngine,
      functionName: "getAccountLiquidity",
      args: [account],
    });
  }

  borrowBalance(asset: Address, account: Address): Promise<bigint> {
    return this.#transport.read({
      address: this.market,
      functionName: "borrowBalance",
      args: [asset, account],
    });
  }
}
