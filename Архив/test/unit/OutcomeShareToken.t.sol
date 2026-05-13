// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test} from "forge-std/Test.sol";
import {OutcomeShareToken} from "../../src/tokens/OutcomeShareToken.sol";

contract OutcomeShareTokenTest is Test {
    bytes4 internal constant ERC1155_INTERFACE_ID = 0xd9b67a26;
    bytes4 internal constant ACCESS_CONTROL_IFACE_ID = 0x7965db0b;
    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");

    OutcomeShareToken internal token;

    function setUp() public {
        token = new OutcomeShareToken("https://api.example.com/tokens/", admin);
        // Grant MINTER_ROLE to minter address.
        // NOTE: cache the role constant BEFORE vm.prank — vm.prank applies to
        // the very next external call, and token.MINTER_ROLE() would consume it
        // before token.grantRole() is reached, leaving grantRole called from
        // the default test sender (which has no DEFAULT_ADMIN_ROLE).
        bytes32 minterRole = token.MINTER_ROLE();
        vm.prank(admin);
        token.grantRole(minterRole, minter);
    }

    // Test 1 — Token ID helpers
    function test_tokenIdHelpers() public view {
        // market 0: YES = 0, NO = 1
        assertEq(token.yesTokenId(0), 0, "market 0 YES");
        assertEq(token.noTokenId(0), 1, "market 0 NO");
        // market 5: YES = 10, NO = 11
        assertEq(token.yesTokenId(5), 10, "market 5 YES");
        assertEq(token.noTokenId(5), 11, "market 5 NO");
    }

    // Helper: call yesTokenId/noTokenId on the deployed instance (avoids address(0))
    function _yes(uint256 mid) internal view returns (uint256) {
        return token.yesTokenId(mid);
    }

    function _no(uint256 mid) internal view returns (uint256) {
        return token.noTokenId(mid);
    }

    // Test 2 — mintOutcomes mints equal YES and NO balances
    function test_mintOutcomes_balances() public {
        uint256 mid = 3;
        uint256 amount = 100 ether;
        vm.prank(minter);
        token.mintOutcomes(mid, alice, amount);
        assertEq(token.balanceOf(alice, _yes(mid)), amount, "YES balance");
        assertEq(token.balanceOf(alice, _no(mid)), amount, "NO balance");
    }

    // Test 3 — mintOutcomes reverts without MINTER_ROLE
    function test_mintOutcomes_reverts_noRole() public {
        vm.prank(charlie); // charlie has no MINTER_ROLE
        vm.expectRevert();
        token.mintOutcomes(0, alice, 1 ether);
    }

    // Test 4 — mintOutcomes reverts on zero recipient
    function test_mintOutcomes_reverts_zeroRecipient() public {
        vm.prank(minter);
        vm.expectRevert(bytes("OST: zero recipient"));
        token.mintOutcomes(0, address(0), 1 ether);
    }

    // Test 5 — mintOutcomes reverts on zero amount
    function test_mintOutcomes_reverts_zeroAmount() public {
        vm.prank(minter);
        vm.expectRevert(bytes("OST: zero amount"));
        token.mintOutcomes(0, alice, 0);
    }

    // Test 6 — burnOutcomes removes YES tokens
    function test_burnOutcomes_yes() public {
        uint256 mid = 1;
        uint256 amount = 50 ether;
        vm.prank(minter);
        token.mintOutcomes(mid, alice, amount);
        vm.prank(minter);
        token.burnOutcomes(mid, alice, amount, 0); // burn all YES, no NO
        assertEq(token.balanceOf(alice, _yes(mid)), 0, "YES should be 0 after burn");
        assertEq(token.balanceOf(alice, _no(mid)), amount, "NO should be unchanged");
    }

    // Test 7 — burnOutcomes removes NO tokens
    function test_burnOutcomes_no() public {
        uint256 mid = 2;
        uint256 amount = 75 ether;
        vm.prank(minter);
        token.mintOutcomes(mid, alice, amount);
        vm.prank(minter);
        token.burnOutcomes(mid, alice, 0, amount); // burn all NO, no YES
        assertEq(token.balanceOf(alice, _yes(mid)), amount, "YES should be unchanged");
        assertEq(token.balanceOf(alice, _no(mid)), 0, "NO should be 0 after burn");
    }

    // Test 8 — burnOutcomes reverts without MINTER_ROLE
    function test_burnOutcomes_reverts_noRole() public {
        vm.prank(minter);
        token.mintOutcomes(0, alice, 10 ether);
        vm.prank(charlie); // no MINTER_ROLE
        vm.expectRevert();
        token.burnOutcomes(0, alice, 10 ether, 0);
    }

    // Test 9 — uri() returns expected URL
    function test_uri_format() public view {
        // tokenId 6 = market 3 YES
        string memory expected = "https://api.example.com/tokens/6.json";
        assertEq(token.uri(6), expected, "URI mismatch");
    }

    // Test 10 — safeBatchTransferFrom
    function test_safeBatchTransferFrom() public {
        uint256 mid = 4;
        vm.prank(minter);
        token.mintOutcomes(mid, alice, 200 ether);
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = _yes(mid);
        ids[1] = _no(mid);
        amounts[0] = 100 ether;
        amounts[1] = 100 ether;
        vm.prank(alice);
        token.safeBatchTransferFrom(alice, bob, ids, amounts, "");
        assertEq(token.balanceOf(bob, _yes(mid)), 100 ether, "bob YES");
        assertEq(token.balanceOf(bob, _no(mid)), 100 ether, "bob NO");
        assertEq(token.balanceOf(alice, _yes(mid)), 100 ether, "alice YES remaining");
    }

    // Test 11 — setBaseUri updates URI
    function test_setBaseUri() public {
        vm.prank(admin);
        token.setBaseUri("https://new-api.example.com/");

        assertEq(token.uri(0), "https://new-api.example.com/0.json", "new URI mismatch");
    }

    // Test 12 — setBaseUri reverts without DEFAULT_ADMIN_ROLE
    function test_setBaseUri_reverts_noRole() public {
        vm.prank(alice);
        vm.expectRevert();
        token.setBaseUri("https://malicious.example.com/");
    }

    // Test 13 — supportsInterface for ERC-1155
    function test_supportsInterface_erc1155() public view {
        assertTrue(token.supportsInterface(ERC1155_INTERFACE_ID), "should support ERC-1155");
    }

    // Test 14 — supportsInterface for AccessControl
    function test_supportsInterface_accessControl() public view {
        assertTrue(token.supportsInterface(ACCESS_CONTROL_IFACE_ID), "should support AccessControl");
    }

    // Test 15 — Admin can grant MINTER_ROLE
    function test_grantMinterRole() public {
        bytes32 minterRole = token.MINTER_ROLE();
        vm.prank(admin);
        token.grantRole(minterRole, charlie);
        // charlie can now mint
        vm.prank(charlie);
        token.mintOutcomes(99, alice, 1 ether);
        assertEq(token.balanceOf(alice, token.yesTokenId(99)), 1 ether);
    }
}
