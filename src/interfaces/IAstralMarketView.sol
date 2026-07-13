// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralTypes } from "../libraries/AstralTypes.sol";

interface IAstralMarketView {
    function marketCount() external view returns (uint256);
    function marketAt(uint256 index) external view returns (address);
    function getMarketConfig(address asset) external view returns (AstralTypes.MarketConfig memory);
    function getMarketState(address asset) external view returns (AstralTypes.MarketState memory);
    function getDebtPosition(address asset, address account)
        external
        view
        returns (AstralTypes.DebtPosition memory);
    function getAccountLiquidity(address account)
        external
        view
        returns (AstralTypes.AccountLiquidity memory);
    function borrowBalance(address asset, address account) external view returns (uint256);
    function supplyBalance(address asset, address account) external view returns (uint256);
    function priceOf(address asset) external view returns (AstralTypes.PriceData memory);
    function availableLiquidity(address asset) external view returns (uint256);
    function previewBorrowIndex(address asset) external view returns (uint256);
    function exchangeRate(address asset) external view returns (uint256);
    function isMarketListed(address asset) external view returns (bool);
    function isMarketActive(address asset) external view returns (bool);
}
