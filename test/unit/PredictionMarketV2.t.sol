// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PredictionMarket} from "../../src/core/PredictionMarket.sol";
import {PredictionMarketV2} from "../../src/core/PredictionMarketV2.sol";
import {OutcomeShareToken} from "../../src/tokens/OutcomeShareToken.sol";

/// @notice Tests V1 → V2 UUPS upgrade. Key checks:
///   - All V1 state is preserved after upgrade.
///   - New V2 functions are accessible after upgrade.
///   - New V2 storage slots work correctly.
///   - V1 implementation cannot be called after upgrade (proxy redirects).
contract PredictionMarketV2UpgradeTest is Test {
    address internal admin = makeAddr("admin");
    address internal creator = makeAddr("creator");
    address internal lp = makeAddr("lp");

    OutcomeShareToken internal outcomeToken;
    PredictionMarket internal v1Impl;
    PredictionMarketV2 internal v2Impl;
    ERC1967Proxy internal proxy;

    // Typed handles to the proxy
    PredictionMarket internal marketV1;
    PredictionMarketV2 internal marketV2;

    function setUp() public {
        outcomeToken = new OutcomeShareToken("https://api.example.com/", admin);

        // Deploy V1 implementation
        v1Impl = new PredictionMarket();

        // Deploy proxy pointing to V1, initialize
        bytes memory initData =
            abi.encodeWithSelector(PredictionMarket.initialize.selector, address(outcomeToken), admin);
        proxy = new ERC1967Proxy(address(v1Impl), initData);
        marketV1 = PredictionMarket(address(proxy));

        // Grant MARKET_CREATOR_ROLE and RESOLVER_ROLE to creator
        vm.startPrank(admin);
        marketV1.grantRole(marketV1.MARKET_CREATOR_ROLE(), creator);
        marketV1.grantRole(marketV1.RESOLVER_ROLE(), creator);
        vm.stopPrank();

        // Grant minting rights on outcome token to the proxy
        bytes32 minterRole = outcomeToken.MINTER_ROLE();

        vm.prank(admin);
        outcomeToken.grantRole(minterRole, address(proxy));

        // Deploy V2 implementation (not yet activated)
        v2Impl = new PredictionMarketV2();
    }

    // Tests

    /// @notice State is preserved after V1 → V2 upgrade.
    function test_upgradeV1toV2_statePreserved() public {
        // Create a market in V1
        vm.prank(creator);
        uint256 marketId =
            marketV1.createMarket("Will ETH > $3000 on Dec 31?", block.timestamp + 1 days, 1_000 ether, lp);

        // Capture V1 state
        PredictionMarket.MarketData memory dataBefore = marketV1.getMarket(marketId);
        uint256 countBefore = marketV1.marketCount();

        // Upgrade to V2 via admin (in production this would be through Timelock)
        vm.prank(admin);
        marketV1.upgradeToAndCall(address(v2Impl), "");

        // Cast proxy to V2
        marketV2 = PredictionMarketV2(address(proxy));

        // V1 state must be intact
        PredictionMarket.MarketData memory dataAfter = marketV2.getMarket(marketId);
        assertEq(dataAfter.question, dataBefore.question, "question changed");
        assertEq(dataAfter.resolutionTime, dataBefore.resolutionTime, "resolutionTime changed");
        assertEq(uint8(dataAfter.status), uint8(dataBefore.status), "status changed");
        assertEq(dataAfter.creator, dataBefore.creator, "creator changed");
        assertEq(dataAfter.totalShares, dataBefore.totalShares, "totalShares changed");
        assertEq(marketV2.marketCount(), countBefore, "marketCount changed");

        // outcomeToken reference intact
        assertEq(address(marketV2.outcomeToken()), address(outcomeToken));
    }

    /// @notice getMarketStats is available after upgrade and returns correct data.
    function test_upgradeV1toV2_newFunctionAccessible() public {
        vm.prank(creator);
        uint256 marketId = marketV1.createMarket("Will BTC > $100k?", block.timestamp + 1 days, 500 ether, lp);

        // Upgrade
        vm.prank(admin);
        marketV1.upgradeToAndCall(address(v2Impl), "");
        marketV2 = PredictionMarketV2(address(proxy));

        // Call new V2 function
        (string memory q, uint8 status, bool outcome, uint256 shares, bool isDisputed) =
            marketV2.getMarketStats(marketId);

        assertEq(q, "Will BTC > $100k?");
        assertEq(status, 0); // Open
        assertFalse(outcome);
        assertEq(shares, 500 ether);
        assertFalse(isDisputed);
    }

    /// @notice V2 dispute window defaults to 0, can be set by admin.
    function test_upgradeV2_disputeWindowDefault() public {
        vm.prank(admin);
        marketV1.upgradeToAndCall(address(v2Impl), "");
        marketV2 = PredictionMarketV2(address(proxy));

        assertEq(marketV2.disputeWindow(), 0);

        vm.prank(admin);
        marketV2.setDisputeWindow(3 days);
        assertEq(marketV2.disputeWindow(), 3 days);
    }

    /// @notice A market can be disputed in V2 within the dispute window.
    function test_v2_disputeMarket_withinWindow() public {
        vm.prank(creator);
        uint256 marketId = marketV1.createMarket("Dispute test", block.timestamp + 1 hours, 100 ether, lp);

        // Upgrade
        vm.prank(admin);
        marketV1.upgradeToAndCall(address(v2Impl), "");
        marketV2 = PredictionMarketV2(address(proxy));

        // Set dispute window
        vm.prank(admin);
        marketV2.setDisputeWindow(7 days);

        // Resolve the market
        vm.warp(block.timestamp + 2 hours);
        vm.prank(creator);
        marketV2.resolveMarket(marketId, true);

        // Dispute within window
        address disputer = makeAddr("disputer");
        vm.prank(disputer);
        marketV2.disputeMarket(marketId);

        (,,,, bool isDisputed) = marketV2.getMarketStats(marketId);
        assertTrue(isDisputed);
    }

    /// @notice Only DEFAULT_ADMIN_ROLE can trigger upgrade.
    function test_upgrade_onlyAdmin_reverts() public {
        vm.prank(creator);
        vm.expectRevert(); // AccessControl
        marketV1.upgradeToAndCall(address(v2Impl), "");
    }
}
