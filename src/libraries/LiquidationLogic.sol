// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralTypes } from "./AstralTypes.sol";
import { FixedPointMath } from "./FixedPointMath.sol";
import { PercentageMath } from "./PercentageMath.sol";
import { PriceMath } from "./PriceMath.sol";

/// @title LiquidationLogic
/// @notice Pure helpers for liquidation caps, repay limits and collateral conversion.
library LiquidationLogic {
    using FixedPointMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;

    function closeAmount(uint256 debtAssets, uint256 requestedRepay, uint256 closeFactorBps)
        internal
        pure
        returns (uint256)
    {
        uint256 maxClose = debtAssets.percentMulDown(closeFactorBps);
        if (maxClose == 0 && debtAssets != 0) maxClose = 1;
        uint256 repay = requestedRepay < maxClose ? requestedRepay : maxClose;
        return repay < debtAssets ? repay : debtAssets;
    }

    function appliedBonus(uint256 baseBonusBps, uint256 currentHealthFactor)
        internal
        pure
        returns (uint256)
    {
        if (currentHealthFactor >= WAD) return baseBonusBps;
        uint256 severity = (WAD - currentHealthFactor).mulDivDown(1000, WAD);
        uint256 dynamicBonus = baseBonusBps + severity;
        return dynamicBonus > 2500 ? 2500 : dynamicBonus;
    }

    function seizeAssets(
        uint256 repayAssets,
        uint8 debtDecimals,
        uint256 debtPrice,
        uint8 debtPriceDecimals,
        uint8 collateralDecimals,
        uint256 collateralPrice,
        uint8 collateralPriceDecimals,
        uint256 bonusBps
    ) internal pure returns (uint256 collateralAssets, uint256 repayValue, uint256 seizeValue) {
        repayValue = PriceMath.valueOf(repayAssets, debtDecimals, debtPrice, debtPriceDecimals);
        seizeValue = repayValue.addBpsUp(bonusBps);
        collateralAssets = PriceMath.amountFromValue(
            seizeValue, collateralDecimals, collateralPrice, collateralPriceDecimals, true
        );
    }

    function healthFactor(uint256 liquidationCollateralValue, uint256 debtValue)
        internal
        pure
        returns (uint256)
    {
        if (debtValue == 0) return type(uint256).max;
        return liquidationCollateralValue.mulDivDown(WAD, debtValue);
    }

    function availableBorrow(uint256 borrowCapacity, uint256 debtValue)
        internal
        pure
        returns (uint256)
    {
        return borrowCapacity > debtValue ? borrowCapacity - debtValue : 0;
    }

    function shortfall(uint256 liquidationCollateralValue, uint256 debtValue)
        internal
        pure
        returns (uint256)
    {
        return debtValue > liquidationCollateralValue ? debtValue - liquidationCollateralValue : 0;
    }

    function isImprovement(uint256 beforeHealthFactor, uint256 projectedHealthFactor)
        internal
        pure
        returns (bool)
    {
        if (projectedHealthFactor == type(uint256).max) return true;
        return projectedHealthFactor > beforeHealthFactor;
    }
}
