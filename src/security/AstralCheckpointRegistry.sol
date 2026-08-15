// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AstralRoles } from "../access/AstralRoles.sol";

/// @title AstralCheckpointRegistry
/// @notice Quorum-approved, hash-linked accounting checkpoints for market operators.
contract AstralCheckpointRegistry is AstralRoles {
    bytes32 public constant REPORTER_ROLE = keccak256("ASTRAL_REPORTER_ROLE");
    uint256 public constant MAX_REPORTERS = 16;

    struct Checkpoint {
        uint64 epoch;
        uint40 proposedAt;
        uint40 finalizedAt;
        uint16 approvals;
        uint256 totalSupplyAssets;
        uint256 totalBorrowAssets;
        uint256 totalReserves;
        bytes32 marketRoot;
        bytes32 accountRoot;
        bytes32 previousHash;
        bytes32 checkpointHash;
        bool finalized;
    }

    uint16 public quorum;
    uint16 public reporterCount;
    uint64 public latestProposedEpoch;
    uint64 public latestFinalizedEpoch;
    bytes32 public latestFinalizedHash;

    mapping(uint64 epoch => Checkpoint checkpoint) public checkpoints;
    mapping(uint64 epoch => mapping(address reporter => bool approved)) public approvals;

    error InvalidQuorum(uint256 quorum, uint256 reporters);
    error ReporterLimit();
    error CheckpointPending(uint64 epoch);
    error InvalidEpoch(uint64 epoch);
    error InvalidRoot();
    error InvalidAccounting();
    error AlreadyApproved(uint64 epoch, address reporter);
    error CheckpointUnavailable(uint64 epoch);
    error StaleParent(bytes32 supplied, bytes32 expected);

    event ReporterUpdated(address indexed reporter, bool enabled, uint256 reporterCount);
    event QuorumUpdated(uint256 previousQuorum, uint256 newQuorum);
    event CheckpointProposed(
        uint64 indexed epoch,
        bytes32 indexed checkpointHash,
        bytes32 indexed previousHash,
        address reporter
    );
    event CheckpointApproved(uint64 indexed epoch, address indexed reporter, uint256 approvals);
    event CheckpointFinalized(
        uint64 indexed epoch, bytes32 indexed checkpointHash, uint256 approvals
    );

    constructor(address initialAdmin, uint16 initialQuorum) AstralRoles(initialAdmin) {
        if (initialQuorum == 0 || initialQuorum > MAX_REPORTERS) {
            revert InvalidQuorum(initialQuorum, 0);
        }
        quorum = initialQuorum;
        _setRoleAdmin(REPORTER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    function setReporter(address reporter, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bool current = hasRole(REPORTER_ROLE, reporter);
        if (current == enabled) return;
        if (enabled) {
            if (reporterCount == MAX_REPORTERS) revert ReporterLimit();
            _grantRole(REPORTER_ROLE, reporter);
            reporterCount += 1;
        } else {
            reporterCount -= 1;
            if (quorum > reporterCount) revert InvalidQuorum(quorum, reporterCount);
            _revokeRole(REPORTER_ROLE, reporter);
        }
        emit ReporterUpdated(reporter, enabled, reporterCount);
    }

    function setQuorum(uint16 newQuorum) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newQuorum == 0 || newQuorum > reporterCount) {
            revert InvalidQuorum(newQuorum, reporterCount);
        }
        uint256 previous = quorum;
        quorum = newQuorum;
        emit QuorumUpdated(previous, newQuorum);
    }

    function propose(
        uint64 epoch,
        uint256 totalSupplyAssets,
        uint256 totalBorrowAssets,
        uint256 totalReserves,
        bytes32 marketRoot,
        bytes32 accountRoot,
        bytes32 previousHash
    ) external onlyRole(REPORTER_ROLE) returns (bytes32 checkpointHash) {
        if (latestProposedEpoch != 0 && !checkpoints[latestProposedEpoch].finalized) {
            revert CheckpointPending(latestProposedEpoch);
        }
        if (epoch <= latestProposedEpoch) revert InvalidEpoch(epoch);
        if (marketRoot == bytes32(0) || accountRoot == bytes32(0)) revert InvalidRoot();
        if (totalBorrowAssets > totalSupplyAssets || totalReserves > totalSupplyAssets) {
            revert InvalidAccounting();
        }
        if (previousHash != latestFinalizedHash) {
            revert StaleParent(previousHash, latestFinalizedHash);
        }

        checkpointHash = computeHash(
            epoch,
            totalSupplyAssets,
            totalBorrowAssets,
            totalReserves,
            marketRoot,
            accountRoot,
            previousHash
        );
        checkpoints[epoch] = Checkpoint({
            epoch: epoch,
            proposedAt: uint40(block.timestamp),
            finalizedAt: 0,
            approvals: 1,
            totalSupplyAssets: totalSupplyAssets,
            totalBorrowAssets: totalBorrowAssets,
            totalReserves: totalReserves,
            marketRoot: marketRoot,
            accountRoot: accountRoot,
            previousHash: previousHash,
            checkpointHash: checkpointHash,
            finalized: false
        });
        latestProposedEpoch = epoch;
        approvals[epoch][msg.sender] = true;
        emit CheckpointProposed(epoch, checkpointHash, previousHash, msg.sender);
        _tryFinalize(epoch);
    }

    function approve(uint64 epoch) external onlyRole(REPORTER_ROLE) {
        Checkpoint storage checkpoint = checkpoints[epoch];
        if (checkpoint.proposedAt == 0 || checkpoint.finalized) {
            revert CheckpointUnavailable(epoch);
        }
        if (checkpoint.previousHash != latestFinalizedHash) {
            revert StaleParent(checkpoint.previousHash, latestFinalizedHash);
        }
        if (approvals[epoch][msg.sender]) revert AlreadyApproved(epoch, msg.sender);
        approvals[epoch][msg.sender] = true;
        checkpoint.approvals += 1;
        emit CheckpointApproved(epoch, msg.sender, checkpoint.approvals);
        _tryFinalize(epoch);
    }

    function _tryFinalize(uint64 epoch) private {
        Checkpoint storage checkpoint = checkpoints[epoch];
        if (checkpoint.approvals < quorum) return;
        checkpoint.finalized = true;
        checkpoint.finalizedAt = uint40(block.timestamp);
        latestFinalizedEpoch = epoch;
        latestFinalizedHash = checkpoint.checkpointHash;
        emit CheckpointFinalized(epoch, checkpoint.checkpointHash, checkpoint.approvals);
    }

    function computeHash(
        uint64 epoch,
        uint256 totalSupplyAssets,
        uint256 totalBorrowAssets,
        uint256 totalReserves,
        bytes32 marketRoot,
        bytes32 accountRoot,
        bytes32 previousHash
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.chainid,
                address(this),
                epoch,
                totalSupplyAssets,
                totalBorrowAssets,
                totalReserves,
                marketRoot,
                accountRoot,
                previousHash
            )
        );
    }

    function pendingApprovals(uint64 epoch) external view returns (uint256) {
        Checkpoint storage checkpoint = checkpoints[epoch];
        if (checkpoint.proposedAt == 0 || checkpoint.finalized || checkpoint.approvals >= quorum) {
            return 0;
        }
        return quorum - checkpoint.approvals;
    }

    function verify(uint64 epoch) external view returns (bool) {
        Checkpoint storage checkpoint = checkpoints[epoch];
        if (checkpoint.proposedAt == 0) return false;
        return checkpoint.checkpointHash
            == computeHash(
            checkpoint.epoch,
            checkpoint.totalSupplyAssets,
            checkpoint.totalBorrowAssets,
            checkpoint.totalReserves,
            checkpoint.marketRoot,
            checkpoint.accountRoot,
            checkpoint.previousHash
        );
    }
}
