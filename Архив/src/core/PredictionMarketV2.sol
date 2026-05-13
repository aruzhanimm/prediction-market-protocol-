// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PredictionMarket} from "./PredictionMarket.sol";

contract PredictionMarketV2 is PredictionMarket {
    uint256 public disputeWindow; // slot 5

    mapping(uint256 => bool) public disputed; // slot 6
    event DisputeWindowUpdated(uint256 newWindow);
    event MarketDisputed(uint256 indexed marketId, address indexed disputer);
    error DisputeWindowClosed(uint256 marketId);
    error AlreadyDisputed(uint256 marketId);
    error MarketNotResolved(uint256 marketId);

    function getMarketStats(uint256 marketId)
        external
        view
        returns (string memory question, uint8 status, bool outcome, uint256 totalShares, bool isDisputed)
    {
        MarketData storage m = markets[marketId];
        return (m.question, uint8(m.status), m.outcome, m.totalShares, disputed[marketId]);
    }

    /// @notice Set the dispute window duration.
    /// @dev Only DEFAULT_ADMIN_ROLE (Timelock) can call this.
    function setDisputeWindow(uint256 newWindow) external onlyRole(DEFAULT_ADMIN_ROLE) {
        disputeWindow = newWindow;
        emit DisputeWindowUpdated(newWindow);
    }

    /// @notice File a dispute against a resolved market within the dispute window.
    /// @dev Any address can call this during the dispute window.
    ///      Actual dispute resolution logic is governance-gated and out of scope for V2.
    function disputeMarket(uint256 marketId) external {
        MarketData storage m = markets[marketId];

        if (m.resolutionTime == 0) revert MarketDoesNotExist(marketId);
        if (m.status != MarketStatus.Resolved) revert MarketNotResolved(marketId);
        if (disputed[marketId]) revert AlreadyDisputed(marketId);

        // Dispute must be filed within disputeWindow seconds of resolution.
        // resolutionTime is used as the proxy for when resolution happened.
        if (disputeWindow > 0 && block.timestamp > m.resolutionTime + disputeWindow) {
            revert DisputeWindowClosed(marketId);
        }

        disputed[marketId] = true;
        emit MarketDisputed(marketId, msg.sender);
    }
}
