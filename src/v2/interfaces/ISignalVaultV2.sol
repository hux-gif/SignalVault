// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {TEEResultV2} from "../types/SignalVaultTypesV2.sol";

/// @notice Frozen runtime ABI for the personal SignalVault V2.
interface ISignalVaultV2 {
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

    function asset() external view returns (address);
    function router() external view returns (address);
    function verifier() external view returns (address);
    function vaultOwner() external view returns (address);

    function totalAssets() external view returns (uint256);
    function userIntentNonce() external view returns (uint256);
    function latestIntentCommitment() external view returns (bytes32);
    function executedResults(bytes32 resultHash) external view returns (bool);

    function deposit(uint256 assets) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 assets);
    function submitPrivateIntent(bytes32 intentCommitment, uint256 nonce) external;
    function executeAuthenticatedRebalance(TEEResultV2 calldata result, bytes calldata signature)
        external;
    function pauseRouter() external;
    function unpauseRouter() external;
    function recoverRouterPosition() external returns (uint256 sharesRecovered);
    function closeVault() external returns (uint256 assetsDelivered);
}
