// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {MyGovernor} from "../src/governance/MyGovernor.sol";
import {PredictionMarket} from "../src/core/PredictionMarket.sol";
import {OutcomeShareToken} from "../src/tokens/OutcomeShareToken.sol";

/// @title PostDeployCheck
/// @notice Checks that deployed protocol contracts are wired correctly.
/// @dev This script does not deploy anything. It reads deployed addresses from environment variables.
contract PostDeployCheck is Script {
    uint256 internal constant EXPECTED_TIMELOCK_DELAY = 2 days;
    uint256 internal constant EXPECTED_VOTING_DELAY = 7200;
    uint256 internal constant EXPECTED_VOTING_PERIOD = 50_400;
    uint256 internal constant EXPECTED_QUORUM_NUMERATOR = 4;

    address internal timelockAddress;
    address internal governorAddress;
    address internal treasuryAddress;
    address internal outcomeTokenAddress;
    address internal predictionMarketAddress;
    address internal marketFactoryAddress;
    address internal resolverAddress;

    TimelockController internal timelock;
    MyGovernor internal governor;
    OutcomeShareToken internal outcomeToken;
    PredictionMarket internal predictionMarket;

    /// @notice Entry point for post-deployment verification.
    /// @dev The function is not view because it stores env-loaded addresses into script state variables.
    function run() external {
        _loadAddresses();
        _bindContracts();

        _checkTimelock();
        _checkGovernor();
        _checkPredictionMarket();
        _checkOutcomeToken();
        _checkTreasuryControl();

        console2.log("Post-deployment checks passed.");
    }

    /// @dev Loads deployed addresses from environment variables.
    ///      These variables must be set before running the script.
    function _loadAddresses() internal {
        timelockAddress = vm.envAddress("TIMELOCK");
        governorAddress = vm.envAddress("GOVERNOR");
        treasuryAddress = vm.envAddress("TREASURY");
        outcomeTokenAddress = vm.envAddress("OUTCOME_TOKEN");
        predictionMarketAddress = vm.envAddress("PREDICTION_MARKET_PROXY");
        marketFactoryAddress = vm.envAddress("MARKET_FACTORY");
        resolverAddress = vm.envAddress("CHAINLINK_RESOLVER");
    }

    /// @dev Converts raw addresses into typed contract handles.
    function _bindContracts() internal {
        timelock = TimelockController(payable(timelockAddress));
        governor = MyGovernor(payable(governorAddress));
        outcomeToken = OutcomeShareToken(outcomeTokenAddress);
        predictionMarket = PredictionMarket(predictionMarketAddress);
    }

    /// @dev Verifies Timelock delay and Governor permissions.
    ///      Governor must be able to propose and cancel operations.
    ///      address(0) as executor means anyone can execute after delay.
    function _checkTimelock() internal view {
        require(timelock.getMinDelay() == EXPECTED_TIMELOCK_DELAY, "Timelock delay mismatch");

        require(timelock.hasRole(timelock.PROPOSER_ROLE(), governorAddress), "Governor missing PROPOSER_ROLE");

        require(timelock.hasRole(timelock.CANCELLER_ROLE(), governorAddress), "Governor missing CANCELLER_ROLE");

        require(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), "Open executor role missing");

        console2.log("Timelock check passed.");
    }

    /// @dev Verifies Governor parameters required by the project specification.
    function _checkGovernor() internal view {
        require(governor.votingDelay() == EXPECTED_VOTING_DELAY, "Voting delay mismatch");
        require(governor.votingPeriod() == EXPECTED_VOTING_PERIOD, "Voting period mismatch");
        require(governor.quorumNumerator() == EXPECTED_QUORUM_NUMERATOR, "Quorum mismatch");

        require(address(governor.timelock()) == timelockAddress, "Governor timelock mismatch");

        console2.log("Governor check passed.");
    }

    /// @dev Verifies PredictionMarket proxy configuration and protocol roles.
    ///      Timelock should be able to govern market creation and dispute resolution.
    function _checkPredictionMarket() internal view {
        require(address(predictionMarket.outcomeToken()) == outcomeTokenAddress, "Outcome token mismatch");
        require(predictionMarket.factory() == marketFactoryAddress, "Factory mismatch");
        require(predictionMarket.resolver() == resolverAddress, "Resolver mismatch");

        require(
            predictionMarket.hasRole(predictionMarket.DEFAULT_ADMIN_ROLE(), timelockAddress),
            "Timelock missing PredictionMarket admin role"
        );

        require(
            predictionMarket.hasRole(predictionMarket.MARKET_CREATOR_ROLE(), timelockAddress),
            "Timelock missing market creator role"
        );

        require(
            predictionMarket.hasRole(predictionMarket.RESOLVER_ROLE(), timelockAddress),
            "Timelock missing resolver role"
        );

        console2.log("PredictionMarket check passed.");
    }

    /// @dev Verifies ERC-1155 outcome token admin and minting roles.
    ///      PredictionMarket and Factory need minting permission for market lifecycle flows.
    function _checkOutcomeToken() internal view {
        bytes32 defaultAdminRole = outcomeToken.DEFAULT_ADMIN_ROLE();
        bytes32 minterRole = outcomeToken.MINTER_ROLE();

        require(
            outcomeToken.hasRole(defaultAdminRole, timelockAddress), "Timelock missing OutcomeShareToken admin role"
        );

        require(outcomeToken.hasRole(minterRole, predictionMarketAddress), "PredictionMarket missing MINTER_ROLE");

        require(outcomeToken.hasRole(minterRole, marketFactoryAddress), "MarketFactory missing MINTER_ROLE");

        require(outcomeToken.hasRole(minterRole, timelockAddress), "Timelock missing MINTER_ROLE");

        console2.log("OutcomeShareToken check passed.");
    }

    /// @dev Verifies that Treasury is controlled by Timelock.
    ///      This supports both common designs:
    ///      1. Ownable Treasury with owner() == Timelock.
    ///      2. AccessControl Treasury where Timelock has SPENDER_ROLE.
    function _checkTreasuryControl() internal view {
        bool checked;

        // Try Ownable-style owner() check.
        (bool ownerOk, bytes memory ownerData) = treasuryAddress.staticcall(abi.encodeWithSignature("owner()"));

        if (ownerOk && ownerData.length >= 32) {
            address owner = abi.decode(ownerData, (address));
            require(owner == timelockAddress, "Treasury owner is not Timelock");
            checked = true;
        }

        // Try AccessControl-style SPENDER_ROLE check.
        (bool roleOk, bytes memory roleData) = treasuryAddress.staticcall(abi.encodeWithSignature("SPENDER_ROLE()"));

        if (roleOk && roleData.length >= 32) {
            bytes32 spenderRole = abi.decode(roleData, (bytes32));

            (bool hasRoleOk, bytes memory hasRoleData) = treasuryAddress.staticcall(
                abi.encodeWithSignature("hasRole(bytes32,address)", spenderRole, timelockAddress)
            );

            require(hasRoleOk && hasRoleData.length >= 32, "Treasury role check failed");
            require(abi.decode(hasRoleData, (bool)), "Timelock missing Treasury SPENDER_ROLE");

            checked = true;
        }

        require(checked, "Treasury control check unavailable");

        console2.log("Treasury check passed.");
    }
}
