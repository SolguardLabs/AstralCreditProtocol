// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralTypes } from "../src/libraries/AstralTypes.sol";
import { AstralTestBase } from "./helpers/AstralTestBase.sol";

contract AstralOracleRiskTest is AstralTestBase {
    function testHealthFactorTracksCollateralPrice() public {
        _openPosition(100 ether, 80_000 * USDC_UNIT);

        AstralTypes.AccountLiquidity memory highPrice = riskEngine.getAccountLiquidity(borrower);
        _setWethPrice(1400 * PRICE_UNIT);
        AstralTypes.AccountLiquidity memory lowerPrice = riskEngine.getAccountLiquidity(borrower);

        assertGt(highPrice.healthFactor, lowerPrice.healthFactor);
        assertGt(lowerPrice.healthFactor, WAD);
    }

    function testOraclePriceIsExposedThroughMarketView() public view {
        AstralTypes.PriceData memory price = market.priceOf(address(weth));

        assertEq(price.price, 2000 * PRICE_UNIT);
        assertEq(price.decimals, 8);
        assertTrue(price.valid);
    }

    function testStaleOraclePriceRevertsRiskRead() public {
        _openPosition(100 ether, 50_000 * USDC_UNIT);
        vm.warp(block.timestamp + 366 days);

        vm.expectRevert();
        riskEngine.getAccountLiquidity(borrower);
    }
}
