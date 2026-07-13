// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralRoles } from "../access/AstralRoles.sol";
import { IPriceFeed } from "../interfaces/IPriceFeed.sol";
import { IPriceOracle } from "../interfaces/IPriceOracle.sol";
import { AstralTypes } from "../libraries/AstralTypes.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { PercentageMath } from "../libraries/PercentageMath.sol";
import { PriceMath } from "../libraries/PriceMath.sol";

/// @title AstralOracleRouter
/// @notice Asset oracle registry with stale-price and fallback controls.
contract AstralOracleRouter is AstralRoles, IPriceOracle {
    using FixedPointMath for uint256;
    using PercentageMath for uint256;

    struct SourceConfig {
        address primary;
        address fallbackSource;
        uint40 staleAfter;
        uint16 maxDeviationBps;
        uint8 targetDecimals;
        bool enabled;
    }

    mapping(address asset => SourceConfig source) private _sources;
    address[] private _assets;

    error SourceNotConfigured(address asset);
    error InvalidSource();
    error StalePrice(address asset, uint256 updatedAt, uint256 maxAge);
    error InvalidPrice(address asset, int256 answer);
    error DeviatedPrice(address asset, uint256 primaryPrice, uint256 fallbackPrice);

    event SourceConfigured(
        address indexed asset,
        address indexed primary,
        address indexed fallbackSource,
        uint40 staleAfter,
        uint16 maxDeviationBps,
        uint8 targetDecimals
    );
    event SourceDisabled(address indexed asset);

    constructor(address initialAdmin) AstralRoles(initialAdmin) { }

    function configureSource(
        address asset,
        address primary,
        address fallbackSource,
        uint40 staleAfter,
        uint16 maxDeviationBps,
        uint8 targetDecimals
    ) external onlyRole(ORACLE_ROLE) {
        if (asset == address(0) || primary == address(0) || staleAfter == 0 || targetDecimals == 0)
        {
            revert InvalidSource();
        }
        if (!_sources[asset].enabled) _assets.push(asset);
        _sources[asset] = SourceConfig({
            primary: primary,
            fallbackSource: fallbackSource,
            staleAfter: staleAfter,
            maxDeviationBps: maxDeviationBps,
            targetDecimals: targetDecimals,
            enabled: true
        });
        emit SourceConfigured(
            asset, primary, fallbackSource, staleAfter, maxDeviationBps, targetDecimals
        );
    }

    function disableSource(address asset) external onlyRole(ORACLE_ROLE) {
        if (!_sources[asset].enabled) revert SourceNotConfigured(asset);
        _sources[asset].enabled = false;
        emit SourceDisabled(asset);
    }

    function latestPrice(address asset)
        external
        view
        override
        returns (AstralTypes.PriceData memory data)
    {
        SourceConfig memory source = _sources[asset];
        if (!source.enabled) revert SourceNotConfigured(asset);
        data = _read(asset, source.primary, source.staleAfter, source.targetDecimals);

        if (source.fallbackSource != address(0) && source.maxDeviationBps != 0) {
            AstralTypes.PriceData memory fallbackData =
                _read(asset, source.fallbackSource, source.staleAfter, source.targetDecimals);
            if (!data.price.isWithinBps(fallbackData.price, source.maxDeviationBps)) {
                revert DeviatedPrice(asset, data.price, fallbackData.price);
            }
        }
    }

    function sourceOf(address asset) external view returns (SourceConfig memory) {
        SourceConfig memory source = _sources[asset];
        if (!source.enabled) revert SourceNotConfigured(asset);
        return source;
    }

    function assetCount() external view returns (uint256) {
        return _assets.length;
    }

    function assetAt(uint256 index) external view returns (address) {
        return _assets[index];
    }

    function _read(address asset, address feed, uint256 staleAfter, uint8 targetDecimals)
        internal
        view
        returns (AstralTypes.PriceData memory data)
    {
        (, int256 answer,, uint256 updatedAt,) = IPriceFeed(feed).latestRoundData();
        if (answer <= 0) revert InvalidPrice(asset, answer);
        if (updatedAt == 0 || block.timestamp - updatedAt > staleAfter) {
            revert StalePrice(asset, updatedAt, staleAfter);
        }
        uint8 sourceDecimals = IPriceFeed(feed).decimals();
        data.price = PriceMath.normalizePrice(uint256(answer), sourceDecimals, targetDecimals);
        data.decimals = targetDecimals;
        data.updatedAt = updatedAt;
        data.valid = true;
    }
}
