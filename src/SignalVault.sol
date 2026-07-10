// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IntentVerifier} from "./IntentVerifier.sol";
import {IStrategyRouter} from "./interfaces/IStrategyRouter.sol";
import {Allocation, TEEResult} from "./types/SignalVaultTypes.sol";

contract SignalVault is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    IStrategyRouter public immutable router;
    IntentVerifier public immutable verifier;
    address public immutable vaultOwner;

    mapping(address user => uint256 nonce) public userIntentNonce;
    mapping(address user => bytes32 commitment) public latestIntentCommitment;
    mapping(bytes32 resultHash => bool executed) public executedResults;

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event PrivateIntentSubmitted(
        address indexed user, bytes32 indexed intentCommitment, uint256 nonce, bytes encryptedIntent
    );
    event TEEAllocationExecuted(address indexed user, bytes32 indexed resultHash);

    error ZeroAddress();
    error ZeroAssets();
    error ZeroShares();
    error InvalidIntentNonce(uint256 expected, uint256 received);
    error Unauthorized();
    error SharesNonTransferable();
    error InvalidIntentCommitment();
    error EmptyEncryptedIntent();
    error InvalidRouterAsset();
    error InvalidRouterVault();
    error InvalidResultUser();
    error InvalidResultHash();
    error InvalidResult();
    error ResultAlreadyExecuted();
    error RouterAccountingMismatch(uint256 reported, uint256 received);

    modifier onlyVaultOwner() {
        if (msg.sender != vaultOwner) revert Unauthorized();
        _;
    }

    constructor(IERC20 asset_, address router_, address verifier_, address vaultOwner_)
        ERC20("SignalVault FXRP Share", "svFXRP")
    {
        if (
            address(asset_) == address(0) || router_ == address(0) || verifier_ == address(0)
                || vaultOwner_ == address(0)
        ) {
            revert ZeroAddress();
        }
        IStrategyRouter candidateRouter = IStrategyRouter(router_);
        if (candidateRouter.asset() != address(asset_)) revert InvalidRouterAsset();
        address boundVault = candidateRouter.vault();
        if (boundVault != address(0) && boundVault != address(this)) revert InvalidRouterVault();
        asset = asset_;
        router = candidateRouter;
        verifier = IntentVerifier(verifier_);
        vaultOwner = vaultOwner_;
        asset_.forceApprove(router_, type(uint256).max);
    }

    function decimals() public view override returns (uint8) {
        return IERC20Metadata(address(asset)).decimals();
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this)) + router.totalAssets();
    }

    function deposit(uint256 assets) external nonReentrant onlyVaultOwner returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();

        uint256 assetsBefore = totalAssets();
        uint256 supply = totalSupply();
        shares = supply == 0 || assetsBefore == 0 ? assets : assets * supply / assetsBefore;
        if (shares == 0) revert ZeroShares();

        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(msg.sender, shares);

        emit Deposited(msg.sender, assets, shares);
    }

    function withdraw(uint256 shares)
        external
        nonReentrant
        onlyVaultOwner
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroShares();

        uint256 supplyBefore = totalSupply();
        uint256 liquidAssets = asset.balanceOf(address(this)) * shares / supplyBefore;
        _burn(msg.sender, shares);

        uint256 balanceBefore = asset.balanceOf(address(this));
        uint256 reported = router.withdrawProRata(shares, supplyBefore);
        uint256 received = asset.balanceOf(address(this)) - balanceBefore;
        if (reported != received) revert RouterAccountingMismatch(reported, received);
        assets = liquidAssets + received;
        asset.safeTransfer(msg.sender, assets);

        emit Withdrawn(msg.sender, assets, shares);
    }

    function submitPrivateIntent(
        bytes calldata encryptedIntent,
        bytes32 intentCommitment,
        uint256 nonce
    ) external onlyVaultOwner {
        if (encryptedIntent.length == 0) revert EmptyEncryptedIntent();
        if (intentCommitment == bytes32(0)) revert InvalidIntentCommitment();
        uint256 expectedNonce = userIntentNonce[msg.sender] + 1;
        if (nonce != expectedNonce) revert InvalidIntentNonce(expectedNonce, nonce);

        userIntentNonce[msg.sender] = nonce;
        latestIntentCommitment[msg.sender] = intentCommitment;

        emit PrivateIntentSubmitted(msg.sender, intentCommitment, nonce, encryptedIntent);
    }

    function computeResultHash(TEEResult memory result) public pure returns (bytes32) {
        Allocation memory allocation = result.allocation;
        return keccak256(
            abi.encode(
                result.user,
                result.vault,
                result.intentCommitment,
                allocation.upshiftBps,
                allocation.firelightBps,
                allocation.sparkdexBps,
                allocation.idleBps,
                result.nonce,
                result.deadline,
                result.ftsoPriceTimestamp,
                result.chainId
            )
        );
    }

    function executeTEEAllocation(TEEResult calldata result, bytes calldata signature)
        external
        nonReentrant
    {
        if (result.user != vaultOwner) revert InvalidResultUser();
        bytes32 canonicalHash = computeResultHash(result);
        if (result.resultHash != canonicalHash) revert InvalidResultHash();
        if (executedResults[canonicalHash]) revert ResultAlreadyExecuted();
        if (
            userIntentNonce[vaultOwner] == 0 || latestIntentCommitment[vaultOwner] == bytes32(0)
                || result.vault != address(this) || result.nonce != userIntentNonce[vaultOwner]
                || result.intentCommitment != latestIntentCommitment[vaultOwner]
                || !verifier.verifyTEEResult(result, signature)
        ) revert InvalidResult();

        executedResults[canonicalHash] = true;
        router.rebalance(result.allocation);
        emit TEEAllocationExecuted(vaultOwner, canonicalHash);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert SharesNonTransferable();
        super._update(from, to, value);
    }
}
