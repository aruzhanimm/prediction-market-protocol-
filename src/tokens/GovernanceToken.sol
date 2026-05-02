// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes {
    uint256 public constant TOTAL_SUPPLY = 100_000_000 ether;
    uint256 public constant TEAM_BPS = 4_000; // 40 %
    uint256 public constant TREASURY_BPS = 3_000; // 30 %
    uint256 public constant COMMUNITY_BPS = 2_000; // 20 %
    uint256 public constant LIQUIDITY_BPS = 1_000; // 10 %

    constructor(address teamWallet, address treasuryWallet, address communityWallet, address liquidityWallet)
        ERC20("PredictToken", "PRED")
        ERC20Permit("PredictToken")
    {
        require(teamWallet != address(0), "GT: zero team");
        require(treasuryWallet != address(0), "GT: zero treasury");
        require(communityWallet != address(0), "GT: zero community");
        require(liquidityWallet != address(0), "GT: zero liquidity");

        _mint(teamWallet, (TOTAL_SUPPLY * TEAM_BPS) / 10_000);
        _mint(treasuryWallet, (TOTAL_SUPPLY * TREASURY_BPS) / 10_000);
        _mint(communityWallet, (TOTAL_SUPPLY * COMMUNITY_BPS) / 10_000);
        _mint(liquidityWallet, (TOTAL_SUPPLY * LIQUIDITY_BPS) / 10_000);
    }

    /// @dev Called on every transfer/mint/burn; both ERC20 and ERC20Votes need it.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /// @dev ERC20Permit and Nonces both expose `nonces`; disambiguate here.
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
