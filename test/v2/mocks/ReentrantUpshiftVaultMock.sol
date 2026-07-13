// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ExecutionUpshiftVaultMock} from "./ExecutionUpshiftVaultMock.sol";

/// @notice Plan-named Upshift security mock exposing propagating callbacks and binding drift.
contract ReentrantUpshiftVaultMock is ExecutionUpshiftVaultMock {
    constructor(address asset_, address lpToken_) ExecutionUpshiftVaultMock(asset_, lpToken_) {}
}
