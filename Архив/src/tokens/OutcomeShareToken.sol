// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract OutcomeShareToken is ERC1155, AccessControl {
    using Strings for uint256;
    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    // State
    /// @notice Human-readable name (for front-ends / block explorers).
    string public name = "Prediction Market Outcome Shares";
    /// @notice Base URI for metadata; token ID is appended as a path segment.
    string private _baseUri;

    constructor(string memory baseUri, address admin) ERC1155(baseUri) {
        require(admin != address(0), "OST: zero admin");
        _baseUri = baseUri;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    // Token-ID helpers (pure, gas-free)
    /// @notice Returns the YES token ID for a given market.
    function yesTokenId(uint256 marketId) public pure returns (uint256) {
        return marketId * 2;
    }

    /// @notice Returns the NO token ID for a given market.
    function noTokenId(uint256 marketId) public pure returns (uint256) {
        return marketId * 2 + 1;
    }

    // Mint / burn
    function mintOutcomes(uint256 marketId, address recipient, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(recipient != address(0), "OST: zero recipient");
        require(amount > 0, "OST: zero amount");

        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);

        ids[0] = yesTokenId(marketId);
        ids[1] = noTokenId(marketId);
        amounts[0] = amount;
        amounts[1] = amount;

        _mintBatch(recipient, ids, amounts, "");
    }

    function burnOutcomes(uint256 marketId, address holder, uint256 yesAmount, uint256 noAmount)
        external
        onlyRole(MINTER_ROLE)
    {
        require(holder != address(0), "OST: zero holder");
        if (yesAmount > 0) {
            _burn(holder, yesTokenId(marketId), yesAmount);
        }
        if (noAmount > 0) {
            _burn(holder, noTokenId(marketId), noAmount);
        }
    }

    // Metadata
    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(_baseUri, tokenId.toString(), ".json"));
    }

    function setBaseUri(string calldata newBaseUri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseUri = newBaseUri;
        _setURI(newBaseUri); // keep parent state in sync
    }

    /// @dev ERC1155 and AccessControl both implement supportsInterface.
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
