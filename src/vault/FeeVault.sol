// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title FeeVault
/// @notice ERC-4626 vault that accepts MarketAMM LP tokens and issues vault shares.
/// @dev Uses virtual offset accounting to reduce first-depositor inflation risk.
///      Yield is simulated through harvest(), which transfers extra LP tokens into the vault.
contract FeeVault is ERC20, IERC4626, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice The underlying LP token accepted by this vault.
    IERC20 private immutable _asset;

    /// @notice Total simulated yield added through harvest().
    uint256 public totalYieldAccrued;

    event Harvested(address indexed caller, uint256 yieldAmount);

    /// @param asset_ Address of the LP token used as the vault asset.
    /// @param name_ ERC-20 name for vault shares.
    /// @param symbol_ ERC-20 symbol for vault shares.
    /// @param owner_ Initial owner allowed to call harvest().
    constructor(address asset_, string memory name_, string memory symbol_, address owner_)
        ERC20(name_, symbol_)
        Ownable(owner_)
    {
        require(asset_ != address(0), "FeeVault: zero asset");
        require(owner_ != address(0), "FeeVault: zero owner");

        _asset = IERC20(asset_);
    }

    /// @inheritdoc IERC4626
    function asset() public view override returns (address) {
        return address(_asset);
    }

    /// @inheritdoc IERC4626
    /// @dev Returns the amount of LP tokens currently held by the vault.
    function totalAssets() public view override returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /// @inheritdoc IERC4626
    /// @dev Rounds down in favor of the vault.
    function convertToShares(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    /// @dev Rounds down in favor of the vault.
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc IERC4626
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    /// @dev Uses Checks-Effects-Interactions and ReentrancyGuard.
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        require(assets > 0, "FeeVault: zero assets");
        require(receiver != address(0), "FeeVault: zero receiver");

        shares = previewDeposit(assets);
        require(shares > 0, "FeeVault: zero shares");

        _mint(receiver, shares);
        _asset.safeTransferFrom(msg.sender, address(this), assets);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IERC4626
    function maxMint(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc IERC4626
    /// @dev Rounds up so the caller deposits enough assets for the requested shares.
    function previewMint(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        require(shares > 0, "FeeVault: zero shares");
        require(receiver != address(0), "FeeVault: zero receiver");

        assets = previewMint(shares);

        _mint(receiver, shares);
        _asset.safeTransferFrom(msg.sender, address(this), assets);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address owner_) public view override returns (uint256) {
        return convertToAssets(balanceOf(owner_));
    }

    /// @inheritdoc IERC4626
    /// @dev Rounds up so the caller burns enough shares for the requested assets.
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 assets, address receiver, address owner_)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        require(assets > 0, "FeeVault: zero assets");
        require(receiver != address(0), "FeeVault: zero receiver");

        shares = previewWithdraw(assets);

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }

        _burn(owner_, shares);
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address owner_) public view override returns (uint256) {
        return balanceOf(owner_);
    }

    /// @inheritdoc IERC4626
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    function redeem(uint256 shares, address receiver, address owner_)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        require(shares > 0, "FeeVault: zero shares");
        require(receiver != address(0), "FeeVault: zero receiver");

        assets = previewRedeem(shares);
        require(assets > 0, "FeeVault: zero assets");

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }

        _burn(owner_, shares);
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    /// @notice Simulates LP yield by transferring additional LP tokens into the vault.
    /// @dev In production, this role would usually belong to a keeper, fee distributor, or Timelock.
    /// @param yieldAmount Additional LP tokens added as yield.
    function harvest(uint256 yieldAmount) external onlyOwner nonReentrant {
        require(yieldAmount > 0, "FeeVault: zero yield");

        totalYieldAccrued += yieldAmount;
        _asset.safeTransferFrom(msg.sender, address(this), yieldAmount);

        emit Harvested(msg.sender, yieldAmount);
    }

    /// @dev Virtual offset protects the first depositor from share-price manipulation.
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        return assets.mulDiv(totalSupply() + 1, totalAssets() + 1, rounding);
    }

    /// @dev Virtual offset keeps asset/share conversion symmetric with _convertToShares().
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 1, rounding);
    }
}
