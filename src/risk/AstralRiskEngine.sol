// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IAstralMarketView } from "../interfaces/IAstralMarketView.sol";
import { IAstralRiskEngine } from "../interfaces/IAstralRiskEngine.sol";
import { AstralTypes } from "../libraries/AstralTypes.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { LiquidationLogic } from "../libraries/LiquidationLogic.sol";
import { PercentageMath } from "../libraries/PercentageMath.sol";
import { PriceMath } from "../libraries/PriceMath.sol";

/// @title AstralRiskEngine
/// @notice Cross-market solvency checks and liquidation quoting.
contract AstralRiskEngine is IAstralRiskEngine {
    using FixedPointMath for uint256;
    using PercentageMath for uint256;

    uint256 public constant WAD = 1e18;

    IAstralMarketView public immutable market;

    error InvalidAccount();
    error InvalidMarketPair();
    error BorrowCapacityExceeded(address account, uint256 requiredValue, uint256 capacityValue);
    error CollateralReductionBlocked(address account, address asset, uint256 requestedAssets);
    error AccountNotLiquidatable(address account);
    error NoDebtForAsset(address account, address asset);
    error NoCollateralForAsset(address account, address asset);
    error InvalidRepayAmount();

    constructor(IAstralMarketView market_) {
        market = market_;
    }

    function getAccountLiquidity(address account)
        public
        view
        override
        returns (AstralTypes.AccountLiquidity memory liquidity)
    {
        if (account == address(0)) revert InvalidAccount();
        uint256 count = market.marketCount();
        liquidity.marketCount = count;

        for (uint256 i = 0; i < count; ++i) {
            address asset = market.marketAt(i);
            AstralTypes.AssetLiquidity memory item = _assetLiquidity(account, asset);
            liquidity.collateralValue += item.collateralValue;
            liquidity.borrowCapacity += item.borrowCapacity;
            liquidity.liquidationCollateralValue += item.liquidationCapacity;
            liquidity.debtValue += item.debtValue;
        }

        liquidity.healthFactor = LiquidationLogic.healthFactor(
            liquidity.liquidationCollateralValue, liquidity.debtValue
        );
        liquidity.availableBorrow =
            LiquidationLogic.availableBorrow(liquidity.borrowCapacity, liquidity.debtValue);
        liquidity.shortfall =
            LiquidationLogic.shortfall(liquidity.liquidationCollateralValue, liquidity.debtValue);
    }

    function getAssetLiquidity(address account, address asset)
        public
        view
        override
        returns (AstralTypes.AssetLiquidity memory)
    {
        if (account == address(0)) revert InvalidAccount();
        return _assetLiquidity(account, asset);
    }

    function healthFactor(address account) external view override returns (uint256) {
        return getAccountLiquidity(account).healthFactor;
    }

    function isLiquidatable(address account) public view override returns (bool) {
        AstralTypes.AccountLiquidity memory liquidity = getAccountLiquidity(account);
        return
            liquidity.debtValue != 0 && liquidity.debtValue > liquidity.liquidationCollateralValue;
    }

    function validateBorrow(address account, address debtAsset, uint256 borrowAmount)
        external
        view
        override
    {
        if (borrowAmount == 0) revert InvalidRepayAmount();
        AstralTypes.MarketConfig memory config = market.getMarketConfig(debtAsset);
        AstralTypes.PriceData memory price = market.priceOf(debtAsset);
        uint256 borrowValue =
            PriceMath.valueOf(borrowAmount, config.assetDecimals, price.price, price.decimals);

        AstralTypes.AccountLiquidity memory liquidity = getAccountLiquidity(account);
        uint256 required = liquidity.debtValue + borrowValue;
        if (required > liquidity.borrowCapacity) {
            revert BorrowCapacityExceeded(account, required, liquidity.borrowCapacity);
        }
    }

    function validateCollateralReduction(address account, address asset, uint256 assets)
        external
        view
        override
    {
        if (assets == 0) return;
        AstralTypes.MarketConfig memory config = market.getMarketConfig(asset);
        if (!config.collateralEnabled) return;

        AstralTypes.PriceData memory price = market.priceOf(asset);
        uint256 value = PriceMath.valueOf(assets, config.assetDecimals, price.price, price.decimals);
        uint256 borrowCapacityReduction = value.percentMulUp(config.loanToValueBps);

        AstralTypes.AccountLiquidity memory liquidity = getAccountLiquidity(account);
        uint256 nextBorrowCapacity = liquidity.borrowCapacity > borrowCapacityReduction
            ? liquidity.borrowCapacity - borrowCapacityReduction
            : 0;

        if (liquidity.debtValue > nextBorrowCapacity) {
            revert CollateralReductionBlocked(account, asset, assets);
        }
    }

    function liquidationQuote(
        address account,
        address collateralAsset,
        address debtAsset,
        uint256 requestedRepay
    ) external view override returns (AstralTypes.LiquidationQuote memory quote) {
        if (account == address(0) || collateralAsset == debtAsset || requestedRepay == 0) {
            revert InvalidMarketPair();
        }

        AstralTypes.AccountLiquidity memory liquidity = getAccountLiquidity(account);
        if (liquidity.debtValue == 0 || liquidity.debtValue <= liquidity.liquidationCollateralValue)
        {
            revert AccountNotLiquidatable(account);
        }

        AstralTypes.MarketConfig memory collateralConfig = market.getMarketConfig(collateralAsset);
        AstralTypes.MarketConfig memory debtConfig = market.getMarketConfig(debtAsset);
        uint256 debtAssets = market.borrowBalance(debtAsset, account);
        uint256 collateralAssets = market.supplyBalance(collateralAsset, account);
        if (debtAssets == 0) revert NoDebtForAsset(account, debtAsset);
        if (collateralAssets == 0) revert NoCollateralForAsset(account, collateralAsset);

        quote.repayAssets =
            LiquidationLogic.closeAmount(debtAssets, requestedRepay, debtConfig.closeFactorBps);
        if (quote.repayAssets == 0) revert InvalidRepayAmount();

        AstralTypes.PriceData memory collateralPrice = market.priceOf(collateralAsset);
        AstralTypes.PriceData memory debtPrice = market.priceOf(debtAsset);
        quote.beforeHealthFactor = liquidity.healthFactor;
        quote.closeFactorBps = debtConfig.closeFactorBps;
        quote.appliedBonusBps = LiquidationLogic.appliedBonus(
            collateralConfig.liquidationBonusBps, liquidity.healthFactor
        );

        (quote.collateralAssets, quote.repayValue, quote.seizeValue) = LiquidationLogic.seizeAssets(
            quote.repayAssets,
            debtConfig.assetDecimals,
            debtPrice.price,
            debtPrice.decimals,
            collateralConfig.assetDecimals,
            collateralPrice.price,
            collateralPrice.decimals,
            quote.appliedBonusBps
        );

        if (quote.collateralAssets > collateralAssets) {
            quote.collateralAssets = collateralAssets;
            quote.seizeValue = PriceMath.valueOf(
                collateralAssets,
                collateralConfig.assetDecimals,
                collateralPrice.price,
                collateralPrice.decimals
            );
        }
    }

    function accountAssetLiquidity(address account)
        external
        view
        returns (AstralTypes.AssetLiquidity[] memory items)
    {
        uint256 count = market.marketCount();
        items = new AstralTypes.AssetLiquidity[](count);
        for (uint256 i = 0; i < count; ++i) {
            items[i] = _assetLiquidity(account, market.marketAt(i));
        }
    }

    function _assetLiquidity(address account, address asset)
        internal
        view
        returns (AstralTypes.AssetLiquidity memory item)
    {
        AstralTypes.MarketConfig memory config = market.getMarketConfig(asset);
        AstralTypes.PriceData memory price = market.priceOf(asset);
        uint256 collateralAssets = market.supplyBalance(asset, account);
        uint256 debtAssets = market.borrowBalance(asset, account);

        item.asset = asset;
        item.collateralAssets = collateralAssets;
        item.debtAssets = debtAssets;
        item.price = price.price;
        item.priceDecimals = price.decimals;

        if (collateralAssets != 0 && config.collateralEnabled) {
            item.collateralValue = PriceMath.valueOf(
                collateralAssets, config.assetDecimals, price.price, price.decimals
            );
            item.borrowCapacity = item.collateralValue.percentMulDown(config.loanToValueBps);
            item.liquidationCapacity =
                item.collateralValue.percentMulDown(config.liquidationThresholdBps);
        }

        if (debtAssets != 0) {
            item.debtValue =
                PriceMath.valueOf(debtAssets, config.assetDecimals, price.price, price.decimals);
        }
    }
}
