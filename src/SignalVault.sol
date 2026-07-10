// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IntentVerifier} from "./IntentVerifier.sol";
import {IStrategyRouter} from "./interfaces/IStrategyRouter.sol";

contract SignalVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    IStrategyRouter public immutable router;
    IntentVerifier public immutable verifier;

    mapping(address user => uint256 nonce) public userIntentNonce;
    mapping(address user => bytes32 commitment) public latestIntentCommitment;

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event PrivateIntentSubmitted(
        address indexed user, bytes32 indexed intentCommitment, uint256 nonce, bytes encryptedIntent
    );

    error ZeroAddress();
    error ZeroAssets();
    error ZeroShares();
    error InvalidIntentNonce(uint256 expected, uint256 received);
    error InsufficientAssets(uint256 expected, uint256 available);

    constructor(IERC20 asset_, address router_, address verifier_)
        ERC20("SignalVault FXRP Share", "svFXRP")
    {
        if (address(asset_) == address(0) || router_ == address(0) || verifier_ == address(0)) {
            revert ZeroAddress();
        }
        asset = asset_;
        router = IStrategyRouter(router_);
        verifier = IntentVerifier(verifier_);
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this)) + router.totalAssets();
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();

        uint256 assetsBefore = totalAssets();
        uint256 supply = totalSupply();
        shares = supply == 0 || assetsBefore == 0 ? assets : assets * supply / assetsBefore;
        if (shares == 0) revert ZeroShares();

        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(msg.sender, shares);

        emit Deposited(msg.sender, assets, shares);
    }

    function withdraw(uint256 shares) external returns (uint256 assets) {
        if (shares == 0) revert ZeroShares();

        uint256 supplyBefore = totalSupply();
        assets = shares * totalAssets() / supplyBefore;
        _burn(msg.sender, shares);

        router.withdrawProRata(shares, supplyBefore);
        uint256 available = asset.balanceOf(address(this));
        if (available < assets) revert InsufficientAssets(assets, available);
        asset.safeTransfer(msg.sender, assets);

        emit Withdrawn(msg.sender, assets, shares);
    }

    function submitPrivateIntent(
        bytes calldata encryptedIntent,
        bytes32 intentCommitment,
        uint256 nonce
    ) external {
        uint256 expectedNonce = userIntentNonce[msg.sender] + 1;
        if (nonce != expectedNonce) revert InvalidIntentNonce(expectedNonce, nonce);

        userIntentNonce[msg.sender] = nonce;
        latestIntentCommitment[msg.sender] = intentCommitment;

        emit PrivateIntentSubmitted(msg.sender, intentCommitment, nonce, encryptedIntent);
    }
}
