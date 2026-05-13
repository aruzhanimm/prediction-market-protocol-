// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {GovernanceToken} from "../../src/tokens/GovernanceToken.sol";
import {MyGovernor} from "../../src/governance/MyGovernor.sol";
import {Treasury} from "../../src/governance/Treasury.sol";

/// @title GovernorLifecycleTest
/// @notice Covers the required OpenZeppelin Governor lifecycle:
///         propose -> vote -> queue -> execute.
/// @dev The setup mirrors the production governance stack:
///      GovernanceToken + MyGovernor + TimelockController + Treasury.
contract GovernorLifecycleTest is Test {
    // Actors

    address internal team = makeAddr("team");
    address internal treasuryWallet = makeAddr("treasuryWallet");
    address internal community = makeAddr("community");
    address internal liquidity = makeAddr("liquidity");

    address internal voter1 = makeAddr("voter1");
    address internal voter2 = makeAddr("voter2");

    // Contracts

    GovernanceToken internal token;
    TimelockController internal timelock;
    MyGovernor internal governor;
    Treasury internal treasury;

    // Constants

    uint256 internal constant TIMELOCK_DELAY = 2 days;

    function setUp() public {
        // Deploy governance token.
        // Distribution is handled inside GovernanceToken constructor.
        token = new GovernanceToken(team, treasuryWallet, community, liquidity);

        // Deploy TimelockController.
        // Governor will be granted proposer/canceller roles.
        // address(0) executor means anyone can execute after the delay passes.
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, address(this));

        // Deploy Governor connected to token and timelock.
        governor = new MyGovernor(token, timelock);

        // Deploy Treasury controlled by the Timelock.
        treasury = new Treasury(address(timelock));

        // Wire Governor and Timelock permissions.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // Remove deployer admin power so governance stack controls the system.
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        // Give voter1 and voter2 voting power.
        // voter1 has 5%, voter2 has 1%.
        vm.startPrank(team);
        token.transfer(voter1, 5_000_000 ether);
        token.transfer(voter2, 1_000_000 ether);
        vm.stopPrank();

        // Delegation is required for ERC20Votes voting power.
        vm.prank(voter1);
        token.delegate(voter1);

        vm.prank(voter2);
        token.delegate(voter2);

        vm.prank(team);
        token.delegate(team);

        // Advance one block so voting snapshots are available.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 12);
    }

    // Helper

    /// @dev Builds a simple proposal that sends 1 ETH from Treasury to voter1.
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

    // Lifecycle test

    /// @notice Full happy path: propose -> vote -> queue -> execute.
    function test_fullLifecycle_proposeVoteQueueExecute() public {
        // Fund Treasury so the proposal has something to execute.
        vm.deal(address(treasury), 10 ether);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildWithdrawProposal();

        // 1. Propose.
        // voter1 has enough voting power to pass proposal threshold.
        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));

        // 2. Advance past voting delay.
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.warp(block.timestamp + 1 days + 12);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));

        // 3. Vote FOR.
        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        // 4. Advance past voting period.
        vm.roll(block.number + governor.votingPeriod() + 1);
        vm.warp(block.timestamp + 7 days + 12);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));

        // 5. Queue through Timelock.
        bytes32 descriptionHash = keccak256(bytes(description));

        governor.queue(targets, values, calldatas, descriptionHash);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        // 6. Advance past Timelock delay.
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // 7. Execute.
        uint256 balanceBefore = voter1.balance;

        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));

        // Verify Treasury action was executed.
        assertEq(voter1.balance - balanceBefore, 1 ether);
    }

    /// @notice Sanity check: Governor parameters match the project specification.
    function test_governorParameters() public view {
        assertEq(governor.votingDelay(), governor.VOTING_DELAY_BLOCKS(), "voting delay mismatch");
        assertEq(governor.votingPeriod(), governor.VOTING_PERIOD_BLOCKS(), "voting period mismatch");
        assertEq(governor.quorumNumerator(), governor.QUORUM_FRACTION(), "quorum fraction mismatch");
    }

    /// @notice Sanity check: Treasury can receive ETH.
    function test_treasury_receivesETH() public {
        vm.deal(address(this), 5 ether);

        (bool ok,) = address(treasury).call{value: 5 ether}("");

        assertTrue(ok);
        assertEq(treasury.ethBalance(), 5 ether);
    }
}
