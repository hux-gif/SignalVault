// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Test ERC-20 that reenters a caller-controlled target from inside transferFrom.
/// Used to prove ReentrancyGuard protection on IdleAdapterV2 state-changing methods.
/// The callback fires exactly once: armCallback sets the armed flag and transferFrom
/// clears it before invoking the target so a recursive call cannot loop indefinitely.
/// Callback failures propagate verbatim so tests can observe ReentrancyGuard reverts.
contract ReentrantERC20V2 is ERC20 {
    bool private _armed;
    address private _target;
    bytes private _data;

    constructor() ERC20("Reentrant Token", "REENT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function armCallback(address target, bytes calldata data) external {
        _armed = true;
        _target = target;
        _data = data;
    }

    function _runCallbackOnce() internal {
        if (!_armed) return;
        _armed = false;
        address target = _target;
        bytes memory data = _data;
        (bool ok, bytes memory returndata) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(returndata, 32), mload(returndata))
            }
        }
    }

    function transferFrom(address owner, address to, uint256 amount)
        public
        override
        returns (bool)
    {
        _runCallbackOnce();
        return super.transferFrom(owner, to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _runCallbackOnce();
        return super.transfer(to, amount);
    }
}
