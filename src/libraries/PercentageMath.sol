// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FixedPointMath } from "./FixedPointMath.sol";

/// @title PercentageMath
/// @notice Basis point operations used by risk and interest accounting.
library PercentageMath {
    using FixedPointMath for uint256;

    uint256 internal constant BPS = 10_000;

    error InvalidBasisPoints(uint256 bps);

    function percentMulDown(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (bps > BPS) revert InvalidBasisPoints(bps);
        return value.mulDivDown(bps, BPS);
    }

    function percentMulUp(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (bps > BPS) revert InvalidBasisPoints(bps);
        return value.mulDivUp(bps, BPS);
    }

    function percentDivDown(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (bps == 0 || bps > BPS) revert InvalidBasisPoints(bps);
        return value.mulDivDown(BPS, bps);
    }

    function percentDivUp(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (bps == 0 || bps > BPS) revert InvalidBasisPoints(bps);
        return value.mulDivUp(BPS, bps);
    }

    function addBps(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (bps > BPS) revert InvalidBasisPoints(bps);
        return value + value.mulDivDown(bps, BPS);
    }

    function addBpsUp(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (bps > BPS) revert InvalidBasisPoints(bps);
        return value + value.mulDivUp(bps, BPS);
    }

    function subtractBps(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (bps > BPS) revert InvalidBasisPoints(bps);
        return value - value.mulDivDown(bps, BPS);
    }

    function complement(uint256 bps) internal pure returns (uint256) {
        if (bps > BPS) revert InvalidBasisPoints(bps);
        return BPS - bps;
    }

    function weightedAverage(uint256 first, uint256 second, uint256 firstWeightBps)
        internal
        pure
        returns (uint256)
    {
        if (firstWeightBps > BPS) revert InvalidBasisPoints(firstWeightBps);
        return percentMulDown(first, firstWeightBps) + percentMulDown(second, BPS - firstWeightBps);
    }

    function ratioBps(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) return 0;
        uint256 ratio = numerator.mulDivDown(BPS, denominator);
        return ratio > BPS ? BPS : ratio;
    }

    function isWithinBps(uint256 value, uint256 referenceValue, uint256 maxDeviationBps)
        internal
        pure
        returns (bool)
    {
        if (referenceValue == 0) return value == 0;
        uint256 diff = value.absDiff(referenceValue);
        return diff.mulDivDown(BPS, referenceValue) <= maxDeviationBps;
    }
}
