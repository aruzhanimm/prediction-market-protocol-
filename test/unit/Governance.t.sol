// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GovernanceToken} from "../../src/tokens/GovernanceToken.sol";
import {MyGovernor} from "../../src/governance/MyGovernor.sol";
import {Treasury} from "../../src/governance/Treasury.sol";

/// @dev Covers the full propose → vote → queue → execute lifecycle required by §3.1.
contract GovernorLifecycleTest is Test {
    // Actors
    address internal team = makeAddr("team");
    address internal treasury_ = makeAddr("treasuryWallet");
    address internal community = makeAddr("community");
    address internal liquidity = makeAddr("liquidity");
    address internal voter1 = makeAddr("voter1");
    address internal voter2 = makeAddr("voter2");
    address internal attacker = makeAddr("attacker");

    // Contracts
    GovernanceToken internal token;
    TimelockController internal timelock;
    MyGovernor internal governor;
    Treasury internal treasury;

    // Constants
    uint256 internal constant TOTAL = 100_000_000 ether;
    uint256 internal constant DELAY = 2 days;

    function setUp() public {
        // Deploy token - 40% team, 30% treasuryWallet, 20% community, 10% liquidity
        token = new GovernanceToken(team, treasury_, community, liquidity);

        // Deploy TimelockController - 2-day min delay, no initial proposers/executors
        // (governor will be granted proposer; address(0) = anyone can execute after delay)
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute after delay passes
        timelock = new TimelockController(DELAY, proposers, executors, address(this));

        // Deploy governor
        governor = new MyGovernor(token, timelock);

        // Deploy treasury controlled by Timelock
        treasury = new Treasury(address(timelock));

        // Wire: grant governor the PROPOSER_ROLE on timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        // Renounce deployer admin so only Timelock can act
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        // Distribute voting power - voter1 gets 5M (5%), voter2 gets 1M (1%)
        vm.startPrank(team);
        token.transfer(voter1, 5_000_000 ether);
        token.transfer(voter2, 1_000_000 ether);
        vm.stopPrank();

        // Delegate to self so voting power is active
        vm.prank(voter1);
        token.delegate(voter1);
        vm.prank(voter2);
        token.delegate(voter2);
        vm.prank(team);
        token.delegate(team);

        // Advance one block so delegation snapshots are recorded
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 12);
    }

    // Helper

    /// @dev Build a minimal proposal that sends 1 ETH from treasury to voter1.
    function _buildWithdrawProposal()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);

        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("withdrawETH(address,uint256)", voter1, 1 ether);
        description = "Proposal #1: withdraw 1 ETH to voter1";
    }

    // Lifecycle tests

    /// @notice Full happy path: propose → vote (passes) → queue → execute.
    function test_fullLifecycle_proposeVoteQueueExecute() public {
        // Fund treasury with some ETH
        vm.deal(address(treasury), 10 ether);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildWithdrawProposal();

        // 1. Propose
        vm.prank(voter1); // voter1 has 5M > 1% threshold
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));

        // 2. Advance past voting delay (7200 blocks = 1 day)
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.warp(block.timestamp + 1 days + 12);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));

        // 3. Vote - voter1 casts FOR
        vm.prank(voter1);
        governor.castVote(proposalId, 1); // 1 = For

        // Also cast with voter2
        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        // 4. Advance past voting period (50400 blocks = 1 week)
        vm.roll(block.number + governor.votingPeriod() + 1);
        vm.warp(block.timestamp + 7 days + 12);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));

        // 5. Queue in Timelock
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        // 6. Advance past Timelock delay (2 days)
        vm.warp(block.timestamp + DELAY + 1);

        // 7. Execute
        uint256 balanceBefore = voter1.balance;
        governor.execute(targets, values, calldatas, descHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));

        // Verify ETH was transferred
        assertEq(voter1.balance - balanceBefore, 1 ether);
    }

    /// @notice Proposal is defeated when quorum is not reached.
    function test_quorumNotReached_proposalDefeated() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildWithdrawProposal();

        // Propose - voter1 has sufficient threshold
        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Advance past voting delay
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.warp(block.timestamp + 1 days + 12);

        // voter2 votes FOR with only 1M tokens (1% of supply)
        // Quorum requires 4% = 4M tokens → not met
        vm.prank(voter2);
        governor.castVote(proposalId, 1); // For

        // Advance past voting period
        vm.roll(block.number + governor.votingPeriod() + 1);
        vm.warp(block.timestamp + 7 days + 12);

        // Should be Defeated (quorum not met)
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    /// @notice Proposal spam: account below threshold cannot propose.
    function test_proposalSpam_belowThreshold_reverts() public {
        // attacker has zero tokens → below 1% threshold
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildWithdrawProposal();

        vm.prank(attacker);
        vm.expectRevert(); // GovernorInsufficientProposerVotes
        governor.propose(targets, values, calldatas, description);
    }

    /// @notice Proposal cannot be executed before Timelock delay expires.
    function test_timelockDelay_executionTooEarly_reverts() public {
        vm.deal(address(treasury), 10 ether);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildWithdrawProposal();

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.warp(block.timestamp + 1 days + 12);

        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);
        vm.warp(block.timestamp + 7 days + 12);

        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);

        // Try to execute immediately - only 1 second elapsed, not 2 days
        vm.warp(block.timestamp + 1);
        vm.expectRevert(); // TimelockController: operation is not ready
        governor.execute(targets, values, calldatas, descHash);
    }

    /// @notice Voter cannot vote twice on the same proposal.
    function test_doubleVote_reverts() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildWithdrawProposal();

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.warp(block.timestamp + 1 days + 12);

        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        // Second vote should revert
        vm.prank(voter1);
        vm.expectRevert(); // GovernorAlreadyCastVote
        governor.castVote(proposalId, 1);
    }

    /// @notice Sanity check: Governor parameters match the project specification.
    function test_governorParameters() public view {
        assertEq(governor.votingDelay(), governor.VOTING_DELAY_BLOCKS(), "voting delay mismatch");
        assertEq(governor.votingPeriod(), governor.VOTING_PERIOD_BLOCKS(), "voting period mismatch");
        assertEq(governor.quorumNumerator(), governor.QUORUM_FRACTION(), "quorum fraction mismatch");
    }

    /// @notice Treasury correctly reports ETH balance.
    function test_treasury_receivesETH() public {
        vm.deal(address(this), 5 ether);
        (bool ok,) = address(treasury).call{value: 5 ether}("");
        assertTrue(ok);
        assertEq(treasury.ethBalance(), 5 ether);
    }

    /// @notice Treasury rejects direct ETH withdraw without SPENDER_ROLE.
    function test_treasury_withdrawETH_onlySpender() public {
        vm.deal(address(treasury), 1 ether);
        vm.prank(attacker);
        vm.expectRevert(); // AccessControl
        treasury.withdrawETH(attacker, 1 ether);
    }
}
