// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal Chainlink AggregatorV3 interface.
interface IAggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

// Test-only implementation of AggregatorV3Interface.
// Allows arbitrary price and updatedAt values to be set for unit and fuzz tests.
// NOT intended for production  no access control on setters by design,
// as tests deploy fresh instances and control them directly.
contract MockAggregator is IAggregatorV3Interface {
    uint8 private _decimals;
    int256 private _answer;
    uint256 private _updatedAt;
    uint80 private _roundId;

    constructor(uint8 decimals_, int256 initialAnswer) {
        _decimals = decimals_;
        _answer = initialAnswer;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }

    /// @notice Update the mock price and bump the round ID.
    function setPrice(int256 newAnswer) external {
        _answer = newAnswer;
        _updatedAt = block.timestamp;
        _roundId++;
    }

    /// @notice Manually override updatedAt (for staleness tests).
    function setUpdatedAt(uint256 ts) external {
        _updatedAt = ts;
    }

    /// @notice Set both price and timestamp atomically.
    function setPriceAndTime(int256 newAnswer, uint256 ts) external {
        _answer = newAnswer;
        _updatedAt = ts;
        _roundId++;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock Aggregator";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _roundId);
    }

    function getRoundData(
        uint80 /* _roundId */
    )
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // Simplified: always returns latest round data for mock purposes.
        return (_roundId, _answer, _updatedAt, _updatedAt, _roundId);
    }
}
