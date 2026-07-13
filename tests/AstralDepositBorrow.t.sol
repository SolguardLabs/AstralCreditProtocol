// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralTestBase } from "./helpers/AstralTestBase.sol";

contract AstralDepositBorrowTest is AstralTestBase {
    function testSupplyMintsVaultSharesAndWithdrawReturnsAssets() public {
        uint256 supplied = 10 ether;
        uint256 shares = _supplyCollateral(borrower, supplied);

        assertEq(aWeth.balanceOf(borrower), shares);
        assertEq(market.supplyBalance(address(weth), borrower), supplied);

        vm.prank(borrower);
        uint256 burned = market.withdraw(address(weth), 2 ether, recipient);

        assertEq(burned, 2 ether);
        assertEq(weth.balanceOf(recipient), 2 ether);
        assertEq(market.supplyBalance(address(weth), borrower), 8 ether);
    }

    function testBorrowUsesCollateralCapacityAndMarketLiquidity() public {
        _supplyCollateral(borrower, 100 ether);

        vm.prank(borrower);
        uint256 accountDebt = market.borrow(address(usdc), 100_000 * USDC_UNIT, borrower);

        assertEq(accountDebt, 100_000 * USDC_UNIT);
        assertEq(usdc.balanceOf(borrower), 100_000 * USDC_UNIT);
        assertEq(market.borrowBalance(address(usdc), borrower), 100_000 * USDC_UNIT);
    }

    function testBorrowAboveCapacityReverts() public {
        _supplyCollateral(borrower, 10 ether);

        vm.prank(borrower);
        vm.expectRevert();
        market.borrow(address(usdc), 50_000 * USDC_UNIT, borrower);
    }

    function testCollateralCannotBeRemovedBelowBorrowCapacity() public {
        _openPosition(100 ether, 100_000 * USDC_UNIT);

        vm.prank(borrower);
        vm.expectRevert();
        market.withdraw(address(weth), 80 ether, borrower);
    }
}
