// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IRateModel } from "../interfaces/IRateModel.sol";
import { DebtMath } from "../libraries/DebtMath.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { PercentageMath } from "../libraries/PercentageMath.sol";

/// @title AstralRateModel
/// @notice Two-slope variable rate curve expressed in RAY units per second.
contract AstralRateModel is IRateModel {
    using FixedPointMath for uint256;
    using PercentageMath for uint256;

    uint256 public constant RAY = 1e27;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    uint256 public immutable optimalUtilizationRay;
    uint256 public immutable baseRatePerYearRay;
    uint256 public immutable slopeOnePerYearRay;
    uint256 public immutable slopeTwoPerYearRay;

    error InvalidRateParameters();

    constructor(
        uint256 optimalUtilizationRay_,
        uint256 baseRatePerYearRay_,
        uint256 slopeOnePerYearRay_,
        uint256 slopeTwoPerYearRay_
    ) {
        if (optimalUtilizationRay_ == 0 || optimalUtilizationRay_ >= RAY) {
            revert InvalidRateParameters();
        }
        optimalUtilizationRay = optimalUtilizationRay_;
        baseRatePerYearRay = baseRatePerYearRay_;
        slopeOnePerYearRay = slopeOnePerYearRay_;
        slopeTwoPerYearRay = slopeTwoPerYearRay_;
    }

    function getBorrowRate(uint256 cash, uint256 totalBorrow, uint256 reserves)
        external
        view
        override
        returns (uint256)
    {
        uint256 utilization = DebtMath.utilizationRay(cash, totalBorrow, reserves);
        return _borrowRatePerSecond(utilization);
    }

    function getSupplyRate(
        uint256 cash,
        uint256 totalBorrow,
        uint256 reserves,
        uint256 reserveFactorBps
    ) external view override returns (uint256) {
        uint256 utilization = DebtMath.utilizationRay(cash, totalBorrow, reserves);
        uint256 borrowRate = _borrowRatePerSecond(utilization);
        uint256 supplierRate = borrowRate.rayMulDown(utilization);
        return supplierRate.percentMulDown(10_000 - reserveFactorBps);
    }

    function annualizedBorrowRate(uint256 cash, uint256 totalBorrow, uint256 reserves)
        external
        view
        returns (uint256)
    {
        uint256 utilization = DebtMath.utilizationRay(cash, totalBorrow, reserves);
        return _borrowRatePerYear(utilization);
    }

    function utilizationRay(uint256 cash, uint256 totalBorrow, uint256 reserves)
        external
        pure
        returns (uint256)
    {
        return DebtMath.utilizationRay(cash, totalBorrow, reserves);
    }

    function _borrowRatePerSecond(uint256 utilization) internal view returns (uint256) {
        return _borrowRatePerYear(utilization) / SECONDS_PER_YEAR;
    }

    function _borrowRatePerYear(uint256 utilization) internal view returns (uint256) {
        if (utilization <= optimalUtilizationRay) {
            uint256 normalized = utilization.rayDivDown(optimalUtilizationRay);
            return baseRatePerYearRay + slopeOnePerYearRay.rayMulDown(normalized);
        }
        uint256 excess = utilization - optimalUtilizationRay;
        uint256 excessRatio = excess.rayDivDown(RAY - optimalUtilizationRay);
        return baseRatePerYearRay + slopeOnePerYearRay + slopeTwoPerYearRay.rayMulDown(excessRatio);
    }
}
