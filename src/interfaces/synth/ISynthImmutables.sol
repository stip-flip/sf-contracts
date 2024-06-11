// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Synth state that never changes
/// @notice These parameters are fixed for a pool forever, i.e., the methods will always return the same values
interface ISynthImmutables {
    function FEE() external view returns (uint24);

    function ORACLE_FEE() external view returns (uint24);
}
