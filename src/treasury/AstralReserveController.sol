// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralRoles } from "../access/AstralRoles.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";

/// @title AstralReserveController
/// @notice Optional treasury receiver for reserve distributions.
contract AstralReserveController is AstralRoles {
    using SafeTransferLib for address;

    address public payoutAccount;

    error InvalidPayoutAccount();

    event PayoutAccountUpdated(address indexed previousAccount, address indexed newAccount);
    event ReserveForwarded(
        address indexed asset, address indexed caller, address indexed payoutAccount, uint256 amount
    );

    constructor(address initialAdmin, address initialPayout) AstralRoles(initialAdmin) {
        if (initialPayout == address(0)) revert InvalidPayoutAccount();
        payoutAccount = initialPayout;
        emit PayoutAccountUpdated(address(0), initialPayout);
    }

    function setPayoutAccount(address newPayout) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newPayout == address(0)) revert InvalidPayoutAccount();
        address previous = payoutAccount;
        payoutAccount = newPayout;
        emit PayoutAccountUpdated(previous, newPayout);
    }

    function forward(address asset) external returns (uint256 amount) {
        amount = IERC20(asset).balanceOf(address(this));
        if (amount != 0) {
            asset.safeTransfer(payoutAccount, amount);
            emit ReserveForwarded(asset, msg.sender, payoutAccount, amount);
        }
    }
}
