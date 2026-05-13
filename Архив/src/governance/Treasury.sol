// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Treasury is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER_ROLE");
    event ETHDeposited(address indexed from, uint256 amount);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientETH(uint256 requested, uint256 available);
    error ETHTransferFailed();

    constructor(address timelockAddress) {
        if (timelockAddress == address(0)) revert ZeroAddress();

        // Timelock is the sole admin — no EOA backdoor.
        _grantRole(DEFAULT_ADMIN_ROLE, timelockAddress);
        _grantRole(SPENDER_ROLE, timelockAddress);
    }

    receive() external payable {
        emit ETHDeposited(msg.sender, msg.value);
    }

    fallback() external payable {
        emit ETHDeposited(msg.sender, msg.value);
    }

    function withdrawETH(address to, uint256 amount) external onlyRole(SPENDER_ROLE) nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 bal = address(this).balance;
        if (amount > bal) revert InsufficientETH(amount, bal);
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert ETHTransferFailed();
        emit ETHWithdrawn(to, amount);
    }

    function withdrawERC20(address token, address to, uint256 amount) external onlyRole(SPENDER_ROLE) nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Withdrawn(token, to, amount);
    }

    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function erc20Balance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}

// only for me
