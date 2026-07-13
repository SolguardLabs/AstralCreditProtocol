// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPriceOracle } from "../interfaces/IPriceOracle.sol";
import { AstralTypes } from "../libraries/AstralTypes.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { PercentageMath } from "../libraries/PercentageMath.sol";

/// @title AstralOracleSentinel
/// @notice Read-only helper that classifies oracle observations for monitoring jobs.
contract AstralOracleSentinel {
    using FixedPointMath for uint256;
    using PercentageMath for uint256;

    enum ObservationStatus {
        Unknown,
        Healthy,
        Stale,
        Deviated,
        Invalid
    }

    struct Observation {
        address asset;
        uint256 primaryPrice;
        uint256 referencePrice;
        uint8 decimals;
        uint256 updatedAt;
        uint256 age;
        uint256 deviationBps;
        ObservationStatus status;
    }

    IPriceOracle public immutable primaryOracle;
    IPriceOracle public immutable referenceOracle;

    constructor(IPriceOracle primaryOracle_, IPriceOracle referenceOracle_) {
        primaryOracle = primaryOracle_;
        referenceOracle = referenceOracle_;
    }

    function observe(address asset, uint256 maxAge, uint256 maxDeviationBps)
        external
        view
        returns (Observation memory observation)
    {
        AstralTypes.PriceData memory primary = primaryOracle.latestPrice(asset);
        AstralTypes.PriceData memory referenceData = referenceOracle.latestPrice(asset);
        observation.asset = asset;
        observation.primaryPrice = primary.price;
        observation.referencePrice = referenceData.price;
        observation.decimals = primary.decimals;
        observation.updatedAt = primary.updatedAt;
        observation.age =
            block.timestamp > primary.updatedAt ? block.timestamp - primary.updatedAt : 0;
        observation.deviationBps = _deviationBps(primary.price, referenceData.price);
        observation.status =
            _status(primary, referenceData, observation.age, maxAge, maxDeviationBps);
    }

    function observeBatch(address[] calldata assets, uint256 maxAge, uint256 maxDeviationBps)
        external
        view
        returns (Observation[] memory observations)
    {
        observations = new Observation[](assets.length);
        for (uint256 i = 0; i < assets.length; ++i) {
            AstralTypes.PriceData memory primary = primaryOracle.latestPrice(assets[i]);
            AstralTypes.PriceData memory referenceData = referenceOracle.latestPrice(assets[i]);
            uint256 age =
                block.timestamp > primary.updatedAt ? block.timestamp - primary.updatedAt : 0;
            observations[i] = Observation({
                asset: assets[i],
                primaryPrice: primary.price,
                referencePrice: referenceData.price,
                decimals: primary.decimals,
                updatedAt: primary.updatedAt,
                age: age,
                deviationBps: _deviationBps(primary.price, referenceData.price),
                status: _status(primary, referenceData, age, maxAge, maxDeviationBps)
            });
        }
    }

    function _status(
        AstralTypes.PriceData memory primary,
        AstralTypes.PriceData memory referenceData,
        uint256 age,
        uint256 maxAge,
        uint256 maxDeviationBps
    ) internal pure returns (ObservationStatus) {
        if (
            !primary.valid || primary.price == 0 || !referenceData.valid || referenceData.price == 0
        ) {
            return ObservationStatus.Invalid;
        }
        if (age > maxAge) return ObservationStatus.Stale;
        if (_deviationBps(primary.price, referenceData.price) > maxDeviationBps) {
            return ObservationStatus.Deviated;
        }
        return ObservationStatus.Healthy;
    }

    function _deviationBps(uint256 price, uint256 referencePrice) internal pure returns (uint256) {
        if (price == 0 && referencePrice == 0) return 0;
        if (price == 0 || referencePrice == 0) return type(uint256).max;
        uint256 diff = price.absDiff(referencePrice);
        return diff.mulDivDown(10_000, referencePrice);
    }
}
