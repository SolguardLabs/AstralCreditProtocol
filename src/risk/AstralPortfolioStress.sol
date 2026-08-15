// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FixedPointMath } from "../libraries/FixedPointMath.sol";

/// @title AstralPortfolioStress
/// @notice Deterministic multi-market stress calculations for governance and keepers.
contract AstralPortfolioStress {
    using FixedPointMath for uint256;

    uint256 public constant WAD = 1e18;
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_MARKETS = 32;

    struct MarketShock {
        address asset;
        uint256 collateralValue;
        uint256 debtValue;
        uint256 liquidAssets;
        uint16 liquidationThresholdBps;
        uint16 collateralShockBps;
        uint16 debtGrowthBps;
        uint16 liquidityHaircutBps;
    }

    struct MarketResult {
        address asset;
        uint256 stressedCollateralValue;
        uint256 stressedLiquidationValue;
        uint256 stressedDebtValue;
        uint256 stressedLiquidAssets;
        uint256 healthFactor;
        uint256 liquidityCoverageWad;
    }

    struct PortfolioResult {
        uint256 collateralValue;
        uint256 liquidationValue;
        uint256 debtValue;
        uint256 liquidAssets;
        uint256 healthFactor;
        uint256 liquidityCoverageWad;
        uint256 concentrationWad;
        uint256 largestMarketShareWad;
        uint256 shortfall;
        uint8 severity;
    }

    error EmptyPortfolio();
    error TooManyMarkets(uint256 count);
    error DuplicateAsset(address asset);
    error InvalidBps(uint256 value);
    error InvalidAsset();

    function evaluate(MarketShock[] calldata shocks)
        external
        pure
        returns (PortfolioResult memory portfolio, MarketResult[] memory markets)
    {
        uint256 count = shocks.length;
        if (count == 0) revert EmptyPortfolio();
        if (count > MAX_MARKETS) revert TooManyMarkets(count);
        markets = new MarketResult[](count);

        for (uint256 i = 0; i < count; ++i) {
            _validate(shocks, i);
            MarketResult memory result = _evaluateMarket(shocks[i]);
            markets[i] = result;
            portfolio.collateralValue += result.stressedCollateralValue;
            portfolio.liquidationValue += result.stressedLiquidationValue;
            portfolio.debtValue += result.stressedDebtValue;
            portfolio.liquidAssets += result.stressedLiquidAssets;
        }

        portfolio.healthFactor = _ratio(portfolio.liquidationValue, portfolio.debtValue);
        portfolio.liquidityCoverageWad = _ratio(portfolio.liquidAssets, portfolio.debtValue);
        (portfolio.concentrationWad, portfolio.largestMarketShareWad) =
            _concentration(markets, portfolio.collateralValue);
        portfolio.shortfall = portfolio.debtValue > portfolio.liquidationValue
            ? portfolio.debtValue - portfolio.liquidationValue
            : 0;
        portfolio.severity = _severity(
            portfolio.healthFactor,
            portfolio.liquidityCoverageWad,
            portfolio.concentrationWad,
            portfolio.shortfall
        );
    }

    function evaluateMarket(MarketShock calldata shock)
        external
        pure
        returns (MarketResult memory)
    {
        _validateBps(shock.liquidationThresholdBps);
        _validateBps(shock.collateralShockBps);
        _validateBps(shock.debtGrowthBps);
        _validateBps(shock.liquidityHaircutBps);
        if (shock.asset == address(0)) revert InvalidAsset();
        return _evaluateMarket(shock);
    }

    function _evaluateMarket(MarketShock calldata shock)
        private
        pure
        returns (MarketResult memory result)
    {
        uint256 collateralMultiplier = BPS - shock.collateralShockBps;
        uint256 liquidityMultiplier = BPS - shock.liquidityHaircutBps;
        result.asset = shock.asset;
        result.stressedCollateralValue = shock.collateralValue * collateralMultiplier / BPS;
        result.stressedLiquidationValue =
            result.stressedCollateralValue * shock.liquidationThresholdBps / BPS;
        result.stressedDebtValue = shock.debtValue * (BPS + shock.debtGrowthBps) / BPS;
        result.stressedLiquidAssets = shock.liquidAssets * liquidityMultiplier / BPS;
        result.healthFactor = _ratio(result.stressedLiquidationValue, result.stressedDebtValue);
        result.liquidityCoverageWad = _ratio(result.stressedLiquidAssets, result.stressedDebtValue);
    }

    function _concentration(MarketResult[] memory markets, uint256 totalCollateral)
        private
        pure
        returns (uint256 hhi, uint256 largestShare)
    {
        if (totalCollateral == 0) return (0, 0);
        for (uint256 i = 0; i < markets.length; ++i) {
            uint256 share = markets[i].stressedCollateralValue.mulDivDown(WAD, totalCollateral);
            hhi += share.mulDivDown(share, WAD);
            if (share > largestShare) largestShare = share;
        }
    }

    function _severity(
        uint256 healthFactor,
        uint256 liquidityCoverage,
        uint256 concentration,
        uint256 shortfall
    ) private pure returns (uint8) {
        if (shortfall != 0 || healthFactor < 0.9e18 || liquidityCoverage < 0.25e18) return 3;
        if (healthFactor < WAD || liquidityCoverage < 0.5e18 || concentration > 0.75e18) return 2;
        if (healthFactor < 1.1e18 || liquidityCoverage < WAD || concentration > 0.5e18) return 1;
        return 0;
    }

    function _validate(MarketShock[] calldata shocks, uint256 index) private pure {
        MarketShock calldata shock = shocks[index];
        if (shock.asset == address(0)) revert InvalidAsset();
        _validateBps(shock.liquidationThresholdBps);
        _validateBps(shock.collateralShockBps);
        _validateBps(shock.debtGrowthBps);
        _validateBps(shock.liquidityHaircutBps);
        for (uint256 j = 0; j < index; ++j) {
            if (shocks[j].asset == shock.asset) revert DuplicateAsset(shock.asset);
        }
    }

    function _validateBps(uint256 value) private pure {
        if (value > BPS) revert InvalidBps(value);
    }

    function _ratio(uint256 numerator, uint256 denominator) private pure returns (uint256) {
        if (denominator == 0) return numerator == 0 ? 0 : type(uint256).max;
        return numerator.mulDivDown(WAD, denominator);
    }

    function minimumDebtReduction(uint256 liquidationValue, uint256 debtValue, uint256 targetHealth)
        external
        pure
        returns (uint256)
    {
        if (debtValue == 0 || targetHealth == 0) return 0;
        uint256 targetDebt = liquidationValue.mulDivDown(WAD, targetHealth);
        return debtValue > targetDebt ? debtValue - targetDebt : 0;
    }

    function reserveCoverage(uint256 liquidAssets, uint256 reserves, uint256 stressedOutflow)
        external
        pure
        returns (uint256 availableAfterReserves, uint256 coverageWad, uint256 shortfall)
    {
        availableAfterReserves = liquidAssets > reserves ? liquidAssets - reserves : 0;
        coverageWad = _ratio(availableAfterReserves, stressedOutflow);
        shortfall =
            stressedOutflow > availableAfterReserves ? stressedOutflow - availableAfterReserves : 0;
    }

    function correlatedShock(uint256 baseShockBps, uint256 correlationWad, uint256 contagionBps)
        external
        pure
        returns (uint256)
    {
        _validateBps(baseShockBps);
        _validateBps(contagionBps);
        if (correlationWad > WAD) revert InvalidBps(correlationWad);
        uint256 addition = uint256(contagionBps).mulDivDown(correlationWad, WAD);
        uint256 combined = baseShockBps + addition;
        return combined > BPS ? BPS : combined;
    }
}
