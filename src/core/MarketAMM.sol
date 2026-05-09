// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AMMLib} from "../libraries/AMMLib.sol";

/// @title MarketAMM
/// @notice Per-market constant-product AMM (x * y = k) that trades YES/NO
///         outcome-share tokens (ERC-1155).  LP providers receive ERC-20 LP
///         tokens proportional to their share of the pool.
/// Design decisions:
///   • x = reserveYes,  y = reserveNo,  k = x * y
///   • 0.3 % swap fee: amountIn is reduced by 0.3 % before applying CPMM formula.
///     This causes k to increase after each swap, passively rewarding LPs.
///   • Minimum liquidity (MINIMUM_LIQUIDITY = 1000) is burned to address(1) on
///     first provision, preventing inflation attacks.
///   • AMMLib.sqrt() (Yul assembly) is used for initial LP computation.
///   • Slippage protection: all mutating functions accept a minimum-output param.
contract MarketAMM is ERC20, ReentrancyGuard {
    using AMMLib for uint256;

    // Constants
    uint256 public constant FEE_NUMERATOR = 997; // 0.3 % fee → use 99.7 % of input
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 public constant MINIMUM_LIQUIDITY = 1_000; // burned forever on first add

    //  Immutable state
    /// @notice The shared ERC-1155 outcome-share token contract.
    IERC1155 public immutable outcomeToken;
    /// @notice The market this AMM belongs to.
    uint256 public immutable marketId;
    /// @notice YES token ID = marketId * 2
    uint256 public immutable yesTokenId;
    /// @notice NO token ID = marketId * 2 + 1
    uint256 public immutable noTokenId;

    // Mutable reserves
    /// @notice Current YES token reserve held by the AMM.
    uint256 public reserveYes;
    /// @notice Current NO token reserve held by the AMM.
    uint256 public reserveNo;

    //  Events
    event LiquidityAdded(address indexed provider, uint256 yesAmount, uint256 noAmount, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 yesAmount, uint256 noAmount, uint256 lpBurned);
    event Swap(address indexed trader, bool buyYes, uint256 amountIn, uint256 amountOut);

    // Errors
    error InsufficientOutput(uint256 amountOut, uint256 minimum);
    error InsufficientLiquidity();
    error ZeroAmount();
    error ZeroAddress();

    // Constructor
    /// @param _outcomeToken   Address of the ERC-1155 OutcomeShareToken contract.
    /// @param _marketId       ID of the prediction market.
    constructor(address _outcomeToken, uint256 _marketId)
        ERC20(
            string(abi.encodePacked("MarketAMM-LP-", _uint2str(_marketId))),
            string(abi.encodePacked("LP-", _uint2str(_marketId)))
        )
    {
        if (_outcomeToken == address(0)) revert ZeroAddress();
        outcomeToken = IERC1155(_outcomeToken);
        marketId = _marketId;
        yesTokenId = _marketId * 2;
        noTokenId = _marketId * 2 + 1;
    }

    // Liquidity
    /// @notice Add liquidity to the pool.  On the first call the pool is
    ///         initialised; subsequent calls must deposit proportionally.
    /// @dev    Caller must call outcomeToken.setApprovalForAll(address(this), true)
    ///         before calling this function.
    /// @param yesAmount  YES tokens to deposit.
    /// @param noAmount   NO tokens to deposit.
    /// @param minLPOut   Minimum LP tokens to receive (slippage protection).
    /// @return lpMinted  LP tokens minted to the caller.
    function addLiquidity(uint256 yesAmount, uint256 noAmount, uint256 minLPOut)
        external
        nonReentrant
        returns (uint256 lpMinted)
    {
        if (yesAmount == 0 || noAmount == 0) revert ZeroAmount();

        uint256 _reserveYes = reserveYes;
        uint256 _reserveNo = reserveNo;
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            // First liquidity provision
            // Geometric mean of deposits → initial LP shares.
            // Uses AMMLib.sqrt (Yul assembly).
            uint256 liquidity = AMMLib.sqrt(yesAmount * noAmount);
            if (liquidity <= MINIMUM_LIQUIDITY) revert InsufficientLiquidity();
            // Burn MINIMUM_LIQUIDITY to address(1) — prevents inflation attack.
            _mint(address(1), MINIMUM_LIQUIDITY);
            lpMinted = liquidity - MINIMUM_LIQUIDITY;
        } else {
            //  Subsequent provisions: proportional to current reserves
            // LP tokens received = min(yesAmount/reserveYes, noAmount/reserveNo) * totalSupply
            uint256 lpFromYes = AMMLib.mulDiv(yesAmount, _totalSupply, _reserveYes);
            uint256 lpFromNo = AMMLib.mulDiv(noAmount, _totalSupply, _reserveNo);
            lpMinted = lpFromYes < lpFromNo ? lpFromYes : lpFromNo;
        }

        if (lpMinted < minLPOut) revert InsufficientOutput(lpMinted, minLPOut);
        // Checks-Effects-Interactions
        reserveYes = _reserveYes + yesAmount;
        reserveNo = _reserveNo + noAmount;
        // Pull ERC-1155 tokens from caller
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = yesTokenId;
        ids[1] = noTokenId;
        amounts[0] = yesAmount;
        amounts[1] = noAmount;
        outcomeToken.safeBatchTransferFrom(msg.sender, address(this), ids, amounts, "");
        _mint(msg.sender, lpMinted);
        emit LiquidityAdded(msg.sender, yesAmount, noAmount, lpMinted);
    }

    /// @notice Remove liquidity proportionally.
    /// @param lpAmount    LP tokens to burn.
    /// @param minYesOut   Minimum YES tokens to receive (slippage protection).
    /// @param minNoOut    Minimum NO tokens to receive (slippage protection).
    /// @return yesOut     YES tokens returned.
    /// @return noOut      NO tokens returned.
    function removeLiquidity(uint256 lpAmount, uint256 minYesOut, uint256 minNoOut)
        external
        nonReentrant
        returns (uint256 yesOut, uint256 noOut)
    {
        if (lpAmount == 0) revert ZeroAmount();
        uint256 _totalSupply = totalSupply();
        uint256 _reserveYes = reserveYes;
        uint256 _reserveNo = reserveNo;
        // Proportional share of reserves
        yesOut = AMMLib.mulDiv(lpAmount, _reserveYes, _totalSupply);
        noOut = AMMLib.mulDiv(lpAmount, _reserveNo, _totalSupply);
        if (yesOut < minYesOut) revert InsufficientOutput(yesOut, minYesOut);
        if (noOut < minNoOut) revert InsufficientOutput(noOut, minNoOut);
        // Checks-Effects-Interactions
        reserveYes = _reserveYes - yesOut;
        reserveNo = _reserveNo - noOut;
        _burn(msg.sender, lpAmount);
        // Push ERC-1155 tokens to caller
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = yesTokenId;
        ids[1] = noTokenId;
        amounts[0] = yesOut;
        amounts[1] = noOut;
        outcomeToken.safeBatchTransferFrom(address(this), msg.sender, ids, amounts, "");
        emit LiquidityRemoved(msg.sender, yesOut, noOut, lpAmount);
    }

    // Swap
    /// @notice Swap YES for NO or NO for YES using CPMM with 0.3% fee.
    /// @param buyYes       If true, user provides NO tokens and receives YES.
    ///                     If false, user provides YES tokens and receives NO.
    /// @param amountIn     Amount of input tokens (before fee).
    /// @param minAmountOut Minimum output tokens (slippage protection).
    /// @return amountOut   Actual output tokens received.
    function swap(bool buyYes, uint256 amountIn, uint256 minAmountOut)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert ZeroAmount();
        amountOut = getAmountOut(buyYes, amountIn);
        if (amountOut < minAmountOut) revert InsufficientOutput(amountOut, minAmountOut);
        uint256 _reserveYes = reserveYes;
        uint256 _reserveNo = reserveNo;

        if (buyYes) {
            // User provides NO, receives YES
            if (amountOut >= _reserveYes) revert InsufficientLiquidity();
            // Checks-Effects-Interactions
            reserveYes = _reserveYes - amountOut;
            reserveNo = _reserveNo + amountIn;
            // Pull NO tokens from caller
            outcomeToken.safeTransferFrom(msg.sender, address(this), noTokenId, amountIn, "");
            // Push YES tokens to caller
            outcomeToken.safeTransferFrom(address(this), msg.sender, yesTokenId, amountOut, "");
        } else {
            // User provides YES, receives NO
            if (amountOut >= _reserveNo) revert InsufficientLiquidity();
            // Checks-Effects-Interactions
            reserveYes = _reserveYes + amountIn;
            reserveNo = _reserveNo - amountOut;
            // Pull YES tokens from caller
            outcomeToken.safeTransferFrom(msg.sender, address(this), yesTokenId, amountIn, "");
            // Push NO tokens to caller
            outcomeToken.safeTransferFrom(address(this), msg.sender, noTokenId, amountOut, "");
        }
        emit Swap(msg.sender, buyYes, amountIn, amountOut);
    }

    // View helpers
    /// @notice Compute output amount for a given input, applying 0.3% fee.
    /// @dev    CPMM formula with fee:
    ///           amountInWithFee = amountIn * 997
    ///           amountOut = (amountInWithFee * reserveOut) /
    ///                       (reserveIn * 1000 + amountInWithFee)
    ///         This is the standard Uniswap V2 formula.
    /// @param buyYes   Direction of swap (true = spend NO, receive YES).
    /// @param amountIn Input token amount (before fee deduction).
    /// @return amountOut Output token amount after 0.3% fee.
    function getAmountOut(bool buyYes, uint256 amountIn) public view returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        uint256 reserveIn = buyYes ? reserveNo : reserveYes;
        uint256 reserveOut = buyYes ? reserveYes : reserveNo;
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        // Apply 0.3% fee: multiply input by 997/1000
        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Returns current reserves and k value.
    function getReserves() external view returns (uint256 _reserveYes, uint256 _reserveNo, uint256 k) {
        _reserveYes = reserveYes;
        _reserveNo = reserveNo;
        k = _reserveYes * _reserveNo;
    }

    // ERC-1155 receiver
    /// @notice Required by ERC-1155 safe transfer protocol.
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /// @notice Required by ERC-1155 safe batch transfer protocol.
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    //  Internal helpers
    /// @dev uint → decimal string (used in constructor for LP token name/symbol).
    function _uint2str(uint256 n) private pure returns (string memory) {
        if (n == 0) return "0";
        uint256 j = n;
        uint256 len;
        while (j != 0) len++;
        j /= 10;
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (n != 0) k--;
        bstr[k] = bytes1(uint8(48 + n % 10));
        n /= 10;
        return string(bstr);
    }
}
