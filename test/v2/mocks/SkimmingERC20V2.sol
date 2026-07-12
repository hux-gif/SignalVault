// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Test token that can deliver less than requested on transferFrom or on transfers
/// initiated by one configured sender while still returning true.
contract SkimmingERC20V2 is ERC20 {
    uint256 public transferFromShortfall;
    address public skimTransferFromOwner;
    address public skimTransferSender;
    uint256 public transferShortfall;
    address public falseTransferSender;

    constructor() ERC20("Skimming Token", "SKIM") {}

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function setTransferFromShortfall(address owner, uint256 shortfall) external {
        skimTransferFromOwner = owner;
        transferFromShortfall = shortfall;
    }

    function setTransferShortfall(address sender, uint256 shortfall) external {
        skimTransferSender = sender;
        transferShortfall = shortfall;
    }

    function setFalseTransferSender(address sender) external {
        falseTransferSender = sender;
    }

    function transfer(address receiver, uint256 amount) public override returns (bool) {
        if (msg.sender == falseTransferSender) return false;
        uint256 shortfall = msg.sender == skimTransferSender ? transferShortfall : 0;
        _skimTransfer(msg.sender, receiver, amount, shortfall);
        return true;
    }

    function transferFrom(address owner, address receiver, uint256 amount)
        public
        override
        returns (bool)
    {
        _spendAllowance(owner, msg.sender, amount);
        uint256 shortfall = owner == skimTransferFromOwner ? transferFromShortfall : 0;
        _skimTransfer(owner, receiver, amount, shortfall);
        return true;
    }

    function _skimTransfer(address owner, address receiver, uint256 amount, uint256 shortfall)
        private
    {
        require(shortfall <= amount);
        uint256 delivered = amount - shortfall;
        if (delivered > 0) _transfer(owner, receiver, delivered);
        if (shortfall > 0) _burn(owner, shortfall);
    }
}
