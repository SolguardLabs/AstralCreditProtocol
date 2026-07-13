// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralTypes } from "../libraries/AstralTypes.sol";

interface IAstralRiskEngine {
    function getAccountLiquidity(address account)
        external
        view
        returns (AstralTypes.AccountLiquidity memory);

    function getAssetLiquidity(address account, address asset)
        external
        view
        returns (AstralTypes.AssetLiquidity memory);

    function healthFactor(address account) external view returns (uint256);
    function isLiquidatable(address account) external view returns (bool);
    function validateBorrow(address account, address debtAsset, uint256 borrowAmount) external view;
    function validateCollateralReduction(address account, address asset, uint256 assets)
        external
        view;

    function liquidationQuote(
        address account,
        address collateralAsset,
        address debtAsset,
        uint256 requestedRepay
    ) external view returns (AstralTypes.LiquidationQuote memory);
}
