// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IAstralMarketView } from "../interfaces/IAstralMarketView.sol";
import { IAstralRiskEngine } from "../interfaces/IAstralRiskEngine.sol";
import { AstralTypes } from "../libraries/AstralTypes.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { PriceMath } from "../libraries/PriceMath.sol";
import { AstralRiskPolicy } from "../risk/AstralRiskPolicy.sol";

/// @title AstralAccountLens
/// @notice Account-level read model for risk desks and liquidation keepers.
contract AstralAccountLens {
    using FixedPointMath for uint256;

    struct AccountMarketPosition {
        address asset;
        address supplyToken;
        uint256 suppliedAssets;
        uint256 borrowedAssets;
        uint256 suppliedValue;
        uint256 borrowedValue;
        uint256 borrowCapacity;
        uint256 liquidationCapacity;
        uint256 price;
        uint8 priceDecimals;
        AstralRiskPolicy.RiskBand riskBand;
    }

    struct AccountSummary {
        AstralTypes.AccountLiquidity liquidity;
        uint256 healthMarginBps;
        uint256 liquidationDistanceBps;
        uint256 borrowHeadroomRatio;
        uint256 liquidationCoverageRatio;
        bool borrowProfileTight;
    }

    IAstralMarketView public immutable market;
    IAstralRiskEngine public immutable riskEngine;

    constructor(IAstralMarketView market_, IAstralRiskEngine riskEngine_) {
        market = market_;
        riskEngine = riskEngine_;
    }

    function summary(address account) public view returns (AccountSummary memory result) {
        result.liquidity = riskEngine.getAccountLiquidity(account);
        result.healthMarginBps = AstralRiskPolicy.healthMarginBps(result.liquidity.healthFactor);
        result.liquidationDistanceBps =
            AstralRiskPolicy.liquidationDistanceBps(result.liquidity.healthFactor);
        result.borrowHeadroomRatio = AstralRiskPolicy.borrowHeadroomRatio(result.liquidity);
        result.liquidationCoverageRatio =
            AstralRiskPolicy.liquidationCoverageRatio(result.liquidity);
        result.borrowProfileTight = AstralRiskPolicy.isBorrowProfileTight(result.liquidity, 500);
    }

    function positions(address account)
        external
        view
        returns (AccountMarketPosition[] memory result)
    {
        uint256 count = market.marketCount();
        result = new AccountMarketPosition[](count);
        for (uint256 i = 0; i < count; ++i) {
            result[i] = position(account, market.marketAt(i));
        }
    }

    function position(address account, address asset)
        public
        view
        returns (AccountMarketPosition memory result)
    {
        AstralTypes.MarketConfig memory config = market.getMarketConfig(asset);
        AstralTypes.PriceData memory price = market.priceOf(asset);
        result.asset = asset;
        result.supplyToken = config.supplyToken;
        result.suppliedAssets = market.supplyBalance(asset, account);
        result.borrowedAssets = market.borrowBalance(asset, account);
        result.price = price.price;
        result.priceDecimals = price.decimals;
        result.riskBand = AstralRiskPolicy.classify(config);

        if (result.suppliedAssets != 0 && config.collateralEnabled) {
            result.suppliedValue = PriceMath.valueOf(
                result.suppliedAssets, config.assetDecimals, price.price, price.decimals
            );
            result.borrowCapacity = AstralRiskPolicy.maximumDebtForCollateral(
                result.suppliedValue, config.loanToValueBps
            );
            result.liquidationCapacity = AstralRiskPolicy.maximumDebtForCollateral(
                result.suppliedValue, config.liquidationThresholdBps
            );
        }

        if (result.borrowedAssets != 0) {
            result.borrowedValue = PriceMath.valueOf(
                result.borrowedAssets, config.assetDecimals, price.price, price.decimals
            );
        }
    }

    function liquidationCandidates(address[] calldata accounts)
        external
        view
        returns (address[] memory candidates, uint256[] memory healthFactors, uint256 count)
    {
        candidates = new address[](accounts.length);
        healthFactors = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; ++i) {
            AstralTypes.AccountLiquidity memory liquidity =
                riskEngine.getAccountLiquidity(accounts[i]);
            if (liquidity.debtValue != 0 && liquidity.healthFactor < 1e18) {
                candidates[count] = accounts[i];
                healthFactors[count] = liquidity.healthFactor;
                ++count;
            }
        }
    }
}
