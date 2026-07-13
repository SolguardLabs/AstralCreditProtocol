// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralRoles } from "../access/AstralRoles.sol";

/// @title AstralTimelockQueue
/// @notice Simple governance queue for configuration payloads executed by an admin account.
contract AstralTimelockQueue is AstralRoles {
    struct Operation {
        address target;
        uint256 value;
        bytes32 dataHash;
        uint40 readyAt;
        uint40 expiresAt;
        bool executed;
        bool cancelled;
    }

    uint40 public immutable minDelay;
    uint40 public immutable gracePeriod;

    mapping(bytes32 id => Operation operation) public operations;

    error InvalidDelay();
    error InvalidOperation();
    error OperationAlreadyQueued(bytes32 id);
    error OperationNotReady(bytes32 id, uint256 readyAt);
    error OperationExpired(bytes32 id, uint256 expiresAt);
    error OperationUnavailable(bytes32 id);
    error ExecutionFailed(bytes32 id);

    event OperationQueued(
        bytes32 indexed id,
        address indexed target,
        uint256 value,
        bytes32 dataHash,
        uint40 readyAt,
        uint40 expiresAt
    );
    event OperationCancelled(bytes32 indexed id);
    event OperationExecuted(bytes32 indexed id, address indexed target, uint256 value);

    constructor(address initialAdmin, uint40 minDelay_, uint40 gracePeriod_)
        AstralRoles(initialAdmin)
    {
        if (minDelay_ == 0 || gracePeriod_ == 0) revert InvalidDelay();
        minDelay = minDelay_;
        gracePeriod = gracePeriod_;
    }

    receive() external payable { }

    function queue(address target, uint256 value, bytes calldata data, bytes32 salt)
        external
        onlyRole(CONFIGURATOR_ROLE)
        returns (bytes32 id)
    {
        if (target == address(0) || data.length == 0) revert InvalidOperation();
        id = hashOperation(target, value, data, salt);
        if (operations[id].readyAt != 0) revert OperationAlreadyQueued(id);
        uint40 readyAt = uint40(block.timestamp + minDelay);
        uint40 expiresAt = readyAt + gracePeriod;
        operations[id] = Operation({
            target: target,
            value: value,
            dataHash: keccak256(data),
            readyAt: readyAt,
            expiresAt: expiresAt,
            executed: false,
            cancelled: false
        });
        emit OperationQueued(id, target, value, keccak256(data), readyAt, expiresAt);
    }

    function cancel(bytes32 id) external onlyRole(GUARDIAN_ROLE) {
        Operation storage operation = operations[id];
        if (operation.readyAt == 0 || operation.executed || operation.cancelled) {
            revert OperationUnavailable(id);
        }
        operation.cancelled = true;
        emit OperationCancelled(id);
    }

    function execute(address target, uint256 value, bytes calldata data, bytes32 salt)
        external
        payable
        onlyRole(CONFIGURATOR_ROLE)
        returns (bytes memory result)
    {
        bytes32 id = hashOperation(target, value, data, salt);
        Operation storage operation = operations[id];
        if (operation.readyAt == 0 || operation.executed || operation.cancelled) {
            revert OperationUnavailable(id);
        }
        if (block.timestamp < operation.readyAt) revert OperationNotReady(id, operation.readyAt);
        if (block.timestamp > operation.expiresAt) {
            revert OperationExpired(id, operation.expiresAt);
        }
        if (operation.dataHash != keccak256(data)) revert InvalidOperation();

        operation.executed = true;
        (bool success, bytes memory output) = target.call{ value: value }(data);
        if (!success) revert ExecutionFailed(id);
        emit OperationExecuted(id, target, value);
        return output;
    }

    function hashOperation(address target, uint256 value, bytes calldata data, bytes32 salt)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(target, value, keccak256(data), salt));
    }

    function isReady(bytes32 id) external view returns (bool) {
        Operation memory operation = operations[id];
        return operation.readyAt != 0 && !operation.cancelled && !operation.executed
            && block.timestamp >= operation.readyAt && block.timestamp <= operation.expiresAt;
    }
}
