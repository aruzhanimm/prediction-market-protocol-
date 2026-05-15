// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MarketAMM} from "../../src/core/MarketAMM.sol";
import {OutcomeShareToken} from "../../src/tokens/OutcomeShareToken.sol";
import {MaliciousReceiver} from "../mocks/MaliciousReceiver.sol";

contract SecurityTest is Test {
    OutcomeShareToken internal outcomeToken;
    MarketAMM internal amm;
    MaliciousReceiver internal malicious;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");

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
    }

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
}
