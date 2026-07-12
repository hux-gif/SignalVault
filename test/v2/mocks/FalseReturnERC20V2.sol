// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Test token that can return false without moving balances.
contract FalseReturnERC20V2 is ERC20 {
    enum FailureMode {
        None,
        Transfer,
        TransferFrom
    }

    FailureMode public failureMode;

    constructor() ERC20("False Return Token", "FALSE") {}

    function setFailureMode(FailureMode mode) external {
        failureMode = mode;
    }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function transfer(address receiver, uint256 amount) public override returns (bool) {
        if (failureMode == FailureMode.Transfer) return false;
        return super.transfer(receiver, amount);
    }

    function transferFrom(address owner, address receiver, uint256 amount)
        public
        override
        returns (bool)
    {
        if (failureMode == FailureMode.TransferFrom) return false;
        return super.transferFrom(owner, receiver, amount);
    }
}
