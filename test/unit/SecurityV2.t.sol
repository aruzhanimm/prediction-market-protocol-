// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MarketAMM} from "../../src/core/MarketAMM.sol";
import {OutcomeShareToken} from "../../src/tokens/OutcomeShareToken.sol";
import {PredictionMarket} from "../../src/core/PredictionMarket.sol";
import {PredictionMarketV2} from "../../src/core/PredictionMarketV2.sol";
import {Treasury} from "../../src/governance/Treasury.sol";
import {MaliciousReceiver} from "../mocks/MaliciousReceiver.sol";

contract SecurityTest is Test {
    OutcomeShareToken internal outcomeToken;
    MarketAMM internal amm;
    MaliciousReceiver internal malicious;

    PredictionMarket internal v1Impl;
    PredictionMarketV2 internal v2Impl;
    ERC1967Proxy internal proxy;
    PredictionMarket internal marketV1;
    PredictionMarketV2 internal marketV2;

    Treasury internal treasury;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal creator = makeAddr("creator");
    address internal resolver = makeAddr("resolver");
    address internal attacker = makeAddr("attacker");
    address internal lp = makeAddr("lp");

    uint256 internal constant MARKET_ID = 0;
    uint256 internal constant INITIAL_LIQUIDITY = 10_000 ether;

    function setUp() public {
        outcomeToken = new OutcomeShareToken("https://api.example.com/", admin);

        bytes32 minterRole = outcomeToken.MINTER_ROLE();

        vm.prank(admin);
        outcomeToken.grantRole(minterRole, minter);

        amm = new MarketAMM(address(outcomeToken), MARKET_ID);
        malicious = new MaliciousReceiver(amm, outcomeToken);

        vm.prank(minter);
        outcomeToken.mintOutcomes(MARKET_ID, address(malicious), INITIAL_LIQUIDITY);

        malicious.approveAMM();
        malicious.addLiquidity(INITIAL_LIQUIDITY);

        v1Impl = new PredictionMarket();
        v2Impl = new PredictionMarketV2();

        bytes memory initData =
            abi.encodeWithSelector(PredictionMarket.initialize.selector, address(outcomeToken), admin);

        proxy = new ERC1967Proxy(address(v1Impl), initData);
        marketV1 = PredictionMarket(address(proxy));

        vm.startPrank(admin);
        marketV1.grantRole(marketV1.MARKET_CREATOR_ROLE(), creator);
        marketV1.grantRole(marketV1.RESOLVER_ROLE(), resolver);
        vm.stopPrank();

        vm.prank(admin);
        outcomeToken.grantRole(minterRole, address(proxy));

        treasury = new Treasury(admin);
    }

    // Case 1: Reentrancy
    function test_reentrancy_attack_fails() public {
        uint256 lpBalance = amm.balanceOf(address(malicious));

        assertGt(lpBalance, 1, "malicious receiver needs LP tokens");

        vm.expectRevert(bytes("REENTRANCY_BLOCKED"));

        malicious.attack(lpBalance / 2, 1);
    }

    function test_reentrancy_withoutGuard_wouldSucceed_documentation() public view {
        uint256 lpBalance = amm.balanceOf(address(malicious));

        assertGt(lpBalance, 1, "without guard, attacker would have LP to reenter with");
        assertEq(address(malicious.amm()), address(amm), "malicious receiver targets AMM");
        assertEq(address(malicious.outcomeToken()), address(outcomeToken), "malicious receiver targets outcome token");
    }

    // Case 2: Access Control before/after
    /// @dev Creates an open market and returns its ID and resolution time.
    function _createMarket() internal returns (uint256 marketId, uint256 resolutionTime) {
        resolutionTime = block.timestamp + 1 days;

        vm.prank(creator);
        marketId = marketV1.createMarket("Will ETH be above threshold?", resolutionTime, 1_000 ether, lp);
    }

    /// @notice Before: account without RESOLVER_ROLE cannot resolve market.
    function test_accessControl_resolveMarket_withoutRole_reverts() public {
        (uint256 marketId, uint256 resolutionTime) = _createMarket();

        vm.warp(resolutionTime + 1);

        vm.prank(attacker);
        vm.expectRevert();

        marketV1.resolveMarket(marketId, true);
    }

    /// @notice After: account with RESOLVER_ROLE can resolve market.
    function test_accessControl_resolveMarket_withRole_succeeds() public {
        (uint256 marketId, uint256 resolutionTime) = _createMarket();

        vm.warp(resolutionTime + 1);

        vm.prank(resolver);
        marketV1.resolveMarket(marketId, true);

        PredictionMarket.MarketData memory data = marketV1.getMarket(marketId);

        assertEq(uint8(data.status), uint8(PredictionMarket.MarketStatus.Resolved), "market not resolved");
        assertTrue(data.outcome, "outcome should be YES");
    }

    /// @notice Before: account without DEFAULT_ADMIN_ROLE cannot upgrade implementation.
    function test_accessControl_upgrade_withoutRole_reverts() public {
        vm.prank(attacker);
        vm.expectRevert();

        marketV1.upgradeToAndCall(address(v2Impl), "");
    }

    /// @notice After: DEFAULT_ADMIN_ROLE can authorize UUPS upgrade.
    function test_accessControl_upgrade_withRole_succeeds() public {
        vm.prank(admin);
        marketV1.upgradeToAndCall(address(v2Impl), "");

        marketV2 = PredictionMarketV2(address(proxy));

        assertEq(marketV2.disputeWindow(), 0, "V2 getter should be available after upgrade");
    }

    /// @notice Before: account without MINTER_ROLE cannot mint YES/NO outcome shares.
    function test_accessControl_mintOutcomes_withoutRole_reverts() public {
        vm.prank(attacker);
        vm.expectRevert();

        outcomeToken.mintOutcomes(MARKET_ID, attacker, 1 ether);
    }

    /// @notice Before: account without SPENDER_ROLE cannot withdraw from Treasury.
    function test_accessControl_treasury_withdraw_withoutRole_reverts() public {
        vm.deal(address(treasury), 1 ether);

        vm.prank(attacker);
        vm.expectRevert();

        treasury.withdrawETH(attacker, 1 ether);
    }
}
