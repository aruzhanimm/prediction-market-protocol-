// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPredictionMarket
/// @notice Interface for the upgradeable PredictionMarket core contract.
interface IPredictionMarket {
    enum MarketStatus {
        Open,
        Resolved,
        Cancelled
    }

    struct MarketData {
        uint256 marketId;
        string question;
        uint256 resolutionTime;
        MarketStatus status;
        bool outcome;
        address creator;
        uint256 totalShares;
    }

    event MarketCreated(uint256 indexed marketId, address indexed creator, string question, uint256 resolutionTime);
    event MarketResolved(uint256 indexed marketId, bool outcome);
    event MarketCancelled(uint256 indexed marketId);
    event SharesRedeemed(uint256 indexed marketId, address indexed redeemer, uint256 sharesBurned, uint256 payout);

    function createMarket(
        string calldata question,
        uint256 resolutionTime,
        uint256 initialShares,
        address liquidityProvider
    ) external returns (uint256 marketId);

    function resolveMarket(uint256 marketId, bool _outcome) external;

    function cancelMarket(uint256 marketId) external;

    function redeemShares(uint256 marketId) external;

    function getMarket(uint256 marketId) external view returns (MarketData memory);

    function isOpen(uint256 marketId) external view returns (bool);

    function marketCount() external view returns (uint256);

    function setResolver(address _resolver) external;

    function setFactory(address _factory) external;
}
