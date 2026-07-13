// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title FixedPointMath
/// @notice Small fixed point helper library for WAD and RAY arithmetic.
library FixedPointMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_WAD = 5e17;
    uint256 internal constant HALF_RAY = 5e26;

    error DivisionByZero();
    error MulDivOverflow(uint256 x, uint256 y, uint256 denominator);

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function zeroFloorSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    function mulDivDown(uint256 x, uint256 y, uint256 denominator)
        internal
        pure
        returns (uint256 z)
    {
        if (denominator == 0) revert DivisionByZero();
        assembly {
            let mm := mulmod(x, y, not(0))
            let prod0 := mul(x, y)
            let prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            if iszero(prod1) {
                z := div(prod0, denominator)
            }
            if prod1 {
                if iszero(gt(denominator, prod1)) {
                    mstore(0x00, 0x7c5f487d)
                    revert(0x1c, 0x04)
                }
                let remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
                let twos := and(denominator, sub(0, denominator))
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
                prod0 := or(prod0, mul(prod1, twos))
                let inv := xor(mul(3, denominator), 2)
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                inv := mul(inv, sub(2, mul(denominator, inv)))
                z := mul(prod0, inv)
            }
        }
    }

    function mulDivUp(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 z) {
        z = mulDivDown(x, y, denominator);
        if (mulmod(x, y, denominator) != 0) z += 1;
    }

    function wadMulDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    function wadMulUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, y, WAD);
    }

    function wadDivDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y);
    }

    function wadDivUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, WAD, y);
    }

    function rayMulDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, RAY);
    }

    function rayMulUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, y, RAY);
    }

    function rayDivDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, RAY, y);
    }

    function rayDivUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, RAY, y);
    }

    function wadToRay(uint256 value) internal pure returns (uint256) {
        return value * 1e9;
    }

    function rayToWadDown(uint256 value) internal pure returns (uint256) {
        return value / 1e9;
    }

    function rayToWadUp(uint256 value) internal pure returns (uint256) {
        return value == 0 ? 0 : (value - 1) / 1e9 + 1;
    }

    function clamp(uint256 value, uint256 low, uint256 high) internal pure returns (uint256) {
        if (value < low) return low;
        if (value > high) return high;
        return value;
    }

    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a & b) + ((a ^ b) >> 1);
    }
}
