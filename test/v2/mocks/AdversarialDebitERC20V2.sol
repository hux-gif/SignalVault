// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Test token that can credit the requested transfer while debiting the
/// configured sender by a different amount. Supply changes are intentional and
/// model a hostile/non-standard underlying whose return value cannot be trusted.
contract AdversarialDebitERC20V2 is ERC20 {
    enum DebitMode {
        Normal,
        OverDebit,
        UnderDebit,
        ReceiverOverCredit
    }

    address public configuredSender;
    DebitMode public debitMode;
    uint256 public debitDelta;

    constructor() ERC20("Adversarial Debit Token", "ADEBIT") {}

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function configureDebit(address sender, DebitMode mode, uint256 delta) external {
        configuredSender = sender;
        debitMode = mode;
        debitDelta = delta;
    }

    function transfer(address receiver, uint256 amount) public override returns (bool) {
        if (msg.sender != configuredSender || debitMode == DebitMode.Normal) {
            return super.transfer(receiver, amount);
        }

        if (debitMode == DebitMode.OverDebit) {
            _transfer(msg.sender, receiver, amount);
            _burn(msg.sender, debitDelta);
        } else if (debitMode == DebitMode.UnderDebit) {
            require(debitDelta <= amount, "debit delta exceeds amount");
            _transfer(msg.sender, receiver, amount - debitDelta);
            _mint(receiver, debitDelta);
        } else {
            _transfer(msg.sender, receiver, amount);
            _mint(receiver, debitDelta);
        }
        return true;
    }
}
