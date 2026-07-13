// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IRateModel {
    function getBorrowRate(uint256 cash, uint256 totalBorrow, uint256 reserves)
        external
        view
        returns (uint256);

    function getSupplyRate(
        uint256 cash,
        uint256 totalBorrow,
        uint256 reserves,
        uint256 reserveFactorBps
    ) external view returns (uint256);
}
