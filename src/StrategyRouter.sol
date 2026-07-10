// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Allocation} from "./types/SignalVaultTypes.sol";
import {IStrategyAdapter} from "./interfaces/IStrategyAdapter.sol";

contract StrategyRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    address public vault;
    bool public adaptersConfigured;
    address[4] public adapters;
    mapping(address adapter => uint256 shares) public adapterShares;

    error OnlyVault();
    error AlreadyBound();
    error AlreadyConfigured();
    error AdaptersNotConfigured();
    error ZeroAddress();
    error InvalidAdapter();
    error InvalidAllocation();

    constructor(IERC20 asset_) Ownable(msg.sender) {
        if (address(asset_) == address(0)) revert ZeroAddress();
        asset = asset_;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    function bindVault(address vault_) external onlyOwner {
        if (vault != address(0)) revert AlreadyBound();
        if (!adaptersConfigured) revert AdaptersNotConfigured();
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;
    }

    function configureAdapters(address upshift, address firelight, address sparkdex, address idle)
        external
        onlyOwner
    {
        if (adaptersConfigured) revert AlreadyConfigured();
        address[4] memory configured = [upshift, firelight, sparkdex, idle];
        for (uint256 i; i < configured.length; ++i) {
            if (
                configured[i] == address(0)
                    || IStrategyAdapter(configured[i]).asset() != address(asset)
            ) revert InvalidAdapter();
            for (uint256 j; j < i; ++j) {
                if (configured[i] == configured[j]) revert InvalidAdapter();
            }
        }
        adapters = configured;
        adaptersConfigured = true;
    }

    function totalAssets() public view returns (uint256 total) {
        total = asset.balanceOf(address(this));
        for (uint256 i; i < adapters.length; ++i) {
            if (adapters[i] != address(0)) {
                total += IStrategyAdapter(adapters[i]).previewRedeem(adapterShares[adapters[i]]);
            }
        }
    }

    function rebalance(Allocation calldata allocation)
        external
        nonReentrant
        onlyVault
        returns (uint256 totalAssetsAfter)
    {
        if (_allocationTotal(allocation) != 10_000) revert InvalidAllocation();

        uint256 vaultBalance = asset.balanceOf(vault);
        if (vaultBalance != 0) asset.safeTransferFrom(vault, address(this), vaultBalance);

        for (uint256 i; i < adapters.length; ++i) {
            address adapter = adapters[i];
            uint256 shares = adapterShares[adapter];
            if (shares != 0) {
                adapterShares[adapter] = 0;
                IStrategyAdapter(adapter).withdraw(shares);
            }
        }

        uint256 assetsToAllocate = asset.balanceOf(address(this));
        uint256[4] memory amounts;
        amounts[0] = assetsToAllocate * allocation.upshiftBps / 10_000;
        amounts[1] = assetsToAllocate * allocation.firelightBps / 10_000;
        amounts[2] = assetsToAllocate * allocation.sparkdexBps / 10_000;
        amounts[3] = assetsToAllocate - amounts[0] - amounts[1] - amounts[2];

        for (uint256 i; i < adapters.length; ++i) {
            if (amounts[i] != 0) {
                asset.forceApprove(adapters[i], amounts[i]);
                adapterShares[adapters[i]] = IStrategyAdapter(adapters[i]).deposit(amounts[i]);
            }
        }
        return totalAssets();
    }

    function withdrawProRata(uint256 vaultShares, uint256 totalVaultShares)
        external
        nonReentrant
        onlyVault
        returns (uint256 assetsOut)
    {
        assetsOut = asset.balanceOf(address(this)) * vaultShares / totalVaultShares;
        for (uint256 i; i < adapters.length; ++i) {
            address adapter = adapters[i];
            uint256 shares = adapterShares[adapter] * vaultShares / totalVaultShares;
            if (shares != 0) {
                adapterShares[adapter] -= shares;
                assetsOut += IStrategyAdapter(adapter).withdraw(shares);
            }
        }
        asset.safeTransfer(vault, assetsOut);
    }

    function _allocationTotal(Allocation calldata allocation) private pure returns (uint256) {
        return uint256(allocation.upshiftBps) + allocation.firelightBps + allocation.sparkdexBps
            + allocation.idleBps;
    }
}
