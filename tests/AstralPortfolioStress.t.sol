// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";

import { AstralPortfolioStress } from "../src/risk/AstralPortfolioStress.sol";

contract AstralPortfolioStressTest is Test {
    AstralPortfolioStress internal stress;

    function setUp() public {
        stress = new AstralPortfolioStress();
    }

    function testEvaluatesTwoMarketPortfolio() public view {
        AstralPortfolioStress.MarketShock[] memory shocks =
            new AstralPortfolioStress.MarketShock[](2);
        shocks[0] =
            _shock(address(0xA1), 1_000_000e18, 400_000e18, 300_000e18, 8000, 2000, 500, 1000);
        shocks[1] = _shock(address(0xB2), 500_000e18, 250_000e18, 180_000e18, 7500, 1000, 200, 2000);

        (
            AstralPortfolioStress.PortfolioResult memory portfolio,
            AstralPortfolioStress.MarketResult[] memory markets
        ) = stress.evaluate(shocks);

        assertEq(markets.length, 2);
        assertEq(portfolio.collateralValue, 1_250_000e18);
        assertEq(portfolio.liquidationValue, 977_500e18);
        assertEq(portfolio.debtValue, 675_000e18);
        assertEq(portfolio.liquidAssets, 414_000e18);
        assertGt(portfolio.healthFactor, 1e18);
        assertEq(portfolio.shortfall, 0);
        assertEq(portfolio.largestMarketShareWad, 0.64e18);
    }

    function testClassifiesSevereShortfall() public view {
        AstralPortfolioStress.MarketShock[] memory shocks =
            new AstralPortfolioStress.MarketShock[](1);
        shocks[0] = _shock(address(0xA1), 100_000e18, 90_000e18, 10_000e18, 7000, 3000, 1000, 5000);
        (AstralPortfolioStress.PortfolioResult memory portfolio,) = stress.evaluate(shocks);
        assertGt(portfolio.shortfall, 0);
        assertEq(portfolio.severity, 3);
        assertLt(portfolio.healthFactor, 1e18);
    }

    function testRejectsDuplicateMarket() public {
        AstralPortfolioStress.MarketShock[] memory shocks =
            new AstralPortfolioStress.MarketShock[](2);
        shocks[0] = _shock(address(0xA1), 100, 10, 20, 8000, 0, 0, 0);
        shocks[1] = _shock(address(0xA1), 200, 20, 40, 8000, 0, 0, 0);
        vm.expectRevert(
            abi.encodeWithSelector(AstralPortfolioStress.DuplicateAsset.selector, address(0xA1))
        );
        stress.evaluate(shocks);
    }

    function testReserveCoverageProtectsProtocolReserves() public view {
        (uint256 available, uint256 coverage, uint256 shortfall) =
            stress.reserveCoverage(1_000_000, 250_000, 900_000);
        assertEq(available, 750_000);
        assertEq(coverage, 833_333_333_333_333_333);
        assertEq(shortfall, 150_000);
    }

    function testCorrelationIncreasesCompositeShockWithinCap() public view {
        assertEq(stress.correlatedShock(2000, 0.5e18, 3000), 3500);
        assertEq(stress.correlatedShock(8000, 1e18, 5000), 10_000);
        assertEq(stress.minimumDebtReduction(800_000, 900_000, 1.1e18), 172_728);
    }

    function _shock(
        address asset,
        uint256 collateralValue,
        uint256 debtValue,
        uint256 liquidAssets,
        uint16 threshold,
        uint16 collateralShock,
        uint16 debtGrowth,
        uint16 liquidityHaircut
    ) internal pure returns (AstralPortfolioStress.MarketShock memory) {
        return AstralPortfolioStress.MarketShock({
                asset: asset,
                collateralValue: collateralValue,
                debtValue: debtValue,
                liquidAssets: liquidAssets,
                liquidationThresholdBps: threshold,
                collateralShockBps: collateralShock,
                debtGrowthBps: debtGrowth,
                liquidityHaircutBps: liquidityHaircut
            });
    }
}
