// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPriceFeed } from "../../src/interfaces/IPriceFeed.sol";

contract MockPriceFeed is IPriceFeed {
    uint8 public immutable override decimals;
    string public override description;
    int256 public answer;
    uint80 public roundId;
    uint256 public updatedAt;

    constructor(uint8 decimals_, string memory description_, int256 initialAnswer) {
        decimals = decimals_;
        description = description_;
        answer = initialAnswer;
        roundId = 1;
        updatedAt = block.timestamp;
    }

    function setAnswer(int256 newAnswer) external {
        answer = newAnswer;
        roundId += 1;
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 newUpdatedAt) external {
        updatedAt = newUpdatedAt;
        roundId += 1;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId, answer, updatedAt, updatedAt, roundId);
    }
}
