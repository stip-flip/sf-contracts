// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import './synth/ISynthImmutables.sol';
import './synth/ISynthState.sol';
import './synth/ISynthActions.sol';
import './synth/ISynthEvents.sol';

/// @title The interface for an S&F Synth
/// @dev The synth interface is broken up into many smaller pieces
interface ISynth is
    ISynthImmutables,
    ISynthState,
    ISynthActions,
    ISynthEvents
{}
