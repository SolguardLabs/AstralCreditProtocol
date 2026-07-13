// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralRoles } from "../access/AstralRoles.sol";
import { AstralTypes } from "../libraries/AstralTypes.sol";

interface IAstralConfigurableMarket {
    function setMarketCaps(address asset, uint128 supplyCap, uint128 borrowCap) external;
    function setMarketRiskParameters(
        address asset,
        uint16 loanToValueBps,
        uint16 liquidationThresholdBps,
        uint16 liquidationBonusBps,
        uint16 reserveFactorBps,
        uint16 closeFactorBps,
        bool borrowingEnabled,
        bool collateralEnabled
    ) external;
    function setMarketStatus(address asset, AstralTypes.MarketStatus status) external;
    function setMarketSources(
        address asset,
        address priceOracle,
        address rateModel,
        uint40 priceMaxAge
    ) external;
}

/// @title AstralConfigurator
/// @notice Batch configuration helper for markets managed by a governance account.
contract AstralConfigurator is AstralRoles {
    IAstralConfigurableMarket public immutable market;

    event RiskProfileApplied(address indexed asset, AstralTypes.RiskParameters parameters);
    event CapsApplied(address indexed asset, AstralTypes.MarketCaps caps);
    event SourcesApplied(
        address indexed asset, AstralTypes.OracleParameters oracle, address rateModel
    );
    event StatusApplied(address indexed asset, AstralTypes.MarketStatus status);

    constructor(address initialAdmin, IAstralConfigurableMarket market_) AstralRoles(initialAdmin) {
        market = market_;
    }

    function applyRiskProfile(address asset, AstralTypes.RiskParameters calldata parameters)
        external
        onlyRole(CONFIGURATOR_ROLE)
    {
        market.setMarketRiskParameters(
            asset,
            parameters.loanToValueBps,
            parameters.liquidationThresholdBps,
            parameters.liquidationBonusBps,
            parameters.reserveFactorBps,
            parameters.closeFactorBps,
            parameters.borrowingEnabled,
            parameters.collateralEnabled
        );
        emit RiskProfileApplied(asset, parameters);
    }

    function applyCaps(address asset, AstralTypes.MarketCaps calldata caps)
        external
        onlyRole(CONFIGURATOR_ROLE)
    {
        market.setMarketCaps(asset, caps.supplyCap, caps.borrowCap);
        emit CapsApplied(asset, caps);
    }

    function applySources(
        address asset,
        AstralTypes.OracleParameters calldata oracle,
        address rateModel
    ) external onlyRole(CONFIGURATOR_ROLE) {
        market.setMarketSources(asset, oracle.priceOracle, rateModel, oracle.priceMaxAge);
        emit SourcesApplied(asset, oracle, rateModel);
    }

    function applyStatus(address asset, AstralTypes.MarketStatus status)
        external
        onlyRole(GUARDIAN_ROLE)
    {
        market.setMarketStatus(asset, status);
        emit StatusApplied(asset, status);
    }
}
