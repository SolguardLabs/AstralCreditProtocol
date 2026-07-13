// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralTypes } from "./AstralTypes.sol";
import { FixedPointMath } from "./FixedPointMath.sol";
import { PercentageMath } from "./PercentageMath.sol";

/// @title DebtMath
/// @notice Interest-index accounting for variable-rate borrow positions.
library DebtMath {
    using FixedPointMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    function currentDebt(AstralTypes.DebtPosition memory position, uint256 currentIndex)
        internal
        pure
        returns (uint256)
    {
        if (position.principal == 0) return 0;
        if (position.interestIndex == 0 || position.interestIndex == currentIndex) {
            return position.principal;
        }
        return uint256(position.principal).mulDivUp(currentIndex, position.interestIndex);
    }

    function nextIndex(uint256 currentIndex, uint256 ratePerSecondRay, uint256 elapsed)
        internal
        pure
        returns (uint256)
    {
        if (elapsed == 0 || ratePerSecondRay == 0) return currentIndex;
        uint256 factor = linearInterestFactor(ratePerSecondRay, elapsed);
        return currentIndex.rayMulDown(factor);
    }

    function linearInterestFactor(uint256 ratePerSecondRay, uint256 elapsed)
        internal
        pure
        returns (uint256)
    {
        if (elapsed == 0 || ratePerSecondRay == 0) return RAY;
        return RAY + ratePerSecondRay * elapsed;
    }

    function utilizationRay(uint256 cash, uint256 totalBorrow, uint256 reserves)
        internal
        pure
        returns (uint256)
    {
        if (totalBorrow == 0) return 0;
        uint256 available = cash > reserves ? cash - reserves : 0;
        return totalBorrow.mulDivDown(RAY, available + totalBorrow);
    }

    function reserveAccrual(uint256 interestAccrued, uint256 reserveFactorBps)
        internal
        pure
        returns (uint256)
    {
        return interestAccrued.percentMulDown(reserveFactorBps);
    }

    function accrueTotals(
        AstralTypes.MarketState memory state,
        uint256 borrowRateRay,
        uint256 supplyRateRay,
        uint256 reserveFactorBps,
        uint256 elapsed,
        uint256 timestamp
    )
        internal
        pure
        returns (AstralTypes.MarketState memory updated, AstralTypes.InterestPreview memory preview)
    {
        updated = state;
        preview.elapsed = elapsed;
        preview.borrowRate = borrowRateRay;
        preview.supplyRate = supplyRateRay;

        if (elapsed == 0) {
            preview.nextBorrowIndex = state.borrowIndex;
            preview.nextSupplyIndex = state.supplyIndex;
            preview.nextTotalBorrow = state.totalBorrowAssets;
            preview.nextTotalSupply = state.totalSupplyAssets;
            return (updated, preview);
        }

        updated.lastAccrual = uint40(timestamp);
        if (state.totalBorrowAssets == 0) {
            preview.nextBorrowIndex = state.borrowIndex;
            preview.nextSupplyIndex = state.supplyIndex;
            preview.nextTotalBorrow = state.totalBorrowAssets;
            preview.nextTotalSupply = state.totalSupplyAssets;
            return (updated, preview);
        }

        uint256 growthFactor = linearInterestFactor(borrowRateRay, elapsed);
        uint256 nextBorrowAssets = uint256(state.totalBorrowAssets).rayMulDown(growthFactor);
        uint256 interestAccrued = nextBorrowAssets - state.totalBorrowAssets;
        uint256 reservesAccrued = reserveAccrual(interestAccrued, reserveFactorBps);

        uint256 nextSupplyAssets =
            uint256(state.totalSupplyAssets) + interestAccrued - reservesAccrued;
        uint256 nextBorrowIndex = nextIndex(state.borrowIndex, borrowRateRay, elapsed);
        uint256 nextSupplyIndex = nextIndex(state.supplyIndex, supplyRateRay, elapsed);

        updated.totalBorrowAssets = uint128(nextBorrowAssets);
        updated.totalSupplyAssets = uint128(nextSupplyAssets);
        updated.totalReserves = uint128(uint256(state.totalReserves) + reservesAccrued);
        updated.borrowIndex = uint128(nextBorrowIndex);
        updated.supplyIndex = uint128(nextSupplyIndex);

        preview.interestAccrued = interestAccrued;
        preview.reservesAccrued = reservesAccrued;
        preview.nextBorrowIndex = nextBorrowIndex;
        preview.nextSupplyIndex = nextSupplyIndex;
        preview.nextTotalBorrow = nextBorrowAssets;
        preview.nextTotalSupply = nextSupplyAssets;
    }

    function checkpoint(uint256 debt, uint256 currentIndex, uint256 timestamp)
        internal
        pure
        returns (AstralTypes.DebtPosition memory position)
    {
        position.principal = uint128(debt);
        position.interestIndex = uint128(currentIndex);
        position.lastUpdate = uint40(timestamp);
    }
}
