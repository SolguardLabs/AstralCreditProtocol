// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FixedPointMath } from "./FixedPointMath.sol";

/// @title ShareMath
/// @notice Conversion helpers for collateral vault shares.
library ShareMath {
    using FixedPointMath for uint256;

    uint256 internal constant WAD = 1e18;

    function assetsToShares(uint256 assets, uint256 totalAssets, uint256 totalShares, bool roundUp)
        internal
        pure
        returns (uint256)
    {
        if (assets == 0) return 0;
        if (totalAssets == 0 || totalShares == 0) return assets;
        return roundUp
            ? assets.mulDivUp(totalShares, totalAssets)
            : assets.mulDivDown(totalShares, totalAssets);
    }

    function sharesToAssets(uint256 shares, uint256 totalAssets, uint256 totalShares, bool roundUp)
        internal
        pure
        returns (uint256)
    {
        if (shares == 0) return 0;
        if (totalShares == 0) return shares;
        return roundUp
            ? shares.mulDivUp(totalAssets, totalShares)
            : shares.mulDivDown(totalAssets, totalShares);
    }

    function exchangeRate(uint256 totalAssets, uint256 totalShares)
        internal
        pure
        returns (uint256)
    {
        if (totalShares == 0) return WAD;
        return totalAssets.mulDivDown(WAD, totalShares);
    }

    function previewMint(uint256 shares, uint256 totalAssets, uint256 totalShares)
        internal
        pure
        returns (uint256)
    {
        if (totalAssets == 0 || totalShares == 0) return shares;
        return shares.mulDivUp(totalAssets, totalShares);
    }

    function previewWithdraw(uint256 assets, uint256 totalAssets, uint256 totalShares)
        internal
        pure
        returns (uint256)
    {
        return assetsToShares(assets, totalAssets, totalShares, true);
    }

    function previewRedeem(uint256 shares, uint256 totalAssets, uint256 totalShares)
        internal
        pure
        returns (uint256)
    {
        return sharesToAssets(shares, totalAssets, totalShares, false);
    }
}
