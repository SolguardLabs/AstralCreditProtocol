// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";

import { AstralCreditMarket } from "../../src/AstralCreditMarket.sol";
import { AstralRateModel } from "../../src/interest/AstralRateModel.sol";
import { IERC20 } from "../../src/interfaces/IERC20.sol";
import { AstralTypes } from "../../src/libraries/AstralTypes.sol";
import { AstralOracleRouter } from "../../src/oracle/AstralOracleRouter.sol";
import { AstralRiskEngine } from "../../src/risk/AstralRiskEngine.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockPriceFeed } from "../mocks/MockPriceFeed.sol";

abstract contract AstralTestBase is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant PRICE_UNIT = 1e8;
    uint256 internal constant USDC_UNIT = 1e6;

    uint256 internal constant OPTIMAL_UTILIZATION = 8e26;
    uint256 internal constant BASE_RATE = 2e25;
    uint256 internal constant SLOPE_ONE = 5e25;
    uint256 internal constant SLOPE_TWO = 8e26;

    address internal admin;
    address internal treasury;
    address internal supplier;
    address internal borrower;
    address internal liquidator;
    address internal recipient;

    MockERC20 internal weth;
    MockERC20 internal usdc;
    MockPriceFeed internal wethFeed;
    MockPriceFeed internal usdcFeed;

    AstralOracleRouter internal oracle;
    AstralRateModel internal rateModel;
    AstralCreditMarket internal market;
    AstralRiskEngine internal riskEngine;

    IERC20 internal aWeth;
    IERC20 internal aUsdc;

    function setUp() public virtual {
        vm.warp(1_900_000_000);

        admin = address(this);
        treasury = makeAddr("treasury");
        supplier = makeAddr("supplier");
        borrower = makeAddr("borrower");
        liquidator = makeAddr("liquidator");
        recipient = makeAddr("recipient");

        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        wethFeed = new MockPriceFeed(8, "WETH / USD", int256(2000 * PRICE_UNIT));
        usdcFeed = new MockPriceFeed(8, "USDC / USD", int256(PRICE_UNIT));

        oracle = new AstralOracleRouter(admin);
        oracle.grantRole(oracle.ORACLE_ROLE(), admin);
        oracle.configureSource(address(weth), address(wethFeed), address(0), 365 days, 0, 8);
        oracle.configureSource(address(usdc), address(usdcFeed), address(0), 365 days, 0, 8);

        rateModel = new AstralRateModel(OPTIMAL_UTILIZATION, BASE_RATE, SLOPE_ONE, SLOPE_TWO);
        market = new AstralCreditMarket(admin, treasury);
        riskEngine = new AstralRiskEngine(market);
        market.setRiskEngine(address(riskEngine));

        market.listMarket(
            address(weth),
            "Astral WETH Vault",
            "aWETH",
            _marketConfig(1_000_000 ether, 500_000 ether, 7000, 8000, 800, 5000, true, true)
        );
        market.listMarket(
            address(usdc),
            "Astral USDC Vault",
            "aUSDC",
            _marketConfig(
                50_000_000 * uint128(USDC_UNIT),
                30_000_000 * uint128(USDC_UNIT),
                8500,
                9000,
                400,
                5000,
                true,
                true
            )
        );

        aWeth = IERC20(market.getMarketConfig(address(weth)).supplyToken);
        aUsdc = IERC20(market.getMarketConfig(address(usdc)).supplyToken);

        _supply(supplier, usdc, 2_000_000 * USDC_UNIT, supplier);
    }

    function _marketConfig(
        uint128 supplyCap,
        uint128 borrowCap,
        uint16 loanToValueBps,
        uint16 liquidationThresholdBps,
        uint16 liquidationBonusBps,
        uint16 closeFactorBps,
        bool borrowingEnabled,
        bool collateralEnabled
    ) internal view returns (AstralTypes.MarketConfig memory config) {
        config = AstralTypes.MarketConfig({
            supplyToken: address(0),
            priceOracle: address(oracle),
            rateModel: address(rateModel),
            supplyCap: supplyCap,
            borrowCap: borrowCap,
            priceMaxAge: 365 days,
            loanToValueBps: loanToValueBps,
            liquidationThresholdBps: liquidationThresholdBps,
            liquidationBonusBps: liquidationBonusBps,
            reserveFactorBps: 1000,
            closeFactorBps: closeFactorBps,
            assetDecimals: 0,
            status: AstralTypes.MarketStatus.Unlisted,
            borrowingEnabled: borrowingEnabled,
            collateralEnabled: collateralEnabled
        });
    }

    function _supply(address payer, MockERC20 asset, uint256 amount, address beneficiary)
        internal
        returns (uint256 shares)
    {
        asset.mint(payer, amount);
        vm.startPrank(payer);
        asset.approve(address(market), amount);
        shares = market.supply(address(asset), amount, beneficiary);
        vm.stopPrank();
    }

    function _supplyCollateral(address account, uint256 amount) internal returns (uint256) {
        return _supply(account, weth, amount, account);
    }

    function _borrow(address account, uint256 amount) internal returns (uint256 accountDebt) {
        vm.prank(account);
        accountDebt = market.borrow(address(usdc), amount, account);
    }

    function _repay(address payer, uint256 amount, address account)
        internal
        returns (uint256 paid, uint256 remaining)
    {
        usdc.mint(payer, amount);
        vm.startPrank(payer);
        usdc.approve(address(market), amount);
        (paid, remaining) = market.repay(address(usdc), amount, account);
        vm.stopPrank();
    }

    function _openPosition(uint256 collateralAmount, uint256 borrowAmount) internal {
        _supplyCollateral(borrower, collateralAmount);
        _borrow(borrower, borrowAmount);
    }

    function _fundLiquidator(uint256 amount) internal {
        usdc.mint(liquidator, amount);
        vm.prank(liquidator);
        usdc.approve(address(market), amount);
    }

    function _setWethPrice(uint256 price) internal {
        wethFeed.setAnswer(int256(price));
    }
}
