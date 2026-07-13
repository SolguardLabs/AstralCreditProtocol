// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralTypes } from "../libraries/AstralTypes.sol";

interface IPriceOracle {
    function latestPrice(address asset) external view returns (AstralTypes.PriceData memory);
}
