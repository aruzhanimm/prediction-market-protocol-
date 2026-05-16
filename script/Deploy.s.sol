// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {GovernanceToken} from "../src/tokens/GovernanceToken.sol";
import {OutcomeShareToken} from "../src/tokens/OutcomeShareToken.sol";

import {PredictionMarket} from "../src/core/PredictionMarket.sol";
import {PredictionMarketV2} from "../src/core/PredictionMarketV2.sol";
import {MarketAMM} from "../src/core/MarketAMM.sol";
import {MarketFactory} from "../src/core/MarketFactory.sol";

import {FeeVault} from "../src/vault/FeeVault.sol";
import {ChainlinkResolver} from "../src/oracle/ChainlinkResolver.sol";

import {MyGovernor} from "../src/governance/MyGovernor.sol";
import {Treasury} from "../src/governance/Treasury.sol";

/// @title Deploy
/// @notice Deploys the full prediction market protocol stack to an L2 testnet.
contract Deploy is Script {
    uint256 internal constant TIMELOCK_DELAY = 2 days;
    uint256 internal constant MARKET_ID = 0;
    uint256 internal constant ORACLE_STALENESS_THRESHOLD = 1 hours;

    string internal constant OUTCOME_BASE_URI = "https://api.prediction-market.local/metadata/{id}.json";

    uint256 internal deployerPrivateKey;
    address internal deployer;

    address internal teamWallet;
    address internal treasuryWallet;
    address internal communityWallet;
    address internal liquidityWallet;
    address internal chainlinkFeed;

    GovernanceToken internal governanceToken;
    TimelockController internal timelock;
    MyGovernor internal governor;
    Treasury internal treasury;

    OutcomeShareToken internal outcomeToken;

    PredictionMarket internal predictionMarketImpl;
    PredictionMarketV2 internal predictionMarketV2Impl;
    ERC1967Proxy internal predictionMarketProxy;
    PredictionMarket internal predictionMarket;

    MarketAMM internal marketAMM;
    FeeVault internal feeVault;
    MarketFactory internal marketFactory;
    ChainlinkResolver internal resolver;

    function run() external {
        _loadConfig();

        vm.startBroadcast(deployerPrivateKey);

        _deployGovernanceStack();
        _deployOutcomeToken();
        _deployPredictionMarketProxy();
        _deployAmmVaultFactoryAndResolver();
        _wireRolesAndPermissions();

        vm.stopBroadcast();

        _logDeployment();
    }

    /// @dev Loads deployer key and configurable addresses from environment variables.
    function _loadConfig() internal {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        teamWallet = vm.envOr("TEAM_WALLET", deployer);
        treasuryWallet = vm.envOr("TREASURY_WALLET", deployer);
        communityWallet = vm.envOr("COMMUNITY_WALLET", deployer);
        liquidityWallet = vm.envOr("LIQUIDITY_WALLET", deployer);

        chainlinkFeed = vm.envAddress("CHAINLINK_FEED");
    }

    /// @dev Deploys ERC20Votes token, Timelock, Governor, and Treasury.
    function _deployGovernanceStack() internal {
        governanceToken = new GovernanceToken(teamWallet, treasuryWallet, communityWallet, liquidityWallet);

        address[] memory proposers = new address[](0);

        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, deployer);
        governor = new MyGovernor(governanceToken, timelock);
        treasury = new Treasury(address(timelock));

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
    }

    /// @dev Deploys the ERC-1155 outcome share token.
    function _deployOutcomeToken() internal {
        outcomeToken = new OutcomeShareToken(OUTCOME_BASE_URI, deployer);
    }

    /// @dev Deploys PredictionMarket V1 implementation, proxy, and V2 implementation.
    function _deployPredictionMarketProxy() internal {
        predictionMarketImpl = new PredictionMarket();

        bytes memory initData =
            abi.encodeWithSelector(PredictionMarket.initialize.selector, address(outcomeToken), deployer);

        predictionMarketProxy = new ERC1967Proxy(address(predictionMarketImpl), initData);
        predictionMarket = PredictionMarket(address(predictionMarketProxy));

        predictionMarketV2Impl = new PredictionMarketV2();
    }

    /// @dev Deploys protocol modules: AMM, vault, factory, and Chainlink resolver.
    function _deployAmmVaultFactoryAndResolver() internal {
        marketAMM = new MarketAMM(address(outcomeToken), MARKET_ID);

        feeVault = new FeeVault(address(marketAMM), "Prediction Market LP Vault", "vPMLP", deployer);

        marketFactory = new MarketFactory(address(outcomeToken), deployer);

        resolver = new ChainlinkResolver(chainlinkFeed, address(predictionMarket), ORACLE_STALENESS_THRESHOLD, deployer);
    }

    /// @dev Grants required roles and connects deployed modules.
    function _wireRolesAndPermissions() internal {
        bytes32 minterRole = outcomeToken.MINTER_ROLE();

        outcomeToken.grantRole(minterRole, address(predictionMarket));
        outcomeToken.grantRole(minterRole, address(marketFactory));

        predictionMarket.setFactory(address(marketFactory));
        predictionMarket.setResolver(address(resolver));

        predictionMarket.grantRole(predictionMarket.DEFAULT_ADMIN_ROLE(), address(timelock));
        predictionMarket.grantRole(predictionMarket.MARKET_CREATOR_ROLE(), address(timelock));
        predictionMarket.grantRole(predictionMarket.RESOLVER_ROLE(), address(timelock));

        outcomeToken.grantRole(outcomeToken.DEFAULT_ADMIN_ROLE(), address(timelock));
        outcomeToken.grantRole(minterRole, address(timelock));

        // After setup, deployer no longer controls the Timelock directly.
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
    }

    /// @dev Prints deployed addresses for README and deployment docs.
    function _logDeployment() internal view {
        console2.log("=== Prediction Market Protocol Deployment ===");
        console2.log("Deployer:", deployer);

        console2.log("GovernanceToken:", address(governanceToken));
        console2.log("TimelockController:", address(timelock));
        console2.log("MyGovernor:", address(governor));
        console2.log("Treasury:", address(treasury));

        console2.log("OutcomeShareToken:", address(outcomeToken));

        console2.log("PredictionMarket implementation V1:", address(predictionMarketImpl));
        console2.log("PredictionMarket proxy:", address(predictionMarket));
        console2.log("PredictionMarket implementation V2:", address(predictionMarketV2Impl));

        console2.log("MarketAMM:", address(marketAMM));
        console2.log("FeeVault:", address(feeVault));
        console2.log("MarketFactory:", address(marketFactory));
        console2.log("ChainlinkResolver:", address(resolver));
        console2.log("Chainlink feed:", chainlinkFeed);
    }
}
