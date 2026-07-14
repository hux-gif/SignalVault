// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

contract RouterBoundVaultMockV2 {
    address public immutable vaultOwner;

    constructor(address vaultOwner_) {
        vaultOwner = vaultOwner_;
    }
}
