// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IAstralMarketView } from "../interfaces/IAstralMarketView.sol";
import { IAstralRiskEngine } from "../interfaces/IAstralRiskEngine.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IRateModel } from "../interfaces/IRateModel.sol";
import { AstralTypes } from "../libraries/AstralTypes.sol";
import { DebtMath } from "../libraries/DebtMath.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { ShareMath } from "../libraries/ShareMath.sol";

/// @title AstralCreditLens
/// @notice Aggregated read-only views for dashboards, bots and governance tooling.
contract AstralCreditLens {
    using FixedPointMath for uint256;

    IAstralMarketView public immutable market;
    IAstralRiskEngine public immutable riskEngine;

    constructor(IAstralMarketView market_, IAstralRiskEngine riskEngine_) {
        market = market_;
        riskEngine = riskEngine_;
    }

    function marketSnapshots()
        external
        view
        returns (AstralTypes.MarketSnapshot[] memory snapshots)
    {
        uint256 count = market.marketCount();
        snapshots = new AstralTypes.MarketSnapshot[](count);
        for (uint256 i = 0; i < count; ++i) {
            snapshots[i] = marketSnapshot(market.marketAt(i));
        }
    }

    function marketSnapshot(address asset)
        public
        view
        returns (AstralTypes.MarketSnapshot memory snapshot)
    {
        AstralTypes.MarketConfig memory config = market.getMarketConfig(asset);
        AstralTypes.MarketState memory state = market.getMarketState(asset);
        AstralTypes.PriceData memory price = market.priceOf(asset);
        uint256 cash = IERC20(asset).balanceOf(address(market));
        uint256 totalShares = IERC20(config.supplyToken).totalSupply();

        snapshot.asset = asset;
        snapshot.supplyToken = config.supplyToken;
        snapshot.cash = cash;
        snapshot.totalSupplyAssets = state.totalSupplyAssets;
        snapshot.totalBorrowAssets = state.totalBorrowAssets;
        snapshot.totalReserves = state.totalReserves;
        snapshot.borrowIndex = state.borrowIndex;
        snapshot.supplyIndex = state.supplyIndex;
        snapshot.utilization =
            DebtMath.utilizationRay(cash, state.totalBorrowAssets, state.totalReserves);
        snapshot.borrowRate = IRateModel(config.rateModel)
            .getBorrowRate(cash, state.totalBorrowAssets, state.totalReserves);
        snapshot.supplyRate = IRateModel(config.rateModel)
            .getSupplyRate(
                cash, state.totalBorrowAssets, state.totalReserves, config.reserveFactorBps
            );
        snapshot.exchangeRate = ShareMath.exchangeRate(state.totalSupplyAssets, totalShares);
        snapshot.price = price.price;
        snapshot.priceDecimals = price.decimals;
        snapshot.status = config.status;
        snapshot.borrowingEnabled = config.borrowingEnabled;
        snapshot.collateralEnabled = config.collateralEnabled;
    }

    function accountOverview(address account)
        external
        view
        returns (
            AstralTypes.AccountLiquidity memory liquidity,
            AstralTypes.AssetLiquidity[] memory assets
        )
    {
        liquidity = riskEngine.getAccountLiquidity(account);
        uint256 count = market.marketCount();
        assets = new AstralTypes.AssetLiquidity[](count);
        for (uint256 i = 0; i < count; ++i) {
            assets[i] = riskEngine.getAssetLiquidity(account, market.marketAt(i));
        }
    }

    function accountBalances(address account)
        external
        view
        returns (address[] memory assets, uint256[] memory supplied, uint256[] memory borrowed)
    {
        uint256 count = market.marketCount();
        assets = new address[](count);
        supplied = new uint256[](count);
        borrowed = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            address asset = market.marketAt(i);
            assets[i] = asset;
            supplied[i] = market.supplyBalance(asset, account);
            borrowed[i] = market.borrowBalance(asset, account);
        }
    }

    function liquidationPreview(
        address account,
        address collateralAsset,
        address debtAsset,
        uint256 requestedRepay
    ) external view returns (AstralTypes.LiquidationQuote memory) {
        return riskEngine.liquidationQuote(account, collateralAsset, debtAsset, requestedRepay);
    }
}
