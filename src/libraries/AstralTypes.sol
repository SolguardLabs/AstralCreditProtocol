// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title AstralTypes
/// @notice Shared structs used by Astral credit markets, risk modules, views and adapters.
library AstralTypes {
    enum MarketStatus {
        Unlisted,
        Active,
        Frozen,
        Deprecated
    }

    struct MarketConfig {
        address supplyToken;
        address priceOracle;
        address rateModel;
        uint128 supplyCap;
        uint128 borrowCap;
        uint40 priceMaxAge;
        uint16 loanToValueBps;
        uint16 liquidationThresholdBps;
        uint16 liquidationBonusBps;
        uint16 reserveFactorBps;
        uint16 closeFactorBps;
        uint8 assetDecimals;
        MarketStatus status;
        bool borrowingEnabled;
        bool collateralEnabled;
    }

    struct MarketState {
        uint128 totalSupplyAssets;
        uint128 totalBorrowAssets;
        uint128 totalReserves;
        uint128 borrowIndex;
        uint128 supplyIndex;
        uint40 lastAccrual;
    }

    struct DebtPosition {
        uint128 principal;
        uint128 interestIndex;
        uint40 lastUpdate;
    }

    struct PriceData {
        uint256 price;
        uint8 decimals;
        uint256 updatedAt;
        bool valid;
    }

    struct AccountLiquidity {
        uint256 collateralValue;
        uint256 borrowCapacity;
        uint256 liquidationCollateralValue;
        uint256 debtValue;
        uint256 healthFactor;
        uint256 availableBorrow;
        uint256 shortfall;
        uint256 marketCount;
    }

    struct AssetLiquidity {
        address asset;
        uint256 collateralAssets;
        uint256 debtAssets;
        uint256 collateralValue;
        uint256 debtValue;
        uint256 borrowCapacity;
        uint256 liquidationCapacity;
        uint256 price;
        uint8 priceDecimals;
    }

    struct LiquidationQuote {
        uint256 repayAssets;
        uint256 collateralAssets;
        uint256 repayValue;
        uint256 seizeValue;
        uint256 beforeHealthFactor;
        uint256 closeFactorBps;
        uint256 appliedBonusBps;
    }

    struct MarketSnapshot {
        address asset;
        address supplyToken;
        uint256 cash;
        uint256 totalSupplyAssets;
        uint256 totalBorrowAssets;
        uint256 totalReserves;
        uint256 borrowIndex;
        uint256 supplyIndex;
        uint256 utilization;
        uint256 borrowRate;
        uint256 supplyRate;
        uint256 exchangeRate;
        uint256 price;
        uint8 priceDecimals;
        MarketStatus status;
        bool borrowingEnabled;
        bool collateralEnabled;
    }

    struct RiskParameters {
        uint16 loanToValueBps;
        uint16 liquidationThresholdBps;
        uint16 liquidationBonusBps;
        uint16 reserveFactorBps;
        uint16 closeFactorBps;
        bool borrowingEnabled;
        bool collateralEnabled;
    }

    struct MarketCaps {
        uint128 supplyCap;
        uint128 borrowCap;
    }

    struct OracleParameters {
        address priceOracle;
        uint40 priceMaxAge;
    }

    struct InterestPreview {
        uint256 elapsed;
        uint256 borrowRate;
        uint256 supplyRate;
        uint256 interestAccrued;
        uint256 reservesAccrued;
        uint256 nextBorrowIndex;
        uint256 nextSupplyIndex;
        uint256 nextTotalBorrow;
        uint256 nextTotalSupply;
    }

    struct TransferValidation {
        address asset;
        address from;
        address to;
        uint256 shares;
        uint256 assets;
        uint256 fromBalanceBefore;
        uint256 totalShares;
    }
}
