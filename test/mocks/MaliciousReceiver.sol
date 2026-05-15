// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {MarketAMM} from "../../src/core/MarketAMM.sol";
import {OutcomeShareToken} from "../../src/tokens/OutcomeShareToken.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title MaliciousReceiver
// Test-only ERC-1155 receiver used to reproduce a reentrancy attempt.
//  MarketAMM.removeLiquidity() sends ERC-1155 outcome tokens back to this contract.
///      During the ERC-1155 receive hook, this contract tries to call removeLiquidity() again.
contract MaliciousReceiver is ERC165, IERC1155Receiver {
    MarketAMM public immutable amm;
    OutcomeShareToken public immutable outcomeToken;
    bool public attackEnabled;
    bool public attemptedReentry;
    uint256 public reenterLpAmount;

    constructor(MarketAMM _amm, OutcomeShareToken _outcomeToken) {
        amm = _amm;
        outcomeToken = _outcomeToken;
    }

    function approveAMM() external {
        outcomeToken.setApprovalForAll(address(amm), true);
    }

    function addLiquidity(uint256 amount) external returns (uint256 lpOut) {
        return amm.addLiquidity(amount, amount, 0);
    }

    function attack(uint256 lpAmount, uint256 _reenterLpAmount) external {
        reenterLpAmount = _reenterLpAmount;
        attackEnabled = true;
        attemptedReentry = false;

        amm.removeLiquidity(lpAmount, 0, 0);

        attackEnabled = false;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external override returns (bytes4) {
        _tryReenter();

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        override
        returns (bytes4)
    {
        _tryReenter();

        return this.onERC1155BatchReceived.selector;
    }

    function _tryReenter() internal {
        if (attackEnabled && !attemptedReentry) {
            attemptedReentry = true;

            try amm.removeLiquidity(reenterLpAmount, 0, 0) returns (
                uint256, uint256
            ) {
            // If this branch is reached on an unguarded AMM, reentrancy succeeded.
            }
            catch {
                revert("REENTRANCY_BLOCKED");
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }
}
