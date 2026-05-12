// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Market} from "./Market.sol";

contract MarketFactory is AccessControl {
    bytes32 public constant MARKET_CREATOR_ROLE = keccak256("MARKET_CREATOR_ROLE");
    // notice Sequential counter — also used as the next market ID.
    uint256 public marketCount;
    // notice marketId → deployed market address.
    mapping(uint256 => address) public markets;
    // notice Ordered list of all deployed market addresses.
    address[] public allMarkets;
    // notice Tracks which CREATE2 salts have already been used to prevent collisions.
    mapping(bytes32 => bool) public usedSalts;
    // notice Address of the shared ERC-1155 outcome-share token contract.
    address public immutable outcomeShareToken;
    event MarketDeployed(
        uint256 indexed marketId,
        address indexed marketAddress,
        address indexed creator,
        string question,
        uint256 resolutionTime,
        bool usedCreate2,
        bytes32 salt
    );

    constructor(address _outcomeShareToken, address admin) {
        require(_outcomeShareToken != address(0), "MF: zero outcome token");
        require(admin != address(0), "MF: zero admin");
        outcomeShareToken = _outcomeShareToken;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MARKET_CREATOR_ROLE, admin);
    }

    // Deployment — CREATE (address non-deterministic)
    function deployMarketDefault(string calldata question, uint256 resolutionTime)
        external
        onlyRole(MARKET_CREATOR_ROLE)
        returns (uint256 marketId, address marketAddr)
    {
        marketId = marketCount++;
        // CREATE: address = keccak256(rlp(sender, nonce))
        Market market = new Market(marketId, question, resolutionTime, outcomeShareToken, msg.sender);
        marketAddr = address(market);
        _register(marketId, marketAddr, question, resolutionTime, false, bytes32(0));
    }

    // Deployment — CREATE2 (address deterministic)
    function deployMarket(bytes32 salt, string calldata question, uint256 resolutionTime)
        external
        onlyRole(MARKET_CREATOR_ROLE)
        returns (uint256 marketId, address marketAddr)
    {
        require(!usedSalts[salt], "MF: salt already used");
        usedSalts[salt] = true;
        marketId = marketCount++;
        // CREATE2: address = keccak256(0xff ++ factory ++ salt ++ keccak256(initcode))
        Market market = new Market{salt: salt}(marketId, question, resolutionTime, outcomeShareToken, msg.sender);
        marketAddr = address(market);
        _register(marketId, marketAddr, question, resolutionTime, true, salt);
    }

    // Address prediction (off-chain / test helper)
    function predictCreate2Address(
        bytes32 salt,
        uint256 marketId,
        string calldata question,
        uint256 resolutionTime,
        address creator
    ) external view returns (address predicted) {
        bytes memory initCode = abi.encodePacked(
            type(Market).creationCode, abi.encode(marketId, question, resolutionTime, outcomeShareToken, creator)
        );
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(initCode)));
        predicted = address(uint160(uint256(hash)));
    }

    // Returns the total number of deployed markets.
    function totalMarkets() external view returns (uint256) {
        return allMarkets.length;
    }

    // Returns all deployed market addresses.
    function getAllMarkets() external view returns (address[] memory) {
        return allMarkets;
    }

    function _register(
        uint256 marketId,
        address marketAddr,
        string calldata question,
        uint256 resolutionTime,
        bool usedCreate2,
        bytes32 salt
    ) internal {
        markets[marketId] = marketAddr;
        allMarkets.push(marketAddr);
        emit MarketDeployed(marketId, marketAddr, msg.sender, question, resolutionTime, usedCreate2, salt);
    }
}
