// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
/// @notice Interface for the ERC-4626 fee vault that holds MarketAMM LP tokens.
interface IFeeVault is IERC4626 {
    event Harvested(address indexed caller, uint256 yieldAmount);
    /// @notice Simulates yield by transferring additional LP tokens into the vault.
    function harvest(uint256 yieldAmount) external;
    /// @notice Total simulated yield added via harvest().
    function totalYieldAccrued() external view returns (uint256);
}
