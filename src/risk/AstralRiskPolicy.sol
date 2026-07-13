// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralTypes } from "../libraries/AstralTypes.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { PercentageMath } from "../libraries/PercentageMath.sol";

/// @title AstralRiskPolicy
/// @notice Stateless policy helpers used by off-chain governance review and local tooling.
library AstralRiskPolicy {
    using FixedPointMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;

    enum RiskBand {
        Empty,
        Conservative,
        Balanced,
        Aggressive,
        Restricted
    }

    struct PolicyView {
        RiskBand band;
        uint256 collateralBufferBps;
        uint256 liquidationSpreadBps;
        uint256 reserveShareBps;
        uint256 closePressureBps;
        bool borrowable;
        bool usableAsCollateral;
    }

    error InvalidPolicy();

    function describe(AstralTypes.MarketConfig memory config)
        internal
        pure
        returns (PolicyView memory view_)
    {
        view_.band = classify(config);
        view_.borrowable = config.borrowingEnabled;
        view_.usableAsCollateral = config.collateralEnabled;
        view_.reserveShareBps = config.reserveFactorBps;
        view_.closePressureBps = config.closeFactorBps;
        if (config.liquidationThresholdBps >= config.loanToValueBps) {
            view_.collateralBufferBps = config.liquidationThresholdBps - config.loanToValueBps;
        }
        view_.liquidationSpreadBps = config.liquidationBonusBps;
    }

    function classify(AstralTypes.MarketConfig memory config) internal pure returns (RiskBand) {
        if (config.status == AstralTypes.MarketStatus.Unlisted) return RiskBand.Empty;
        if (!config.borrowingEnabled && !config.collateralEnabled) return RiskBand.Restricted;
        if (config.loanToValueBps <= 5000 && config.liquidationThresholdBps <= 6500) {
            return RiskBand.Conservative;
        }
        if (config.loanToValueBps <= 7500 && config.liquidationThresholdBps <= 8500) {
            return RiskBand.Balanced;
        }
        return RiskBand.Aggressive;
    }

    function validate(AstralTypes.MarketConfig memory config) internal pure {
        if (config.loanToValueBps > config.liquidationThresholdBps) revert InvalidPolicy();
        if (config.liquidationThresholdBps > BPS) revert InvalidPolicy();
        if (config.liquidationBonusBps > 5000) revert InvalidPolicy();
        if (config.reserveFactorBps > BPS) revert InvalidPolicy();
        if (config.closeFactorBps == 0 || config.closeFactorBps > BPS) revert InvalidPolicy();
        if (config.borrowCap > config.supplyCap) revert InvalidPolicy();
    }

    function healthMarginBps(uint256 healthFactor) internal pure returns (uint256) {
        if (healthFactor == type(uint256).max) return type(uint256).max;
        if (healthFactor <= WAD) return 0;
        return (healthFactor - WAD).mulDivDown(BPS, WAD);
    }

    function liquidationDistanceBps(uint256 healthFactor) internal pure returns (uint256) {
        if (healthFactor >= WAD) return 0;
        return (WAD - healthFactor).mulDivUp(BPS, WAD);
    }

    function borrowHeadroomRatio(AstralTypes.AccountLiquidity memory liquidity)
        internal
        pure
        returns (uint256)
    {
        if (liquidity.borrowCapacity == 0) return 0;
        return liquidity.availableBorrow.mulDivDown(WAD, liquidity.borrowCapacity);
    }

    function liquidationCoverageRatio(AstralTypes.AccountLiquidity memory liquidity)
        internal
        pure
        returns (uint256)
    {
        if (liquidity.debtValue == 0) return type(uint256).max;
        return liquidity.liquidationCollateralValue.mulDivDown(WAD, liquidity.debtValue);
    }

    function minimumCollateralForDebt(uint256 debtValue, uint256 liquidationThresholdBps)
        internal
        pure
        returns (uint256)
    {
        if (debtValue == 0) return 0;
        return debtValue.percentDivUp(liquidationThresholdBps);
    }

    function maximumDebtForCollateral(uint256 collateralValue, uint256 loanToValueBps)
        internal
        pure
        returns (uint256)
    {
        return collateralValue.percentMulDown(loanToValueBps);
    }

    function isBorrowProfileTight(
        AstralTypes.AccountLiquidity memory liquidity,
        uint256 minHeadroomBps
    ) internal pure returns (bool) {
        if (liquidity.debtValue == 0) return false;
        if (liquidity.borrowCapacity <= liquidity.debtValue) return true;
        uint256 headroom = (liquidity.borrowCapacity - liquidity.debtValue)
        .mulDivDown(BPS, liquidity.borrowCapacity);
        return headroom < minHeadroomBps;
    }
}
