// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralRoles } from "./access/AstralRoles.sol";
import { ReentrancyGuard } from "./core/ReentrancyGuard.sol";
import { IAstralMarketView } from "./interfaces/IAstralMarketView.sol";
import { IAstralRiskEngine } from "./interfaces/IAstralRiskEngine.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { IRateModel } from "./interfaces/IRateModel.sol";
import { ISupplyTokenHook } from "./interfaces/ISupplyTokenHook.sol";
import { AstralTypes } from "./libraries/AstralTypes.sol";
import { DebtMath } from "./libraries/DebtMath.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { LiquidationLogic } from "./libraries/LiquidationLogic.sol";
import { PercentageMath } from "./libraries/PercentageMath.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { ShareMath } from "./libraries/ShareMath.sol";
import { AstralSupplyToken } from "./tokens/AstralSupplyToken.sol";

/// @title AstralCreditMarket
/// @notice Multi-asset collateral vault and variable-rate credit market.
contract AstralCreditMarket is AstralRoles, ReentrancyGuard, IAstralMarketView, ISupplyTokenHook {
    using FixedPointMath for uint256;
    using PercentageMath for uint256;
    using SafeTransferLib for address;

    uint256 public constant RAY = 1e27;
    uint256 public constant BPS = 10_000;

    mapping(address asset => AstralTypes.MarketConfig config) private _marketConfigs;
    mapping(address asset => AstralTypes.MarketState state) private _marketStates;
    mapping(address asset => mapping(address account => AstralTypes.DebtPosition position)) private
        _debtPositions;
    address[] private _marketList;

    IAstralRiskEngine public riskEngine;
    address public treasury;
    bool public protocolPaused;

    error InvalidAddress();
    error InvalidAmount();
    error InvalidMarketAsset(address asset);
    error MarketAlreadyListed(address asset);
    error MarketNotListed(address asset);
    error MarketNotActive(address asset);
    error MarketFrozen(address asset);
    error BorrowingDisabled(address asset);
    error ProtocolPaused();
    error InvalidMarketConfiguration();
    error SupplyCapExceeded(address asset, uint256 cap, uint256 requestedTotal);
    error BorrowCapExceeded(address asset, uint256 cap, uint256 requestedTotal);
    error InsufficientLiquidity(address asset, uint256 available, uint256 requested);
    error InsufficientShares(address account, uint256 balance, uint256 requested);
    error InsufficientDebt(address asset, address account);
    error InvalidLiquidationPair();
    error AccountNotLiquidatable(address account);
    error LiquidationDoesNotImprove(address account, uint256 beforeHealth, uint256 projectedHealth);
    error UnexpectedTokenBalance(address asset, uint256 expected, uint256 received);
    error ReserveAmountExceeded(uint256 reserves, uint256 requested);
    error RiskEngineNotConfigured();
    error UnauthorizedSupplyToken(address caller, address expected);
    error NumericOverflow(uint256 value);
    error StaleOrInvalidPrice(address asset);

    event MarketListed(
        address indexed asset,
        address indexed supplyToken,
        address indexed priceOracle,
        address rateModel
    );
    event MarketStatusUpdated(address indexed asset, AstralTypes.MarketStatus status);
    event MarketCapsUpdated(address indexed asset, uint256 supplyCap, uint256 borrowCap);
    event MarketRiskUpdated(
        address indexed asset,
        uint256 loanToValueBps,
        uint256 liquidationThresholdBps,
        uint256 liquidationBonusBps,
        uint256 reserveFactorBps,
        uint256 closeFactorBps,
        bool borrowingEnabled,
        bool collateralEnabled
    );
    event MarketSourcesUpdated(
        address indexed asset,
        address indexed priceOracle,
        address indexed rateModel,
        uint256 priceMaxAge
    );
    event RiskEngineUpdated(address indexed previousEngine, address indexed newEngine);
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);
    event ProtocolPauseUpdated(bool paused);
    event InterestAccrued(
        address indexed asset,
        uint256 interestAccrued,
        uint256 reservesAccrued,
        uint256 borrowIndex,
        uint256 supplyIndex
    );
    event Supplied(
        address indexed asset,
        address indexed payer,
        address indexed beneficiary,
        uint256 assets,
        uint256 shares
    );
    event Withdrawn(
        address indexed asset,
        address indexed account,
        address indexed recipient,
        uint256 assets,
        uint256 shares
    );
    event Borrowed(
        address indexed asset,
        address indexed borrower,
        address indexed recipient,
        uint256 amount,
        uint256 accountDebt
    );
    event Repaid(
        address indexed asset,
        address indexed payer,
        address indexed borrower,
        uint256 paid,
        uint256 remainingDebt
    );
    event Liquidated(
        address indexed liquidator,
        address indexed account,
        address indexed debtAsset,
        address collateralAsset,
        uint256 debtRepaid,
        uint256 collateralSeized,
        uint256 sharesSeized
    );
    event ReservesClaimed(address indexed asset, address indexed recipient, uint256 amount);
    event BorrowRoundingSurplus(address indexed asset, uint256 amount);

    constructor(address initialAdmin, address initialTreasury) AstralRoles(initialAdmin) {
        if (initialTreasury == address(0)) revert InvalidAddress();
        treasury = initialTreasury;
        _grantRole(TREASURY_ROLE, initialTreasury);
        emit TreasuryUpdated(address(0), initialTreasury);
    }

    modifier whenOperational() {
        if (protocolPaused) revert ProtocolPaused();
        _;
    }

    modifier onlyListed(address asset) {
        _requireListed(asset);
        _;
    }

    function listMarket(
        address asset,
        string calldata supplyTokenName,
        string calldata supplyTokenSymbol,
        AstralTypes.MarketConfig calldata parameters
    ) external onlyRole(CONFIGURATOR_ROLE) returns (address supplyToken) {
        if (asset == address(0) || asset.code.length == 0) revert InvalidMarketAsset(asset);
        if (_isListed(asset)) revert MarketAlreadyListed(asset);

        uint8 decimals = IERC20(asset).decimals();
        AstralTypes.MarketConfig memory config = parameters;
        config.supplyToken = address(0);
        config.assetDecimals = decimals;
        config.status = AstralTypes.MarketStatus.Active;
        _validateConfiguration(config);

        supplyToken = address(
            new AstralSupplyToken(
                address(this), asset, supplyTokenName, supplyTokenSymbol, decimals
            )
        );
        config.supplyToken = supplyToken;

        _marketConfigs[asset] = config;
        _marketStates[asset] = AstralTypes.MarketState({
            totalSupplyAssets: 0,
            totalBorrowAssets: 0,
            totalReserves: 0,
            borrowIndex: _toUint128(RAY),
            supplyIndex: _toUint128(RAY),
            lastAccrual: _toUint40(block.timestamp)
        });
        _marketList.push(asset);

        emit MarketListed(asset, supplyToken, config.priceOracle, config.rateModel);
    }

    function setRiskEngine(address newRiskEngine) external onlyRole(CONFIGURATOR_ROLE) {
        if (newRiskEngine == address(0) || newRiskEngine.code.length == 0) revert InvalidAddress();
        address previous = address(riskEngine);
        riskEngine = IAstralRiskEngine(newRiskEngine);
        emit RiskEngineUpdated(previous, newRiskEngine);
    }

    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert InvalidAddress();
        address previous = treasury;
        treasury = newTreasury;
        _revokeRole(TREASURY_ROLE, previous);
        _grantRole(TREASURY_ROLE, newTreasury);
        emit TreasuryUpdated(previous, newTreasury);
    }

    function setProtocolPaused(bool paused) external onlyRole(GUARDIAN_ROLE) {
        protocolPaused = paused;
        emit ProtocolPauseUpdated(paused);
    }

    function setMarketStatus(address asset, AstralTypes.MarketStatus status)
        external
        onlyRole(GUARDIAN_ROLE)
        onlyListed(asset)
    {
        if (status == AstralTypes.MarketStatus.Unlisted) {
            revert InvalidMarketConfiguration();
        }
        _marketConfigs[asset].status = status;
        emit MarketStatusUpdated(asset, status);
    }

    function setMarketCaps(address asset, uint128 supplyCap, uint128 borrowCap)
        external
        onlyRole(CONFIGURATOR_ROLE)
        onlyListed(asset)
    {
        if (supplyCap == 0 || borrowCap > supplyCap) revert InvalidMarketConfiguration();
        AstralTypes.MarketState memory state = _previewMarketState(asset);
        if (state.totalSupplyAssets > supplyCap || state.totalBorrowAssets > borrowCap) {
            revert InvalidMarketConfiguration();
        }
        _marketConfigs[asset].supplyCap = supplyCap;
        _marketConfigs[asset].borrowCap = borrowCap;
        emit MarketCapsUpdated(asset, supplyCap, borrowCap);
    }

    function setMarketRiskParameters(
        address asset,
        uint16 loanToValueBps,
        uint16 liquidationThresholdBps,
        uint16 liquidationBonusBps,
        uint16 reserveFactorBps,
        uint16 closeFactorBps,
        bool borrowingEnabled,
        bool collateralEnabled
    ) external onlyRole(CONFIGURATOR_ROLE) onlyListed(asset) {
        _validateRiskParameters(
            loanToValueBps,
            liquidationThresholdBps,
            liquidationBonusBps,
            reserveFactorBps,
            closeFactorBps
        );
        AstralTypes.MarketConfig storage config = _marketConfigs[asset];
        config.loanToValueBps = loanToValueBps;
        config.liquidationThresholdBps = liquidationThresholdBps;
        config.liquidationBonusBps = liquidationBonusBps;
        config.reserveFactorBps = reserveFactorBps;
        config.closeFactorBps = closeFactorBps;
        config.borrowingEnabled = borrowingEnabled;
        config.collateralEnabled = collateralEnabled;
        emit MarketRiskUpdated(
            asset,
            loanToValueBps,
            liquidationThresholdBps,
            liquidationBonusBps,
            reserveFactorBps,
            closeFactorBps,
            borrowingEnabled,
            collateralEnabled
        );
    }

    function setMarketSources(
        address asset,
        address priceOracle,
        address rateModel,
        uint40 priceMaxAge
    ) external onlyRole(CONFIGURATOR_ROLE) onlyListed(asset) {
        if (
            priceOracle == address(0) || priceOracle.code.length == 0 || rateModel == address(0)
                || rateModel.code.length == 0 || priceMaxAge == 0
        ) revert InvalidMarketConfiguration();
        _accrueMarket(asset);
        AstralTypes.MarketConfig storage config = _marketConfigs[asset];
        config.priceOracle = priceOracle;
        config.rateModel = rateModel;
        config.priceMaxAge = priceMaxAge;
        emit MarketSourcesUpdated(asset, priceOracle, rateModel, priceMaxAge);
    }

    function supply(address asset, uint256 assets, address beneficiary)
        external
        nonReentrant
        whenOperational
        onlyListed(asset)
        returns (uint256 shares)
    {
        if (assets == 0 || beneficiary == address(0)) revert InvalidAmount();
        _requireActive(asset);
        _accrueMarket(asset);

        AstralTypes.MarketConfig storage config = _marketConfigs[asset];
        AstralTypes.MarketState storage state = _marketStates[asset];
        uint256 nextTotalAssets = uint256(state.totalSupplyAssets) + assets;
        if (nextTotalAssets > config.supplyCap) {
            revert SupplyCapExceeded(asset, config.supplyCap, nextTotalAssets);
        }

        AstralSupplyToken receipt = AstralSupplyToken(config.supplyToken);
        shares =
            ShareMath.assetsToShares(assets, state.totalSupplyAssets, receipt.totalSupply(), false);
        if (shares == 0) revert InvalidAmount();

        _pullExact(asset, msg.sender, assets);
        state.totalSupplyAssets = _toUint128(nextTotalAssets);
        receipt.mint(beneficiary, shares);
        emit Supplied(asset, msg.sender, beneficiary, assets, shares);
    }

    function withdraw(address asset, uint256 assets, address recipient)
        external
        nonReentrant
        onlyListed(asset)
        returns (uint256 shares)
    {
        if (assets == 0 || recipient == address(0)) revert InvalidAmount();
        _accrueMarket(asset);

        AstralTypes.MarketConfig storage config = _marketConfigs[asset];
        AstralTypes.MarketState storage state = _marketStates[asset];
        AstralSupplyToken receipt = AstralSupplyToken(config.supplyToken);
        shares =
            ShareMath.assetsToShares(assets, state.totalSupplyAssets, receipt.totalSupply(), true);
        _validateShareBalance(receipt, msg.sender, shares);
        _validateLiquidity(asset, assets);
        _riskController().validateCollateralReduction(msg.sender, asset, assets);

        receipt.burn(msg.sender, shares);
        state.totalSupplyAssets = _toUint128(uint256(state.totalSupplyAssets) - assets);
        asset.safeTransfer(recipient, assets);
        emit Withdrawn(asset, msg.sender, recipient, assets, shares);
    }

    function redeem(address asset, uint256 shares, address recipient)
        external
        nonReentrant
        onlyListed(asset)
        returns (uint256 assets)
    {
        if (shares == 0 || recipient == address(0)) revert InvalidAmount();
        _accrueMarket(asset);

        AstralTypes.MarketConfig storage config = _marketConfigs[asset];
        AstralTypes.MarketState storage state = _marketStates[asset];
        AstralSupplyToken receipt = AstralSupplyToken(config.supplyToken);
        _validateShareBalance(receipt, msg.sender, shares);
        assets =
            ShareMath.sharesToAssets(shares, state.totalSupplyAssets, receipt.totalSupply(), false);
        if (assets == 0) revert InvalidAmount();
        _validateLiquidity(asset, assets);
        _riskController().validateCollateralReduction(msg.sender, asset, assets);

        receipt.burn(msg.sender, shares);
        state.totalSupplyAssets = _toUint128(uint256(state.totalSupplyAssets) - assets);
        asset.safeTransfer(recipient, assets);
        emit Withdrawn(asset, msg.sender, recipient, assets, shares);
    }

    function borrow(address asset, uint256 amount, address recipient)
        external
        nonReentrant
        whenOperational
        onlyListed(asset)
        returns (uint256 accountDebt)
    {
        if (amount == 0 || recipient == address(0)) revert InvalidAmount();
        _requireBorrowing(asset);
        _accrueMarket(asset);

        AstralTypes.MarketConfig storage config = _marketConfigs[asset];
        AstralTypes.MarketState storage state = _marketStates[asset];
        uint256 nextTotalBorrow = uint256(state.totalBorrowAssets) + amount;
        if (nextTotalBorrow > config.borrowCap) {
            revert BorrowCapExceeded(asset, config.borrowCap, nextTotalBorrow);
        }
        _validateLiquidity(asset, amount);
        _riskController().validateBorrow(msg.sender, asset, amount);

        AstralTypes.DebtPosition storage position = _debtPositions[asset][msg.sender];
        accountDebt = DebtMath.currentDebt(position, state.borrowIndex) + amount;
        _writeDebtPosition(position, accountDebt, state.borrowIndex);
        state.totalBorrowAssets = _toUint128(nextTotalBorrow);
        asset.safeTransfer(recipient, amount);
        emit Borrowed(asset, msg.sender, recipient, amount, accountDebt);
    }

    function repay(address asset, uint256 requestedAmount, address borrower)
        external
        nonReentrant
        onlyListed(asset)
        returns (uint256 paid, uint256 remainingDebt)
    {
        if (requestedAmount == 0 || borrower == address(0)) revert InvalidAmount();
        AstralTypes.DebtPosition storage position = _debtPositions[asset][borrower];
        if (position.principal == 0) revert InsufficientDebt(asset, borrower);

        _accrueMarket(asset);
        AstralTypes.MarketState storage state = _marketStates[asset];
        uint256 currentDebt = DebtMath.currentDebt(position, state.borrowIndex);
        paid = requestedAmount == type(uint256).max || requestedAmount > currentDebt
            ? currentDebt
            : requestedAmount;
        if (paid == 0) revert InvalidAmount();

        _pullExact(asset, msg.sender, paid);
        remainingDebt = currentDebt - paid;
        _writeDebtPosition(position, remainingDebt, state.borrowIndex);
        _reduceBorrowAssets(asset, state, paid);
        emit Repaid(asset, msg.sender, borrower, paid, remainingDebt);
    }

    function liquidate(
        address collateralAsset,
        address debtAsset,
        address account,
        uint256 requestedRepay
    )
        external
        nonReentrant
        onlyListed(collateralAsset)
        onlyListed(debtAsset)
        returns (uint256 paid, uint256 sharesSeized)
    {
        if (
            account == address(0) || account == msg.sender || collateralAsset == debtAsset
                || requestedRepay == 0
        ) revert InvalidLiquidationPair();

        _accrueMarket(debtAsset);
        _accrueMarket(collateralAsset);

        IAstralRiskEngine controller = _riskController();
        if (!controller.isLiquidatable(account)) revert AccountNotLiquidatable(account);

        AstralTypes.LiquidationQuote memory quote =
            controller.liquidationQuote(account, collateralAsset, debtAsset, requestedRepay);

        paid = _settleLiquidationDebt(debtAsset, account, quote.repayAssets);
        uint256 projectedHealth = controller.healthFactor(account);
        if (!LiquidationLogic.isImprovement(quote.beforeHealthFactor, projectedHealth)) {
            revert LiquidationDoesNotImprove(account, quote.beforeHealthFactor, projectedHealth);
        }

        uint256 collateralSeized;
        (sharesSeized, collateralSeized) = _seizeLiquidationCollateral(
            collateralAsset, account, quote.collateralAssets, msg.sender
        );
        emit Liquidated(
            msg.sender, account, debtAsset, collateralAsset, paid, collateralSeized, sharesSeized
        );
    }

    function claimReserves(address asset, uint256 amount, address recipient)
        external
        nonReentrant
        onlyRole(TREASURY_ROLE)
        onlyListed(asset)
    {
        if (amount == 0 || recipient == address(0)) revert InvalidAmount();
        _accrueMarket(asset);
        AstralTypes.MarketState storage state = _marketStates[asset];
        if (amount > state.totalReserves) {
            revert ReserveAmountExceeded(state.totalReserves, amount);
        }
        _validateLiquidity(asset, amount);
        state.totalReserves = _toUint128(uint256(state.totalReserves) - amount);
        asset.safeTransfer(recipient, amount);
        emit ReservesClaimed(asset, recipient, amount);
    }

    function accrueInterest(address asset)
        external
        onlyListed(asset)
        returns (uint256 borrowIndex)
    {
        _accrueMarket(asset);
        return _marketStates[asset].borrowIndex;
    }

    function validateSupplyTokenTransfer(
        address asset,
        address from,
        address,
        uint256 shares,
        uint256 fromBalanceBefore,
        uint256 totalSupplyBefore
    ) external view override onlyListed(asset) {
        address expectedToken = _marketConfigs[asset].supplyToken;
        if (msg.sender != expectedToken) revert UnauthorizedSupplyToken(msg.sender, expectedToken);
        if (from == address(0) || shares == 0) return;
        if (shares > fromBalanceBefore) revert InsufficientShares(from, fromBalanceBefore, shares);

        AstralTypes.MarketState memory state = _previewMarketState(asset);
        uint256 assets = shares == fromBalanceBefore
            ? supplyBalance(asset, from)
            : ShareMath.sharesToAssets(shares, state.totalSupplyAssets, totalSupplyBefore, true);
        _riskController().validateCollateralReduction(from, asset, assets);
    }

    function marketCount() external view override returns (uint256) {
        return _marketList.length;
    }

    function marketAt(uint256 index) external view override returns (address) {
        return _marketList[index];
    }

    function getMarketConfig(address asset)
        external
        view
        override
        returns (AstralTypes.MarketConfig memory)
    {
        _requireListed(asset);
        return _marketConfigs[asset];
    }

    function getMarketState(address asset)
        external
        view
        override
        returns (AstralTypes.MarketState memory)
    {
        _requireListed(asset);
        return _previewMarketState(asset);
    }

    function getDebtPosition(address asset, address account)
        external
        view
        override
        returns (AstralTypes.DebtPosition memory)
    {
        _requireListed(asset);
        return _debtPositions[asset][account];
    }

    function getAccountLiquidity(address account)
        external
        view
        override
        returns (AstralTypes.AccountLiquidity memory)
    {
        return _riskController().getAccountLiquidity(account);
    }

    function borrowBalance(address asset, address account) public view override returns (uint256) {
        _requireListed(asset);
        AstralTypes.MarketState memory state = _previewMarketState(asset);
        return DebtMath.currentDebt(_debtPositions[asset][account], state.borrowIndex);
    }

    function supplyBalance(address asset, address account) public view override returns (uint256) {
        _requireListed(asset);
        AstralTypes.MarketConfig storage config = _marketConfigs[asset];
        AstralTypes.MarketState memory state = _previewMarketState(asset);
        uint256 shares = IERC20(config.supplyToken).balanceOf(account);
        uint256 totalShares = IERC20(config.supplyToken).totalSupply();
        return ShareMath.sharesToAssets(shares, state.totalSupplyAssets, totalShares, false);
    }

    function priceOf(address asset)
        public
        view
        override
        returns (AstralTypes.PriceData memory price)
    {
        _requireListed(asset);
        AstralTypes.MarketConfig storage config = _marketConfigs[asset];
        price = IPriceOracle(config.priceOracle).latestPrice(asset);
        if (
            !price.valid || price.price == 0
                || block.timestamp - price.updatedAt > config.priceMaxAge
        ) {
            revert StaleOrInvalidPrice(asset);
        }
    }

    function availableLiquidity(address asset) public view override returns (uint256) {
        _requireListed(asset);
        uint256 cash = IERC20(asset).balanceOf(address(this));
        uint256 reserves = _previewMarketState(asset).totalReserves;
        return cash > reserves ? cash - reserves : 0;
    }

    function previewBorrowIndex(address asset) external view override returns (uint256) {
        _requireListed(asset);
        return _previewMarketState(asset).borrowIndex;
    }

    function exchangeRate(address asset) external view override returns (uint256) {
        _requireListed(asset);
        AstralTypes.MarketConfig storage config = _marketConfigs[asset];
        AstralTypes.MarketState memory state = _previewMarketState(asset);
        return
            ShareMath.exchangeRate(
                state.totalSupplyAssets, IERC20(config.supplyToken).totalSupply()
            );
    }

    function isMarketListed(address asset) external view override returns (bool) {
        return _isListed(asset);
    }

    function isMarketActive(address asset) external view override returns (bool) {
        return _marketConfigs[asset].status == AstralTypes.MarketStatus.Active;
    }

    function previewRates(address asset)
        external
        view
        returns (uint256 borrowRate, uint256 supplyRate)
    {
        _requireListed(asset);
        AstralTypes.MarketConfig storage config = _marketConfigs[asset];
        AstralTypes.MarketState memory state = _previewMarketState(asset);
        uint256 cash = IERC20(asset).balanceOf(address(this));
        borrowRate = IRateModel(config.rateModel)
            .getBorrowRate(cash, state.totalBorrowAssets, state.totalReserves);
        supplyRate = IRateModel(config.rateModel)
            .getSupplyRate(
                cash, state.totalBorrowAssets, state.totalReserves, config.reserveFactorBps
            );
    }

    function _accrueMarket(address asset) internal {
        AstralTypes.MarketState memory current = _marketStates[asset];
        AstralTypes.MarketState memory updated = _previewMarketState(asset);
        if (updated.lastAccrual == current.lastAccrual) return;

        uint256 interestAccrued =
            uint256(updated.totalBorrowAssets) - uint256(current.totalBorrowAssets);
        uint256 reservesAccrued = uint256(updated.totalReserves) - uint256(current.totalReserves);
        _marketStates[asset] = updated;
        emit InterestAccrued(
            asset, interestAccrued, reservesAccrued, updated.borrowIndex, updated.supplyIndex
        );
    }

    function _previewMarketState(address asset)
        internal
        view
        returns (AstralTypes.MarketState memory updated)
    {
        updated = _marketStates[asset];
        uint256 elapsed = block.timestamp - updated.lastAccrual;
        if (elapsed == 0) return updated;
        updated.lastAccrual = _toUint40(block.timestamp);
        if (updated.totalBorrowAssets == 0) return updated;

        AstralTypes.MarketConfig storage config = _marketConfigs[asset];
        uint256 cash = IERC20(asset).balanceOf(address(this));
        uint256 borrowRate = IRateModel(config.rateModel)
            .getBorrowRate(cash, updated.totalBorrowAssets, updated.totalReserves);
        uint256 supplyRate = IRateModel(config.rateModel)
            .getSupplyRate(
                cash, updated.totalBorrowAssets, updated.totalReserves, config.reserveFactorBps
            );

        uint256 growthFactor = DebtMath.linearInterestFactor(borrowRate, elapsed);
        uint256 nextBorrowAssets = uint256(updated.totalBorrowAssets).rayMulDown(growthFactor);
        uint256 interestAccrued = nextBorrowAssets - updated.totalBorrowAssets;
        uint256 reservesAccrued = interestAccrued.percentMulDown(config.reserveFactorBps);

        updated.totalBorrowAssets = _toUint128(nextBorrowAssets);
        updated.totalSupplyAssets =
            _toUint128(uint256(updated.totalSupplyAssets) + interestAccrued - reservesAccrued);
        updated.totalReserves = _toUint128(uint256(updated.totalReserves) + reservesAccrued);
        updated.borrowIndex =
            _toUint128(DebtMath.nextIndex(updated.borrowIndex, borrowRate, elapsed));
        updated.supplyIndex =
            _toUint128(DebtMath.nextIndex(updated.supplyIndex, supplyRate, elapsed));
    }

    function _settleLiquidationDebt(address debtAsset, address account, uint256 quotedRepay)
        internal
        returns (uint256 repayAssets)
    {
        AstralTypes.MarketState storage state = _marketStates[debtAsset];
        AstralTypes.DebtPosition storage position = _debtPositions[debtAsset][account];
        uint256 currentDebt = DebtMath.currentDebt(position, state.borrowIndex);
        repayAssets = quotedRepay > currentDebt ? currentDebt : quotedRepay;
        if (repayAssets == 0) revert InvalidAmount();

        _pullExact(debtAsset, msg.sender, repayAssets);
        _writeDebtPosition(position, currentDebt - repayAssets, state.borrowIndex);
        _reduceBorrowAssets(debtAsset, state, repayAssets);
    }

    function _seizeLiquidationCollateral(
        address collateralAsset,
        address account,
        uint256 collateralAssets,
        address recipient
    ) internal returns (uint256 seizeShares, uint256 assetsSeized) {
        AstralTypes.MarketConfig storage config = _marketConfigs[collateralAsset];
        AstralTypes.MarketState storage state = _marketStates[collateralAsset];
        AstralSupplyToken token = AstralSupplyToken(config.supplyToken);
        seizeShares = ShareMath.assetsToShares(
            collateralAssets, state.totalSupplyAssets, token.totalSupply(), true
        );
        uint256 accountShares = token.balanceOf(account);
        if (seizeShares > accountShares) seizeShares = accountShares;
        if (seizeShares == 0) revert InvalidAmount();
        assetsSeized = ShareMath.sharesToAssets(
            seizeShares, state.totalSupplyAssets, token.totalSupply(), false
        );
        token.transferOnLiquidation(account, recipient, seizeShares);
    }

    function _writeDebtPosition(
        AstralTypes.DebtPosition storage position,
        uint256 principal,
        uint256 interestIndex
    ) internal {
        position.principal = _toUint128(principal);
        position.interestIndex = _toUint128(interestIndex);
        position.lastUpdate = _toUint40(block.timestamp);
    }

    function _reduceBorrowAssets(
        address asset,
        AstralTypes.MarketState storage state,
        uint256 reduction
    ) internal {
        uint256 aggregate = state.totalBorrowAssets;
        if (reduction <= aggregate) {
            state.totalBorrowAssets = _toUint128(aggregate - reduction);
            return;
        }
        uint256 surplus = reduction - aggregate;
        state.totalBorrowAssets = 0;
        state.totalReserves = _toUint128(uint256(state.totalReserves) + surplus);
        emit BorrowRoundingSurplus(asset, surplus);
    }

    function _pullExact(address asset, address payer, uint256 amount) internal {
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        asset.safeTransferFrom(payer, address(this), amount);
        uint256 received = IERC20(asset).balanceOf(address(this)) - balanceBefore;
        if (received != amount) revert UnexpectedTokenBalance(asset, amount, received);
    }

    function _validateLiquidity(address asset, uint256 amount) internal view {
        uint256 available = availableLiquidity(asset);
        if (amount > available) revert InsufficientLiquidity(asset, available, amount);
    }

    function _validateShareBalance(AstralSupplyToken token, address account, uint256 shares)
        internal
        view
    {
        uint256 balance = token.balanceOf(account);
        if (shares > balance) revert InsufficientShares(account, balance, shares);
    }

    function _riskController() internal view returns (IAstralRiskEngine controller) {
        controller = riskEngine;
        if (address(controller) == address(0)) revert RiskEngineNotConfigured();
    }

    function _requireListed(address asset) internal view {
        if (!_isListed(asset)) revert MarketNotListed(asset);
    }

    function _requireActive(address asset) internal view {
        AstralTypes.MarketStatus status = _marketConfigs[asset].status;
        if (status != AstralTypes.MarketStatus.Active) revert MarketNotActive(asset);
    }

    function _requireBorrowing(address asset) internal view {
        _requireActive(asset);
        if (!_marketConfigs[asset].borrowingEnabled) revert BorrowingDisabled(asset);
    }

    function _isListed(address asset) internal view returns (bool) {
        return _marketConfigs[asset].status != AstralTypes.MarketStatus.Unlisted;
    }

    function _validateConfiguration(AstralTypes.MarketConfig memory config) internal view {
        if (
            config.priceOracle == address(0) || config.priceOracle.code.length == 0
                || config.rateModel == address(0) || config.rateModel.code.length == 0
                || config.supplyCap == 0 || config.borrowCap > config.supplyCap
                || config.priceMaxAge == 0 || config.assetDecimals > 36
        ) revert InvalidMarketConfiguration();
        _validateRiskParameters(
            config.loanToValueBps,
            config.liquidationThresholdBps,
            config.liquidationBonusBps,
            config.reserveFactorBps,
            config.closeFactorBps
        );
    }

    function _validateRiskParameters(
        uint256 loanToValueBps,
        uint256 liquidationThresholdBps,
        uint256 liquidationBonusBps,
        uint256 reserveFactorBps,
        uint256 closeFactorBps
    ) internal pure {
        if (
            loanToValueBps > liquidationThresholdBps || liquidationThresholdBps > BPS
                || liquidationBonusBps > 5000 || reserveFactorBps > BPS || closeFactorBps == 0
                || closeFactorBps > BPS
        ) revert InvalidMarketConfiguration();
    }

    function _toUint128(uint256 value) internal pure returns (uint128) {
        if (value > type(uint128).max) revert NumericOverflow(value);
        return uint128(value);
    }

    function _toUint40(uint256 value) internal pure returns (uint40) {
        if (value > type(uint40).max) revert NumericOverflow(value);
        return uint40(value);
    }
}
