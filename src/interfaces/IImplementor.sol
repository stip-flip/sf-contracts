// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title IImplementation
/// @notice Interface used by the factory for the implementation contracts
interface IImplementor {
    function synthImplementation() external view returns (address);
}
