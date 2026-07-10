// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategyAdapter} from "../interfaces/IStrategyAdapter.sol";

contract MockStrategyAdapter is IStrategyAdapter {
    using SafeERC20 for IERC20;

    IERC20 internal immutable _asset;
    address public immutable router;
    string internal _name;
    uint256 internal immutable _riskScore;

    error OnlyRouter();
    error ZeroAmount();

    constructor(IERC20 asset_, address router_, string memory name_, uint256 riskScore_) {
        _asset = asset_;
        router = router_;
        _name = name_;
        _riskScore = riskScore_;
    }

    modifier onlyRouter() {
        if (msg.sender != router) revert OnlyRouter();
        _;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function deposit(uint256 amount) external onlyRouter returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();
        _asset.safeTransferFrom(msg.sender, address(this), amount);
        return amount;
    }

    function withdraw(uint256 shares) external onlyRouter returns (uint256 amount) {
        _asset.safeTransfer(msg.sender, shares);
        return shares;
    }

    function previewRedeem(uint256 shares) external pure returns (uint256 amount) {
        return shares;
    }

    function totalAssets() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function riskScore() external view returns (uint256) {
        return _riskScore;
    }

    function name() external view returns (string memory) {
        return _name;
    }
}
