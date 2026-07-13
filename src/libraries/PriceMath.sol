// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FixedPointMath } from "./FixedPointMath.sol";

/// @title PriceMath
/// @notice Converts asset units and oracle prices into a common WAD value.
library PriceMath {
    using FixedPointMath for uint256;

    uint256 internal constant WAD = 1e18;

    error InvalidDecimals(uint8 decimals);
    error InvalidPrice();

    function valueOf(uint256 amount, uint8 assetDecimals, uint256 price, uint8 priceDecimals)
        internal
        pure
        returns (uint256)
    {
        if (assetDecimals > 36 || priceDecimals > 36) revert InvalidDecimals(assetDecimals);
        if (price == 0) revert InvalidPrice();
        uint256 denominator = 10 ** uint256(assetDecimals);
        uint256 priceScale = 10 ** uint256(priceDecimals);
        uint256 assetValue = amount.mulDivDown(price, denominator);
        return assetValue.mulDivDown(WAD, priceScale);
    }

    function amountFromValue(
        uint256 value,
        uint8 assetDecimals,
        uint256 price,
        uint8 priceDecimals,
        bool roundUp
    ) internal pure returns (uint256) {
        if (assetDecimals > 36 || priceDecimals > 36) {
            revert InvalidDecimals(assetDecimals);
        }
        if (price == 0) revert InvalidPrice();
        uint256 numerator = value * (10 ** uint256(assetDecimals));
        uint256 scaled = roundUp
            ? numerator.mulDivUp(10 ** uint256(priceDecimals), WAD)
            : numerator.mulDivDown(10 ** uint256(priceDecimals), WAD);
        return roundUp ? scaled.mulDivUp(1, price) : scaled / price;
    }

    function normalizePrice(uint256 price, uint8 sourceDecimals, uint8 targetDecimals)
        internal
        pure
        returns (uint256)
    {
        if (sourceDecimals > 36 || targetDecimals > 36) revert InvalidDecimals(sourceDecimals);
        if (price == 0) revert InvalidPrice();
        if (sourceDecimals == targetDecimals) return price;
        if (sourceDecimals < targetDecimals) {
            return price * (10 ** uint256(targetDecimals - sourceDecimals));
        }
        return price / (10 ** uint256(sourceDecimals - targetDecimals));
    }

    function scaleAmount(uint256 amount, uint8 fromDecimals, uint8 toDecimals)
        internal
        pure
        returns (uint256)
    {
        if (fromDecimals > 36 || toDecimals > 36) revert InvalidDecimals(fromDecimals);
        if (fromDecimals == toDecimals) return amount;
        if (fromDecimals < toDecimals) return amount * (10 ** uint256(toDecimals - fromDecimals));
        return amount / (10 ** uint256(fromDecimals - toDecimals));
    }
}
