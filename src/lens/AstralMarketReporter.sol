// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IAstralMarketView } from "../interfaces/IAstralMarketView.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IRateModel } from "../interfaces/IRateModel.sol";
import { AstralTypes } from "../libraries/AstralTypes.sol";
import { DebtMath } from "../libraries/DebtMath.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { MarketMath } from "../libraries/MarketMath.sol";

/// @title AstralMarketReporter
/// @notice Compact market reports intended for scripts and keeper health checks.
contract AstralMarketReporter {
    using FixedPointMath for uint256;

    struct CapacityReport {
        address asset;
        address supplyToken;
        uint256 liquidAssets;
        uint256 supplyRoom;
        uint256 borrowRoom;
        uint256 utilizationRay;
        uint256 debtToSupplyWad;
        uint256 reserveShareWad;
        uint256 supplyCapUsageWad;
        uint256 borrowCapUsageWad;
        bool canSupplyOneUnit;
        bool canBorrowOneUnit;
    }

    struct RateReport {
        address asset;
        uint256 borrowRatePerSecondRay;
        uint256 supplyRatePerSecondRay;
        uint256 borrowRatePerYearRay;
        uint256 supplyRatePerYearRay;
        uint256 borrowIndex;
        uint256 supplyIndex;
        uint256 lastAccrual;
    }

    IAstralMarketView public immutable market;

    constructor(IAstralMarketView market_) {
        market = market_;
    }

    function capacityReports() external view returns (CapacityReport[] memory reports) {
        uint256 count = market.marketCount();
        reports = new CapacityReport[](count);
        for (uint256 i = 0; i < count; ++i) {
            reports[i] = capacityReport(market.marketAt(i));
        }
    }

    function capacityReport(address asset) public view returns (CapacityReport memory report) {
        AstralTypes.MarketConfig memory config = market.getMarketConfig(asset);
        AstralTypes.MarketState memory state = market.getMarketState(asset);
        uint256 cash = IERC20(asset).balanceOf(address(market));

        report.asset = asset;
        report.supplyToken = config.supplyToken;
        report.liquidAssets = MarketMath.availableLiquidity(cash, state.totalReserves);
        report.supplyRoom = MarketMath.supplyCapacity(state.totalSupplyAssets, config.supplyCap);
        report.borrowRoom = MarketMath.borrowableLiquidity(
            cash, state.totalBorrowAssets, state.totalReserves, config.borrowCap
        );
        report.utilizationRay =
            DebtMath.utilizationRay(cash, state.totalBorrowAssets, state.totalReserves);
        report.debtToSupplyWad =
            MarketMath.debtToSupply(state.totalBorrowAssets, state.totalSupplyAssets);
        report.reserveShareWad =
            MarketMath.reserveShare(state.totalReserves, state.totalSupplyAssets);
        report.supplyCapUsageWad =
            MarketMath.capUtilizationAfterSupply(state.totalSupplyAssets, config.supplyCap, 0);
        report.borrowCapUsageWad =
            MarketMath.capUtilizationAfterBorrow(state.totalBorrowAssets, config.borrowCap, 0);
        report.canSupplyOneUnit = MarketMath.canSupply(config, state, 1);
        report.canBorrowOneUnit = MarketMath.canBorrow(config, state, cash, 1);
    }

    function rateReports() external view returns (RateReport[] memory reports) {
        uint256 count = market.marketCount();
        reports = new RateReport[](count);
        for (uint256 i = 0; i < count; ++i) {
            reports[i] = rateReport(market.marketAt(i));
        }
    }

    function rateReport(address asset) public view returns (RateReport memory report) {
        AstralTypes.MarketConfig memory config = market.getMarketConfig(asset);
        AstralTypes.MarketState memory state = market.getMarketState(asset);
        uint256 cash = IERC20(asset).balanceOf(address(market));
        report.asset = asset;
        report.borrowRatePerSecondRay = IRateModel(config.rateModel)
            .getBorrowRate(cash, state.totalBorrowAssets, state.totalReserves);
        report.supplyRatePerSecondRay = IRateModel(config.rateModel)
            .getSupplyRate(
                cash, state.totalBorrowAssets, state.totalReserves, config.reserveFactorBps
            );
        report.borrowRatePerYearRay = report.borrowRatePerSecondRay * 365 days;
        report.supplyRatePerYearRay = report.supplyRatePerSecondRay * 365 days;
        report.borrowIndex = state.borrowIndex;
        report.supplyIndex = state.supplyIndex;
        report.lastAccrual = state.lastAccrual;
    }
}
