// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IStrategyRouterV2} from "./interfaces/IStrategyRouterV2.sol";
import {IntentVerifierV2} from "./IntentVerifierV2.sol";
import {SignalVaultHashesV2} from "./libraries/SignalVaultHashesV2.sol";
import {TEEResultV2, AllocationV2, RebalanceLimitsV2} from "./types/SignalVaultTypesV2.sol";

/// @notice Personal single-user vault with non-transferable shares,
/// authenticated TEE result verification, and frozen Router binding.
contract SignalVaultV2 is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAssets();
    error ZeroShares();
    error Unauthorized();
    error SharesNonTransferable();
    error InvalidIntentCommitment();
    error InvalidIntentNonce(uint256 expected, uint256 received);
    error InvalidResult();
    error ResultAlreadyExecuted();
    error RouterConfigMismatch();
    error IntentNotSubmitted();
    error DeadlineExpired();
    error InsufficientVaultLiquidity();

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event PrivateIntentSubmitted(
        address indexed user, bytes32 indexed intentCommitment, uint256 nonce
    );
    event AuthenticatedRebalanceExecuted(
        address indexed user, bytes32 indexed resultHash, uint256 totalAssetsAfter
    );
    event VaultClosed(address indexed user, uint256 assetsDelivered);
    event RouterPaused(address indexed user, bool paused);
    event RouterPositionRecovered(address indexed user, uint256 sharesRecovered);

    IERC20 public immutable asset;
    IStrategyRouterV2 public immutable router;
    IntentVerifierV2 public immutable verifier;
    address public immutable vaultOwner;

    uint256 public userIntentNonce;
    bytes32 public latestIntentCommitment;
    mapping(bytes32 => bool) public executedResults;

    modifier onlyVaultOwner() {
        if (msg.sender != vaultOwner) revert Unauthorized();
        _;
    }

    constructor(
        IERC20 asset_,
        IStrategyRouterV2 router_,
        IntentVerifierV2 verifier_,
        address vaultOwner_
    ) ERC20("SignalVault V2 FXRP Share", "svFXRP2") {
        if (
            address(asset_) == address(0) || address(router_) == address(0)
                || address(verifier_) == address(0) || vaultOwner_ == address(0)
        ) {
            revert ZeroAddress();
        }
        if (router_.asset() != address(asset_)) revert ZeroAddress();
        if (router_.vaultOwner() != vaultOwner_) revert Unauthorized();
        asset = asset_;
        router = router_;
        verifier = verifier_;
        vaultOwner = vaultOwner_;
    }

    function decimals() public view override returns (uint8) {
        return IERC20Metadata(address(asset)).decimals();
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this)) + router.totalAssets();
    }

    function deposit(uint256 assets) external onlyVaultOwner nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();

        uint256 nav = totalAssets();
        uint256 supply = totalSupply();
        shares = supply == 0 || nav == 0 ? assets : assets * supply / nav;
        if (shares == 0) revert ZeroShares();

        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(msg.sender, shares);

        emit Deposited(msg.sender, assets, shares);
    }

    function withdraw(uint256 shares)
        external
        onlyVaultOwner
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroShares();
        if (shares > balanceOf(msg.sender)) revert ZeroShares();

        uint256 supply = totalSupply();
        assets = totalAssets() * shares / supply;
        if (assets == 0) revert ZeroAssets();

        _burn(msg.sender, shares);

        uint256 vaultDirect = asset.balanceOf(address(this));
        if (vaultDirect < assets) {
            uint256 deficit = assets - vaultDirect;
            router.withdrawToVault(deficit);
        }

        asset.safeTransfer(msg.sender, assets);

        emit Withdrawn(msg.sender, assets, shares);
    }

    function submitPrivateIntent(bytes32 intentCommitment, uint256 nonce)
        external
        onlyVaultOwner
        nonReentrant
    {
        if (intentCommitment == bytes32(0)) revert InvalidIntentCommitment();
        uint256 expectedNonce = userIntentNonce + 1;
        if (nonce != expectedNonce) revert InvalidIntentNonce(expectedNonce, nonce);

        userIntentNonce = nonce;
        latestIntentCommitment = intentCommitment;

        emit PrivateIntentSubmitted(msg.sender, intentCommitment, nonce);
    }

    function executeAuthenticatedRebalance(TEEResultV2 calldata result, bytes calldata signature)
        external
        nonReentrant
    {
        if (result.user != vaultOwner) revert Unauthorized();
        if (result.vault != address(this)) revert InvalidResult();
        if (result.nonce != userIntentNonce || userIntentNonce == 0) revert IntentNotSubmitted();
        if (result.intentCommitment != latestIntentCommitment) revert IntentNotSubmitted();
        if (result.routerConfigHash != router.routerConfigHash()) revert RouterConfigMismatch();
        if (result.capabilityProfile != router.capabilityProfile()) revert InvalidResult();
        if (result.resultHash != SignalVaultHashesV2.computeResultHash(result)) {
            revert InvalidResult();
        }
        if (executedResults[result.resultHash]) revert ResultAlreadyExecuted();
        if (!verifier.verifyTEEResult(result, signature)) revert InvalidResult();

        executedResults[result.resultHash] = true;

        uint256 fundingAssets = asset.balanceOf(address(this));
        if (fundingAssets != 0) {
            asset.safeTransfer(address(router), fundingAssets);
        }

        uint256 totalAssetsAfter =
            router.rebalance(result.resultHash, result.allocation, result.limits, fundingAssets);

        emit AuthenticatedRebalanceExecuted(msg.sender, result.resultHash, totalAssetsAfter);
    }

    function pauseRouter() external onlyVaultOwner {
        router.setExecutionPaused(true);
        emit RouterPaused(msg.sender, true);
    }

    function unpauseRouter() external onlyVaultOwner {
        router.setExecutionPaused(false);
        emit RouterPaused(msg.sender, false);
    }

    function recoverRouterPosition()
        external
        onlyVaultOwner
        nonReentrant
        returns (uint256 sharesRecovered)
    {
        sharesRecovered = router.recoverAdapterPosition();
        emit RouterPositionRecovered(msg.sender, sharesRecovered);
    }

    function closeVault() external onlyVaultOwner nonReentrant returns (uint256 assetsDelivered) {
        uint256 shares = balanceOf(msg.sender);
        if (shares != 0) {
            _burn(msg.sender, shares);
        }

        router.withdrawAllToVault();

        assetsDelivered = asset.balanceOf(address(this));
        asset.safeTransfer(msg.sender, assetsDelivered);

        emit VaultClosed(msg.sender, assetsDelivered);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert SharesNonTransferable();
        super._update(from, to, value);
    }
}
