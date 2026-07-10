// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockStrategyAdapter} from "./MockStrategyAdapter.sol";

contract IdleAdapter is MockStrategyAdapter {
    constructor(IERC20 asset_, address router_) MockStrategyAdapter(asset_, router_, "Idle", 0) {}
}
