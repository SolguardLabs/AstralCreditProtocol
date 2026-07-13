// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralTypes } from "../src/libraries/AstralTypes.sol";
import { AstralTestBase } from "./helpers/AstralTestBase.sol";

contract AstralLiquidationTest is AstralTestBase {
    function testPriceMoveCanMakePositionLiquidatable() public {
        _openPosition(100 ether, 100_000 * USDC_UNIT);

        AstralTypes.AccountLiquidity memory beforeMove = riskEngine.getAccountLiquidity(borrower);
        assertGt(beforeMove.healthFactor, WAD);

        _setWethPrice(1200 * PRICE_UNIT);
        AstralTypes.AccountLiquidity memory afterMove = riskEngine.getAccountLiquidity(borrower);

        assertLt(afterMove.healthFactor, WAD);
        assertTrue(riskEngine.isLiquidatable(borrower));
    }

    function testPartialLiquidationRepaysDebtAndTransfersCollateralShares() public {
        _openPosition(100 ether, 100_000 * USDC_UNIT);
        _setWethPrice(1200 * PRICE_UNIT);
        _fundLiquidator(20_000 * USDC_UNIT);

        uint256 borrowerDebtBefore = market.borrowBalance(address(usdc), borrower);
        uint256 borrowerCollateralBefore = market.supplyBalance(address(weth), borrower);
        uint256 liquidatorCollateralBefore = market.supplyBalance(address(weth), liquidator);

        vm.prank(liquidator);
        (uint256 paid, uint256 sharesSeized) =
            market.liquidate(address(weth), address(usdc), borrower, 10_000 * USDC_UNIT);

        assertEq(paid, 10_000 * USDC_UNIT);
        assertGt(sharesSeized, 0);
        assertEq(market.borrowBalance(address(usdc), borrower), borrowerDebtBefore - paid);
        assertLt(market.supplyBalance(address(weth), borrower), borrowerCollateralBefore);
        assertGt(market.supplyBalance(address(weth), liquidator), liquidatorCollateralBefore);
    }

    function testLiquidationQuoteRespectsCloseFactor() public {
        _openPosition(100 ether, 100_000 * USDC_UNIT);
        _setWethPrice(1000 * PRICE_UNIT);

        AstralTypes.LiquidationQuote memory quote = riskEngine.liquidationQuote(
            address(borrower), address(weth), address(usdc), 80_000 * USDC_UNIT
        );

        assertEq(quote.repayAssets, 50_000 * USDC_UNIT);
        assertGt(quote.collateralAssets, 0);
        assertGt(quote.appliedBonusBps, 800);
    }
}
