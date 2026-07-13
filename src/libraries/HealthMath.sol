// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FixedPointMath } from "./FixedPointMath.sol";

/// @title HealthMath
/// @notice Small helpers for presenting account health in keeper tooling.
library HealthMath {
    using FixedPointMath for uint256;

    uint256 internal constant WAD = 1e18;

    enum HealthBand {
        NoDebt,
        Critical,
        Warning,
        Stable,
        Strong
    }

    function band(uint256 healthFactor) internal pure returns (HealthBand) {
        if (healthFactor == type(uint256).max) return HealthBand.NoDebt;
        if (healthFactor < WAD) return HealthBand.Critical;
        if (healthFactor < 1.1e18) return HealthBand.Warning;
        if (healthFactor < 1.5e18) return HealthBand.Stable;
        return HealthBand.Strong;
    }

    function distanceToLiquidation(uint256 healthFactor) internal pure returns (uint256) {
        if (healthFactor >= WAD) return healthFactor - WAD;
        return 0;
    }

    function deficitToTarget(
        uint256 liquidationCollateralValue,
        uint256 debtValue,
        uint256 targetHealthFactor
    ) internal pure returns (uint256) {
        if (debtValue == 0) return 0;
        uint256 required = debtValue.wadMulUp(targetHealthFactor);
        return required > liquidationCollateralValue ? required - liquidationCollateralValue : 0;
    }

    function debtAtTarget(uint256 liquidationCollateralValue, uint256 targetHealthFactor)
        internal
        pure
        returns (uint256)
    {
        if (targetHealthFactor == 0) return type(uint256).max;
        return liquidationCollateralValue.wadDivDown(targetHealthFactor);
    }

    function repayToTarget(
        uint256 liquidationCollateralValue,
        uint256 debtValue,
        uint256 targetHealthFactor
    ) internal pure returns (uint256) {
        if (debtValue == 0 || targetHealthFactor == 0) return 0;
        uint256 targetDebt = debtAtTarget(liquidationCollateralValue, targetHealthFactor);
        return debtValue > targetDebt ? debtValue - targetDebt : 0;
    }

    function improves(uint256 beforeHealthFactor, uint256 afterHealthFactor)
        internal
        pure
        returns (bool)
    {
        if (afterHealthFactor == type(uint256).max) return true;
        return afterHealthFactor > beforeHealthFactor;
    }
}
