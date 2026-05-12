// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IMarketAMM
/// @notice Interface for the per-market constant-product AMM.
interface IMarketAMM {
    event LiquidityAdded(address indexed provider, uint256 yesAmount, uint256 noAmount, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 yesAmount, uint256 noAmount, uint256 lpBurned);
    event Swap(address indexed trader, bool buyYes, uint256 amountIn, uint256 amountOut);

    function addLiquidity(uint256 yesAmount, uint256 noAmount, uint256 minLPOut) external returns (uint256 lpMinted);

    function removeLiquidity(uint256 lpAmount, uint256 minYesOut, uint256 minNoOut)
        external
        returns (uint256 yesOut, uint256 noOut);

    function swap(bool buyYes, uint256 amountIn, uint256 minAmountOut) external returns (uint256 amountOut);

    function getAmountOut(bool buyYes, uint256 amountIn) external view returns (uint256 amountOut);

    function getReserves() external view returns (uint256 reserveYes, uint256 reserveNo, uint256 k);

    function outcomeToken() external view returns (address);

    function marketId() external view returns (uint256);

    function reserveYes() external view returns (uint256);

    function reserveNo() external view returns (uint256);
}
