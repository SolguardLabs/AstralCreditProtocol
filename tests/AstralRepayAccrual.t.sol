// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralTypes } from "../src/libraries/AstralTypes.sol";
import { AstralTestBase } from "./helpers/AstralTestBase.sol";

contract AstralRepayAccrualTest is AstralTestBase {
    function testAccrualIncreasesBorrowIndexAndDebt() public {
        _openPosition(100 ether, 100_000 * USDC_UNIT);

        vm.warp(block.timestamp + 30 days);

        uint256 previewDebt = market.borrowBalance(address(usdc), borrower);
        assertGt(previewDebt, 100_000 * USDC_UNIT);

        uint256 index = market.accrueInterest(address(usdc));
        AstralTypes.MarketState memory state = market.getMarketState(address(usdc));

        assertGt(index, RAY);
        assertGt(state.totalBorrowAssets, 100_000 * USDC_UNIT);
        assertGt(state.totalReserves, 0);
    }

    function testRepayReducesDebtAfterAccrual() public {
        _openPosition(100 ether, 100_000 * USDC_UNIT);
        vm.warp(block.timestamp + 45 days);

        uint256 debtBefore = market.borrowBalance(address(usdc), borrower);
        (uint256 paid, uint256 remaining) = _repay(borrower, 10_000 * USDC_UNIT, borrower);

        assertEq(paid, 10_000 * USDC_UNIT);
        assertEq(remaining, market.borrowBalance(address(usdc), borrower));
        assertApproxEqAbs(remaining + paid, debtBefore, 2);
    }

    function testFullRepayClearsPosition() public {
        _openPosition(100 ether, 60_000 * USDC_UNIT);
        vm.warp(block.timestamp + 10 days);

        uint256 debt = market.borrowBalance(address(usdc), borrower);
        usdc.mint(borrower, debt);
        vm.startPrank(borrower);
        usdc.approve(address(market), debt);
        (uint256 paid, uint256 remaining) = market.repay(address(usdc), type(uint256).max, borrower);
        vm.stopPrank();

        assertEq(paid, debt);
        assertEq(remaining, 0);
        assertEq(market.borrowBalance(address(usdc), borrower), 0);
    }
}
