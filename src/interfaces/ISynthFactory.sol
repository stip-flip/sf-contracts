// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import './IOracleView.sol';

/// @title The interface for the S&F Factory
interface ISynthFactory {
    /// @notice Emitted when a synth is created
    /// @param oracle The oracle used to determine the price of the share token
    /// @param synth The address of the short synth
    /// @param long Whether the synth is a long or a short (stip or flip)
    event SynthCreated(
        address indexed oracle,
        address indexed synth,
        bool long
    );

    /// @notice Creates a synth for the given two tokens and fee
    /// @param oracle The oracle used in the synth
    /// @param oracleSlot The oracle slot used in the synth
    /// @param name The name of the synth
    /// @param description The description of the synth
    /// @param long Whether the synth is a long synth
    /// @param leverage The leverage of the synth
    /// @return synth The address of the newly created synth
    function createSynth(
        IOracleView oracle,
        uint8 oracleSlot,
        string memory name,
        string memory description,
        bool long,
        IOracleView.Leverage leverage
    ) external returns (address synth);
}
