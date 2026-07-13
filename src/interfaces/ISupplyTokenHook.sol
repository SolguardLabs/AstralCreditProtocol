// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface ISupplyTokenHook {
    function validateSupplyTokenTransfer(
        address asset,
        address from,
        address to,
        uint256 shares,
        uint256 fromBalanceBefore,
        uint256 totalSupplyBefore
    ) external view;
}
