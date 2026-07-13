// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "../interfaces/IERC20.sol";

/// @title SafeTransferLib
/// @notice Minimal ERC-20 transfer wrappers supporting tokens with or without boolean returns.
library SafeTransferLib {
    error TransferFailed(address token, address to, uint256 amount);
    error TransferFromFailed(address token, address from, address to, uint256 amount);
    error ApproveFailed(address token, address spender, uint256 amount);

    function safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeCall(IERC20.transfer, (to, amount)));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TransferFailed(token, to, amount);
        }
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeCall(IERC20.transferFrom, (from, to, amount)));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TransferFromFailed(token, from, to, amount);
        }
    }

    function safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeCall(IERC20.approve, (spender, amount)));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ApproveFailed(token, spender, amount);
        }
    }

    function balanceOf(address token, address account) internal view returns (uint256 balance) {
        balance = IERC20(token).balanceOf(account);
    }
}
