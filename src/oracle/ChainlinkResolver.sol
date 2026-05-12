// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAggregatorV3Interface} from "./MockAggregator.sol";

// Reads a Chainlink price feed and resolves binary prediction markets based on a configurable price threshold.
contract ChainlinkResolver is AccessControl {
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    IAggregatorV3Interface public immutable feed;
    uint256 public immutable stalenessThreshold;
    IMarketCore public immutable market;
    event MarketResolved(uint256 indexed marketId, bool outcome, int256 price, int256 threshold);
    error InvalidPrice(int256 price);
    error StalePrice(uint256 updatedAt, uint256 threshold);
    error InvalidRound(uint80 roundId);

    constructor(address _feed, address _market, uint256 _stalenessThreshold, address _admin) {
        require(_feed != address(0), "ChainlinkResolver: zero feed");
        require(_market != address(0), "ChainlinkResolver: zero market");
        require(_stalenessThreshold > 0, "ChainlinkResolver: zero staleness");
        require(_admin != address(0), "ChainlinkResolver: zero admin");
        feed = IAggregatorV3Interface(_feed);
        market = IMarketCore(_market);
        stalenessThreshold = _stalenessThreshold;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(RESOLVER_ROLE, _admin);
    }

    function getLatestPrice() public view returns (int256 price) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
        // Validate round completeness
        if (answeredInRound < roundId) revert InvalidRound(roundId);
        // Validate price is positive
        if (answer <= 0) revert InvalidPrice(answer);
        // Validate freshness
        if (block.timestamp - updatedAt > stalenessThreshold) {
            revert StalePrice(updatedAt, stalenessThreshold);
        }

        return answer;
    }

    function resolveMarket(uint256 marketId, int256 priceThreshold) external onlyRole(RESOLVER_ROLE) {
        int256 price = getLatestPrice();
        bool outcome = price >= priceThreshold;
        market.resolveMarket(marketId, outcome);
        emit MarketResolved(marketId, outcome, price, priceThreshold);
    }
}

interface IMarketCore {
    function resolveMarket(uint256 marketId, bool outcome) external;
}
