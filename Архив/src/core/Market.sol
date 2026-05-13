// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Market {
    enum Status {
        Open,
        Resolved,
        Cancelled
    }
    uint256 public immutable marketId;
    address public immutable creator;
    uint256 public immutable resolutionTime;
    string public question;
    address public immutable outcomeToken;
    Status public status;
    bool public outcome; // true = YES, false = NO (valid only when resolved)
    event MarketResolved(uint256 indexed marketId, bool outcome);
    event MarketCancelled(uint256 indexed marketId);

    constructor(
        uint256 _marketId,
        string memory _question,
        uint256 _resolutionTime,
        address _outcomeToken,
        address _creator
    ) {
        require(_resolutionTime > block.timestamp, "Market: resolution in the past");
        require(_outcomeToken != address(0), "Market: zero outcome token");
        require(_creator != address(0), "Market: zero creator");
        marketId = _marketId;
        question = _question;
        resolutionTime = _resolutionTime;
        outcomeToken = _outcomeToken;
        creator = _creator;
        status = Status.Open;
    }

    // Resolution (stub — Week 8 wires this to ChainlinkResolver)
    // Resolves the market. Only the creator can call this stub.
    function resolve(bool _outcome) external {
        require(msg.sender == creator, "Market: not creator");
        require(status == Status.Open, "Market: not open");
        require(block.timestamp >= resolutionTime, "Market: too early");
        status = Status.Resolved;
        outcome = _outcome;
        emit MarketResolved(marketId, _outcome);
    }

    // Cancels the market. Only the creator can call this stub.
    function cancel() external {
        require(msg.sender == creator, "Market: not creator");
        require(status == Status.Open, "Market: not open");
        status = Status.Cancelled;
        emit MarketCancelled(marketId);
    }
}
