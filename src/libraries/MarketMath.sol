// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralTypes } from "./AstralTypes.sol";
import { DebtMath } from "./DebtMath.sol";
import { FixedPointMath } from "./FixedPointMath.sol";
import { PercentageMath } from "./PercentageMath.sol";
import { ShareMath } from "./ShareMath.sol";

/// @title MarketMath
/// @notice Pure helpers for market-level accounting, limits and dashboard metrics.
library MarketMath {
    using FixedPointMath for uint256;
    using PercentageMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    function availableLiquidity(uint256 cash, uint256 reserves) internal pure returns (uint256) {
        return cash > reserves ? cash - reserves : 0;
    }

    function utilization(uint256 cash, uint256 totalBorrow, uint256 reserves)
        internal
        pure
        returns (uint256)
    {
        return DebtMath.utilizationRay(cash, totalBorrow, reserves);
    }

    function borrowableLiquidity(
        uint256 cash,
        uint256 totalBorrow,
        uint256 reserves,
        uint256 borrowCap
    ) internal pure returns (uint256) {
        uint256 liquid = availableLiquidity(cash, reserves);
        if (totalBorrow >= borrowCap) return 0;
        uint256 capRoom = borrowCap - totalBorrow;
        return liquid < capRoom ? liquid : capRoom;
    }

    function supplyCapacity(uint256 totalSupply, uint256 supplyCap)
        internal
        pure
        returns (uint256)
    {
        return totalSupply >= supplyCap ? 0 : supplyCap - totalSupply;
    }

    function reserveShare(uint256 totalReserves, uint256 totalSupplyAssets)
        internal
        pure
        returns (uint256)
    {
        if (totalSupplyAssets == 0) return 0;
        return totalReserves.mulDivDown(WAD, totalSupplyAssets);
    }

    function debtToSupply(uint256 totalBorrow, uint256 totalSupplyAssets)
        internal
        pure
        returns (uint256)
    {
        if (totalSupplyAssets == 0) return 0;
        return totalBorrow.mulDivDown(WAD, totalSupplyAssets);
    }

    function vaultEquity(uint256 totalSupplyAssets, uint256 totalBorrow, uint256 cash)
        internal
        pure
        returns (uint256)
    {
        uint256 economicAssets = cash + totalBorrow;
        return economicAssets > totalSupplyAssets ? economicAssets - totalSupplyAssets : 0;
    }

    function accountShareOfVault(uint256 accountShares, uint256 totalShares)
        internal
        pure
        returns (uint256)
    {
        if (totalShares == 0) return 0;
        return accountShares.mulDivDown(WAD, totalShares);
    }

    function accountAssets(
        uint256 accountShares,
        AstralTypes.MarketState memory state,
        uint256 totalShares
    ) internal pure returns (uint256) {
        return ShareMath.sharesToAssets(accountShares, state.totalSupplyAssets, totalShares, false);
    }

    function requiredSharesForAssets(
        uint256 assets,
        AstralTypes.MarketState memory state,
        uint256 totalShares
    ) internal pure returns (uint256) {
        return ShareMath.assetsToShares(assets, state.totalSupplyAssets, totalShares, true);
    }

    function canSupply(
        AstralTypes.MarketConfig memory config,
        AstralTypes.MarketState memory state,
        uint256 assets
    ) internal pure returns (bool) {
        if (config.status != AstralTypes.MarketStatus.Active) {
            return false;
        }
        if (assets == 0) return false;
        return uint256(state.totalSupplyAssets) + assets <= config.supplyCap;
    }

    function canBorrow(
        AstralTypes.MarketConfig memory config,
        AstralTypes.MarketState memory state,
        uint256 cash,
        uint256 assets
    ) internal pure returns (bool) {
        if (config.status != AstralTypes.MarketStatus.Active) return false;
        if (!config.borrowingEnabled || assets == 0) return false;
        if (uint256(state.totalBorrowAssets) + assets > config.borrowCap) return false;
        return assets <= availableLiquidity(cash, state.totalReserves);
    }

    function maxWithdrawFromShares(
        uint256 accountShares,
        AstralTypes.MarketState memory state,
        uint256 totalShares,
        uint256 cash,
        uint256 reserves
    ) internal pure returns (uint256) {
        uint256 assets = accountAssets(accountShares, state, totalShares);
        uint256 liquid = availableLiquidity(cash, reserves);
        return assets < liquid ? assets : liquid;
    }

    function capUtilizationAfterBorrow(uint256 totalBorrow, uint256 borrowCap, uint256 amount)
        internal
        pure
        returns (uint256)
    {
        if (borrowCap == 0) return 0;
        return (totalBorrow + amount).mulDivDown(WAD, borrowCap);
    }

    function capUtilizationAfterSupply(uint256 totalSupply, uint256 supplyCap, uint256 amount)
        internal
        pure
        returns (uint256)
    {
        if (supplyCap == 0) return 0;
        return (totalSupply + amount).mulDivDown(WAD, supplyCap);
    }
}
