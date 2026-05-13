// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @dev Minimal interface for the ERC-1155 outcome-share token.
///      Keeps PredictionMarket decoupled from the full token implementation.
interface IOutcomeShareToken {
    function mintOutcomes(uint256 marketId, address recipient, uint256 amount) external;
    function burnOutcomes(uint256 marketId, address holder, uint256 yesAmount, uint256 noAmount) external;
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function yesTokenId(uint256 marketId) external pure returns (uint256);
    function noTokenId(uint256 marketId) external pure returns (uint256);
}

/// @title PredictionMarket V1
/// @notice Upgradeable core contract for creating, resolving, cancelling, and redeeming binary prediction markets.
/// @dev UUPS implementation. Storage variables must remain append-only in future versions.
///
/// Role model:
/// - DEFAULT_ADMIN_ROLE: protocol admin, expected to be held by Timelock or DAO.
/// - MARKET_CREATOR_ROLE: allowed to create and cancel markets.
/// - RESOLVER_ROLE: allowed to resolve markets, expected to be assigned to an oracle/resolver contract.
///
/// Storage layout note:
/// This is V1 storage. Any V2 implementation must append new variables after the existing state
/// to avoid proxy storage collisions. Full layout is documented in docs/storage-layout.md.
contract PredictionMarket is Initializable, AccessControl, ReentrancyGuard, UUPSUpgradeable {
    bytes32 public constant MARKET_CREATOR_ROLE = keccak256("MARKET_CREATOR_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

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
        /// @notice Timestamp when resolveMarket() was actually called. 0 if not yet resolved.
        uint256 resolvedAt;
    }

    /// @notice Sequential counter used as the next market ID.
    uint256 public marketCount;

    /// @notice Stores market lifecycle data by market ID.
    mapping(uint256 => MarketData) public markets;

    /// @notice Shared ERC-1155 contract that mints and burns YES/NO outcome shares.
    IOutcomeShareToken public outcomeToken;

    /// @notice Optional factory address connected to this market core.
    address public factory;

    /// @notice Resolver address allowed to finalize outcomes.
    address public resolver;

    event MarketCreated(uint256 indexed marketId, address indexed creator, string question, uint256 resolutionTime);
    event MarketResolved(uint256 indexed marketId, bool outcome);
    event MarketCancelled(uint256 indexed marketId);
    event SharesRedeemed(uint256 indexed marketId, address indexed redeemer, uint256 sharesBurned, uint256 payout);

    error MarketDoesNotExist(uint256 marketId);
    error MarketNotOpen(uint256 marketId);
    error MarketNotResolved(uint256 marketId);
    error ResolutionTooEarly(uint256 marketId, uint256 resolutionTime);
    error ZeroAddress();
    error ZeroShares();
    error InvalidResolutionTime();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the proxy instance.
    /// @dev Replaces constructor logic for the UUPS proxy deployment.
    /// @param _outcomeToken Address of the ERC-1155 outcome-share token.
    /// @param _admin Address receiving DEFAULT_ADMIN_ROLE and initial protocol roles.
    function initialize(address _outcomeToken, address _admin) external initializer {
        if (_outcomeToken == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MARKET_CREATOR_ROLE, _admin);
        _grantRole(RESOLVER_ROLE, _admin);

        outcomeToken = IOutcomeShareToken(_outcomeToken);
    }

    /// @notice Creates a new binary prediction market.
    /// @dev Mints equal YES and NO outcome shares to the initial liquidity provider.
    ///      Only MARKET_CREATOR_ROLE can create markets.
    /// @param question Market question shown to users.
    /// @param resolutionTime Timestamp after which the market can be resolved.
    /// @param initialShares Initial amount of YES and NO shares to mint.
    /// @param liquidityProvider Address receiving the initial outcome shares.
    /// @return marketId ID of the newly created market.
    function createMarket(
        string calldata question,
        uint256 resolutionTime,
        uint256 initialShares,
        address liquidityProvider
    ) external onlyRole(MARKET_CREATOR_ROLE) nonReentrant returns (uint256 marketId) {
        if (resolutionTime <= block.timestamp) revert InvalidResolutionTime();
        if (initialShares == 0) revert ZeroShares();
        if (liquidityProvider == address(0)) revert ZeroAddress();

        marketId = marketCount++;

        markets[marketId] = MarketData({
            marketId: marketId,
            question: question,
            resolutionTime: resolutionTime,
            status: MarketStatus.Open,
            outcome: false,
            creator: msg.sender,
            totalShares: initialShares
        });

        outcomeToken.mintOutcomes(marketId, liquidityProvider, initialShares);

        emit MarketCreated(marketId, msg.sender, question, resolutionTime);
    }

    /// @notice Resolves an open market with the final YES/NO outcome.
    /// @dev Only RESOLVER_ROLE can resolve markets, and only after resolutionTime.
    ///      In the full protocol, this role should be assigned to a Chainlink resolver or dispute module.
    function resolveMarket(uint256 marketId, bool _outcome) external onlyRole(RESOLVER_ROLE) nonReentrant {
        MarketData storage market = _requireOpen(marketId);

        if (block.timestamp < market.resolutionTime) {
            revert ResolutionTooEarly(marketId, market.resolutionTime);
        }

        market.status = MarketStatus.Resolved;
        market.outcome = _outcome;
        market.resolvedAt = block.timestamp;

        emit MarketResolved(marketId, _outcome);
    }

    /// @notice Cancels an open market.
    /// @dev Only MARKET_CREATOR_ROLE can cancel markets in V1.
    ///      A later version can move this power fully behind governance dispute resolution.
    function cancelMarket(uint256 marketId) external onlyRole(MARKET_CREATOR_ROLE) {
        MarketData storage market = _requireOpen(marketId);

        market.status = MarketStatus.Cancelled;

        emit MarketCancelled(marketId);
    }

    /// @notice Redeems winning outcome shares after market resolution.
    /// @dev V1 burns winning shares and emits a payout accounting event.
    ///      Actual collateral transfer can be added in V2 without changing the existing storage order.
    function redeemShares(uint256 marketId) external nonReentrant {
        MarketData storage market = markets[marketId];

        if (market.resolutionTime == 0) revert MarketDoesNotExist(marketId);
        if (market.status != MarketStatus.Resolved) revert MarketNotResolved(marketId);

        bool winnerIsYes = market.outcome;
        uint256 winningTokenId = winnerIsYes ? outcomeToken.yesTokenId(marketId) : outcomeToken.noTokenId(marketId);
        uint256 shares = outcomeToken.balanceOf(msg.sender, winningTokenId);

        if (shares == 0) revert ZeroShares();

        if (winnerIsYes) {
            outcomeToken.burnOutcomes(marketId, msg.sender, shares, 0);
        } else {
            outcomeToken.burnOutcomes(marketId, msg.sender, 0, shares);
        }

        emit SharesRedeemed(marketId, msg.sender, shares, shares);
    }

    /// @notice Returns full market data for a given market ID.
    function getMarket(uint256 marketId) external view returns (MarketData memory) {
        return markets[marketId];
    }

    /// @notice Returns true if the market exists and is currently open.
    function isOpen(uint256 marketId) external view returns (bool) {
        return markets[marketId].status == MarketStatus.Open && markets[marketId].resolutionTime > 0;
    }

    /// @notice Updates the resolver address and grants it RESOLVER_ROLE.
    /// @dev Only DEFAULT_ADMIN_ROLE can update resolver permissions.
    ///      The previous resolver role is revoked to avoid stale oracle permissions.
    function setResolver(address _resolver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_resolver == address(0)) revert ZeroAddress();

        if (resolver != address(0)) {
            _revokeRole(RESOLVER_ROLE, resolver);
        }

        resolver = _resolver;
        _grantRole(RESOLVER_ROLE, _resolver);
    }

    /// @notice Sets the factory address associated with this prediction market core.
    /// @dev Kept separate from initialize() so the factory can be wired after deployment.
    function setFactory(address _factory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_factory == address(0)) revert ZeroAddress();

        factory = _factory;
    }

    /// @dev UUPS upgrade authorization hook.
    ///      Only DEFAULT_ADMIN_ROLE should authorize upgrades, ideally through Timelock governance.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @dev Loads an existing open market or reverts with a specific custom error.
    function _requireOpen(uint256 marketId) internal view returns (MarketData storage market) {
        market = markets[marketId];

        if (market.resolutionTime == 0) revert MarketDoesNotExist(marketId);
        if (market.status != MarketStatus.Open) revert MarketNotOpen(marketId);
    }
}
