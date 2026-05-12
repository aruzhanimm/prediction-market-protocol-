// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PredictionMarket} from "../../src/core/PredictionMarket.sol";
import {OutcomeShareToken} from "../../src/tokens/OutcomeShareToken.sol";

contract PredictionMarketTest is Test {
    OutcomeShareToken internal outcomeToken;
    PredictionMarket internal pm; // proxy - the live instance
    PredictionMarket internal impl; // bare implementation (for upgrade tests)

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal resolver = makeAddr("resolver");

    uint256 internal constant RESOLUTION_DELAY = 7 days;
    uint256 internal constant INITIAL_SHARES = 1_000 ether;

    function setUp() public {
        // Deploy ERC-1155 outcome token
        outcomeToken = new OutcomeShareToken("https://api.example.com/", admin);

        // Deploy PredictionMarket behind ERC-1967 UUPS proxy
        impl = new PredictionMarket();

        bytes memory initData = abi.encodeCall(PredictionMarket.initialize, (address(outcomeToken), admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pm = PredictionMarket(address(proxy));

        // Grant PredictionMarket MINTER_ROLE on the outcome token
        bytes32 minterRole = outcomeToken.MINTER_ROLE();
        vm.prank(admin);
        outcomeToken.grantRole(minterRole, address(pm));
    }

    //  Helpers

    function _createMarket(address creator, string memory q, uint256 delay) internal returns (uint256 marketId) {
        vm.prank(creator);
        return pm.createMarket(q, block.timestamp + delay, INITIAL_SHARES, creator);
    }

    // createMarket

    // Test 1 - createMarket increments marketCount
    function test_createMarket_incrementsCount() public {
        _createMarket(admin, "Will ETH hit $5k?", RESOLUTION_DELAY);
        assertEq(pm.marketCount(), 1, "marketCount should be 1");

        _createMarket(admin, "Will BTC hit $100k?", RESOLUTION_DELAY);
        assertEq(pm.marketCount(), 2, "marketCount should be 2");
    }

    // Test 2 - createMarket mints YES+NO shares to liquidity provider
    function test_createMarket_mintsShares() public {
        uint256 marketId = _createMarket(admin, "Will ETH hit $5k?", RESOLUTION_DELAY);

        uint256 yesId = outcomeToken.yesTokenId(marketId);
        uint256 noId = outcomeToken.noTokenId(marketId);

        assertEq(outcomeToken.balanceOf(admin, yesId), INITIAL_SHARES, "YES shares minted");
        assertEq(outcomeToken.balanceOf(admin, noId), INITIAL_SHARES, "NO shares minted");
    }

    // Test 3 - createMarket emits MarketCreated event
    function test_createMarket_emitsEvent() public {
        uint256 resolutionTime = block.timestamp + RESOLUTION_DELAY;
        vm.expectEmit(true, true, false, true);
        emit PredictionMarket.MarketCreated(0, admin, "Q?", resolutionTime);
        vm.prank(admin);
        pm.createMarket("Q?", resolutionTime, INITIAL_SHARES, admin);
    }

    // Test 4 - createMarket reverts for non-creator
    function test_createMarket_reverts_noRole() public {
        vm.prank(alice);
        vm.expectRevert();
        pm.createMarket("Q?", block.timestamp + 1 days, INITIAL_SHARES, alice);
    }

    // Test 5 - createMarket reverts when resolutionTime is in the past
    function test_createMarket_reverts_pastResolutionTime() public {
        vm.prank(admin);
        vm.expectRevert();
        pm.createMarket("Q?", block.timestamp - 1, INITIAL_SHARES, admin);
    }

    // Test 6 - createMarket reverts with zero initialShares
    function test_createMarket_reverts_zeroShares() public {
        vm.prank(admin);
        vm.expectRevert();
        pm.createMarket("Q?", block.timestamp + 1 days, 0, admin);
    }

    // resolveMarket

    // Test 7 - resolveMarket sets outcome and status correctly
    function test_resolveMarket_setsOutcome() public {
        uint256 marketId = _createMarket(admin, "Will ETH hit $5k?", RESOLUTION_DELAY);

        vm.warp(block.timestamp + RESOLUTION_DELAY + 1);

        vm.prank(admin); // admin has RESOLVER_ROLE
        pm.resolveMarket(marketId, true);

        PredictionMarket.MarketData memory data = pm.getMarket(marketId);
        assertEq(uint256(data.status), uint256(PredictionMarket.MarketStatus.Resolved));
        assertTrue(data.outcome, "outcome should be true (YES wins)");
    }

    // Test 8 - resolveMarket reverts before resolutionTime
    function test_resolveMarket_reverts_tooEarly() public {
        uint256 marketId = _createMarket(admin, "Q?", RESOLUTION_DELAY);

        vm.prank(admin);
        vm.expectRevert();
        pm.resolveMarket(marketId, true);
    }

    // Test 9 - resolveMarket reverts for non-resolver
    function test_resolveMarket_reverts_noRole() public {
        uint256 marketId = _createMarket(admin, "Q?", RESOLUTION_DELAY);
        vm.warp(block.timestamp + RESOLUTION_DELAY + 1);

        vm.prank(alice);
        vm.expectRevert();
        pm.resolveMarket(marketId, true);
    }

    // Test 10 - resolveMarket reverts on already-resolved market
    function test_resolveMarket_reverts_alreadyResolved() public {
        uint256 marketId = _createMarket(admin, "Q?", RESOLUTION_DELAY);
        vm.warp(block.timestamp + RESOLUTION_DELAY + 1);

        vm.prank(admin);
        pm.resolveMarket(marketId, true);

        vm.prank(admin);
        vm.expectRevert();
        pm.resolveMarket(marketId, false); // second resolution must fail
    }

    // redeemShares

    // Test 11 - Winner can redeem YES shares after YES resolution
    function test_redeemShares_yesWinner() public {
        uint256 marketId = _createMarket(admin, "Q?", RESOLUTION_DELAY);
        vm.warp(block.timestamp + RESOLUTION_DELAY + 1);
        vm.prank(admin);
        pm.resolveMarket(marketId, true); // YES wins

        uint256 yesId = outcomeToken.yesTokenId(marketId);
        uint256 sharesBefore = outcomeToken.balanceOf(admin, yesId);
        assertGt(sharesBefore, 0, "admin has YES shares");

        vm.prank(admin);
        pm.redeemShares(marketId);

        assertEq(outcomeToken.balanceOf(admin, yesId), 0, "YES shares burned after redemption");
    }

    // Test 12 - redeemShares reverts on unresolved market
    function test_redeemShares_reverts_notResolved() public {
        uint256 marketId = _createMarket(admin, "Q?", RESOLUTION_DELAY);

        vm.prank(admin);
        vm.expectRevert();
        pm.redeemShares(marketId);
    }

    // Test 13 - redeemShares reverts when caller has zero winning shares
    function test_redeemShares_reverts_zeroShares() public {
        uint256 marketId = _createMarket(admin, "Q?", RESOLUTION_DELAY);
        vm.warp(block.timestamp + RESOLUTION_DELAY + 1);
        vm.prank(admin);
        pm.resolveMarket(marketId, true); // YES wins

        vm.prank(alice); // alice has no shares
        vm.expectRevert();
        pm.redeemShares(marketId);
    }

    // UUPS proxy and roles

    // Test 14 - initialize cannot be called twice
    function test_initialize_reverts_alreadyInitialized() public {
        vm.expectRevert();
        pm.initialize(address(outcomeToken), admin);
    }

    // Test 15 - Implementation initializer is disabled (proxy pattern safety)
    function test_implementation_initializerDisabled() public {
        PredictionMarket freshImpl = new PredictionMarket();
        vm.expectRevert();
        freshImpl.initialize(address(outcomeToken), admin);
    }

    // Test 16 - setResolver grants RESOLVER_ROLE to new resolver
    function test_setResolver_grantsRole() public {
        vm.prank(admin);
        pm.setResolver(resolver);

        assertTrue(pm.hasRole(pm.RESOLVER_ROLE(), resolver), "resolver has RESOLVER_ROLE");
        assertEq(pm.resolver(), resolver, "resolver address stored");
    }

    // Test 17 - Non-admin cannot upgrade
    function test_upgrade_reverts_nonAdmin() public {
        PredictionMarket newImpl = new PredictionMarket();
        vm.prank(alice);
        vm.expectRevert();
        pm.upgradeToAndCall(address(newImpl), "");
    }

    // Test 18 - isOpen returns true for open market
    function test_isOpen_returnsTrue() public {
        uint256 marketId = _createMarket(admin, "Q?", RESOLUTION_DELAY);
        assertTrue(pm.isOpen(marketId), "market should be open");
    }

    // Test 19 - isOpen returns false after resolution
    function test_isOpen_returnsFalse_afterResolution() public {
        uint256 marketId = _createMarket(admin, "Q?", RESOLUTION_DELAY);
        vm.warp(block.timestamp + RESOLUTION_DELAY + 1);
        vm.prank(admin);
        pm.resolveMarket(marketId, false);

        assertFalse(pm.isOpen(marketId), "market should not be open");
    }

    // Test 20 - cancelMarket sets status to Cancelled
    function test_cancelMarket() public {
        uint256 marketId = _createMarket(admin, "Q?", RESOLUTION_DELAY);

        vm.prank(admin);
        pm.cancelMarket(marketId);

        PredictionMarket.MarketData memory data = pm.getMarket(marketId);
        assertEq(uint256(data.status), uint256(PredictionMarket.MarketStatus.Cancelled), "status should be Cancelled");
    }
}
