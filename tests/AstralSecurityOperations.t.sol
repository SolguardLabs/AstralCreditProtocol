// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";

import { AstralTimelockQueue } from "../src/governance/AstralTimelockQueue.sol";
import { AstralCheckpointRegistry } from "../src/security/AstralCheckpointRegistry.sol";
import { AstralReserveController } from "../src/treasury/AstralReserveController.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract ConfigTarget {
    uint256 public value;

    function setValue(uint256 newValue) external {
        value = newValue;
    }
}

contract AstralSecurityOperationsTest is Test {
    address internal reporterA = makeAddr("reporter-a");
    address internal reporterB = makeAddr("reporter-b");
    address internal reporterC = makeAddr("reporter-c");

    function testCheckpointRequiresIndependentQuorum() public {
        AstralCheckpointRegistry registry = new AstralCheckpointRegistry(address(this), 2);
        registry.setReporter(reporterA, true);
        registry.setReporter(reporterB, true);

        vm.prank(reporterA);
        bytes32 digest = registry.propose(
            1,
            1_000_000,
            400_000,
            50_000,
            keccak256("market-root-1"),
            keccak256("account-root-1"),
            bytes32(0)
        );
        assertEq(registry.pendingApprovals(1), 1);
        assertEq(registry.latestFinalizedHash(), bytes32(0));

        vm.prank(reporterB);
        registry.approve(1);
        assertEq(registry.latestFinalizedHash(), digest);
        assertEq(registry.latestFinalizedEpoch(), 1);
        assertTrue(registry.verify(1));
    }

    function testCheckpointLinksFinalizedParents() public {
        AstralCheckpointRegistry registry = new AstralCheckpointRegistry(address(this), 1);
        registry.setReporter(reporterA, true);
        vm.prank(reporterA);
        bytes32 first =
            registry.propose(10, 1000, 500, 25, keccak256("m1"), keccak256("a1"), bytes32(0));
        vm.prank(reporterA);
        bytes32 second =
            registry.propose(11, 1100, 550, 30, keccak256("m2"), keccak256("a2"), first);
        assertEq(registry.latestFinalizedHash(), second);
        (,,,,,,,,, bytes32 previousHash,, bool finalized) = registry.checkpoints(11);
        assertEq(previousHash, first);
        assertTrue(finalized);
    }

    function testCheckpointRejectsDuplicateApproval() public {
        AstralCheckpointRegistry registry = new AstralCheckpointRegistry(address(this), 2);
        registry.setReporter(reporterA, true);
        registry.setReporter(reporterB, true);
        vm.prank(reporterA);
        registry.propose(1, 100, 50, 5, keccak256("markets"), keccak256("accounts"), bytes32(0));
        vm.expectRevert(
            abi.encodeWithSelector(AstralCheckpointRegistry.AlreadyApproved.selector, 1, reporterA)
        );
        vm.prank(reporterA);
        registry.approve(1);
    }

    function testReporterRemovalCannotBreakQuorum() public {
        AstralCheckpointRegistry registry = new AstralCheckpointRegistry(address(this), 2);
        registry.setReporter(reporterA, true);
        registry.setReporter(reporterB, true);
        vm.expectRevert(
            abi.encodeWithSelector(AstralCheckpointRegistry.InvalidQuorum.selector, 2, 1)
        );
        registry.setReporter(reporterB, false);
        registry.setReporter(reporterC, true);
        assertEq(registry.reporterCount(), 3);
    }

    function testTimelockExecutesOnlyInsideWindow() public {
        AstralTimelockQueue queue = new AstralTimelockQueue(address(this), 1 days, 2 days);
        ConfigTarget target = new ConfigTarget();
        bytes memory data = abi.encodeCall(target.setValue, (42));
        bytes32 salt = keccak256("astral-parameter-change");
        bytes32 id = queue.queue(address(target), 0, data, salt);

        vm.expectPartialRevert(AstralTimelockQueue.OperationNotReady.selector);
        queue.execute(address(target), 0, data, salt);
        vm.warp(block.timestamp + 1 days);
        assertTrue(queue.isReady(id));
        queue.execute(address(target), 0, data, salt);
        assertEq(target.value(), 42);
    }

    function testGuardianCanCancelQueuedOperation() public {
        AstralTimelockQueue queue = new AstralTimelockQueue(address(this), 1 hours, 1 days);
        ConfigTarget target = new ConfigTarget();
        bytes memory data = abi.encodeCall(target.setValue, (7));
        bytes32 salt = bytes32(uint256(7));
        bytes32 id = queue.queue(address(target), 0, data, salt);
        queue.cancel(id);
        assertFalse(queue.isReady(id));
        vm.warp(block.timestamp + 1 hours);
        vm.expectRevert(
            abi.encodeWithSelector(AstralTimelockQueue.OperationUnavailable.selector, id)
        );
        queue.execute(address(target), 0, data, salt);
    }

    function testReserveControllerForwardsFullBalance() public {
        address payout = makeAddr("payout");
        AstralReserveController controller = new AstralReserveController(address(this), payout);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        asset.mint(address(controller), 250_000e6);
        uint256 forwarded = controller.forward(address(asset));
        assertEq(forwarded, 250_000e6);
        assertEq(asset.balanceOf(payout), 250_000e6);
        assertEq(asset.balanceOf(address(controller)), 0);
    }
}
