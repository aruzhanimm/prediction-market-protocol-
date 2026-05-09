// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarketFactory} from "../../src/core/MarketFactory.sol";
import {Market} from "../../src/core/Market.sol";
import {OutcomeShareToken} from "../../src/tokens/OutcomeShareToken.sol";

contract MarketFactoryTest is Test {
    address internal admin = makeAddr("admin");
    address internal creator = makeAddr("creator");
    address internal stranger = makeAddr("stranger");

    MarketFactory internal factory;
    OutcomeShareToken internal outcomeToken;

    string internal constant QUESTION = "Will ETH be above $5000 by 2026?";
    uint256 internal resolutionTime;

    function setUp() public {
        resolutionTime = block.timestamp + 30 days;
        outcomeToken = new OutcomeShareToken("https://api.example.com/tokens/", admin);
        factory = new MarketFactory(address(outcomeToken), admin);

        vm.startPrank(admin);
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), creator);
        vm.stopPrank();
    }

    // Test 1 — deployMarketDefault deploys via CREATE
    function test_deployDefault_deploysMarket() public {
        vm.prank(creator);
        (, address addr) = factory.deployMarketDefault(QUESTION, resolutionTime);

        assertTrue(addr != address(0), "market address should not be zero");
        assertTrue(addr.code.length > 0, "deployed address should contain code");
    }

    // Test 2 — allMarkets array grows
    function test_deployDefault_allMarketsGrows() public {
        assertEq(factory.totalMarkets(), 0);
        vm.prank(creator);
        factory.deployMarketDefault(QUESTION, resolutionTime);
        assertEq(factory.totalMarkets(), 1);
        vm.prank(creator);
        factory.deployMarketDefault("Second question?", resolutionTime);
        assertEq(factory.totalMarkets(), 2);
    }

    // Test 3 — markets mapping stores correct address
    function test_deployDefault_marketsMapping() public {
        vm.prank(creator);
        (uint256 mid, address addr) = factory.deployMarketDefault(QUESTION, resolutionTime);

        assertEq(factory.markets(mid), addr, "markets mapping should store deployed address");
    }

    // Test 4 — marketCount increments
    function test_marketCount_increments() public {
        assertEq(factory.marketCount(), 0);
        vm.prank(creator);
        factory.deployMarketDefault(QUESTION, resolutionTime);
        assertEq(factory.marketCount(), 1);
        vm.prank(creator);
        factory.deployMarket(keccak256("salt1"), "Q2?", resolutionTime);
        assertEq(factory.marketCount(), 2);
    }

    // Test 5 — deployMarket deploys via CREATE2
    function test_deployCreate2_deploysMarket() public {
        bytes32 salt = keccak256("unique-salt");
        vm.prank(creator);
        (, address addr) = factory.deployMarket(salt, QUESTION, resolutionTime);
        assertTrue(addr != address(0), "market address should not be zero");
        assertTrue(addr.code.length > 0, "deployed address should contain code");
    }

    // Test 6 — CREATE2 address matches off-chain prediction
    function test_deployCreate2_addressMatchesPrediction() public {
        bytes32 salt = keccak256("test-salt");
        uint256 marketId = factory.marketCount(); // snapshot before deploy
        address predicted = factory.predictCreate2Address(salt, marketId, QUESTION, resolutionTime, creator);

        vm.prank(creator);
        (, address actual) = factory.deployMarket(salt, QUESTION, resolutionTime);
        assertEq(actual, predicted, "CREATE2 address should match prediction");
    }

    // Test 7 — Different salts produce different addresses
    function test_deployCreate2_differentSalts_differentAddresses() public {
        bytes32 salt1 = keccak256("salt-alpha");
        bytes32 salt2 = keccak256("salt-beta");
        vm.prank(creator);
        (, address addr1) = factory.deployMarket(salt1, QUESTION, resolutionTime);
        vm.prank(creator);
        (, address addr2) = factory.deployMarket(salt2, QUESTION, resolutionTime);
        assertTrue(addr1 != addr2, "different salts must yield different addresses");
    }

    // Test 8 — Same parameters with same salt revert (already deployed)
    function test_deployCreate2_sameSalt_reverts() public {
        bytes32 salt = keccak256("duplicate-salt");
        vm.prank(creator);
        factory.deployMarket(salt, QUESTION, resolutionTime);
        // Second deployment with the same salt should revert (CREATE2 collision)
        vm.prank(creator);
        vm.expectRevert();
        factory.deployMarket(salt, QUESTION, resolutionTime);
    }

    // Test 9 — deployMarketDefault reverts without role
    function test_deployDefault_reverts_noRole() public {
        vm.prank(stranger);
        vm.expectRevert();
        factory.deployMarketDefault(QUESTION, resolutionTime);
    }

    // Test 10 — deployMarket reverts without role
    function test_deployCreate2_reverts_noRole() public {
        vm.prank(stranger);
        vm.expectRevert();
        factory.deployMarket(keccak256("s"), QUESTION, resolutionTime);
    }

    // Test 11 — getAllMarkets returns full list
    function test_getAllMarkets() public {
        vm.prank(creator);
        (, address a1) = factory.deployMarketDefault(QUESTION, resolutionTime);
        vm.prank(creator);
        (, address a2) = factory.deployMarket(keccak256("s"), "Q2?", resolutionTime);
        address[] memory list = factory.getAllMarkets();
        assertEq(list.length, 2);
        assertEq(list[0], a1);
        assertEq(list[1], a2);
    }

    // Test 12 — totalMarkets returns correct count
    function test_totalMarkets() public {
        assertEq(factory.totalMarkets(), 0);

        vm.prank(creator);
        factory.deployMarketDefault(QUESTION, resolutionTime);
        assertEq(factory.totalMarkets(), 1);
    }

    // Test 13 — Deployed market has correct question
    function test_deployedMarket_question() public {
        vm.prank(creator);
        (, address addr) = factory.deployMarketDefault(QUESTION, resolutionTime);

        assertEq(Market(addr).question(), QUESTION, "question mismatch");
    }

    // Test 14 — Deployed market has correct resolutionTime
    function test_deployedMarket_resolutionTime() public {
        vm.prank(creator);
        (, address addr) = factory.deployMarketDefault(QUESTION, resolutionTime);

        assertEq(Market(addr).resolutionTime(), resolutionTime, "resolutionTime mismatch");
    }

    // Test 15 — Constructor reverts on zero outcomeShareToken
    function test_constructor_reverts_zeroOutcomeToken() public {
        vm.expectRevert(bytes("MF: zero outcome token"));
        new MarketFactory(address(0), admin);
    }
}
