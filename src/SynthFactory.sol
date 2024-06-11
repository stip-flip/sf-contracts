// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.6;

import './interfaces/ISynthFactory.sol';
import './interfaces/IImplementor.sol';
import './interfaces/IOracleView.sol';

import './libraries/Clones.sol';

import './Synth.sol';

/// @title Synth factory
/// @notice Deploys Synth contracts
contract SynthFactory is ISynthFactory, IImplementor {
    address public immutable override synthImplementation;
    mapping(bytes32 => address) public synths;

    constructor() {
        synthImplementation = address(new Synth());
    }

    function createSynth(
        IOracleView oracle,
        uint8 oracleSlot,
        string memory name,
        string memory description,
        bool long,
        IOracleView.Leverage leverage
    ) external override returns (address synth) {
        bytes32 key = keccak256(
            abi.encodePacked(address(oracle), oracleSlot, long, leverage)
        );

        string memory exponent = '';
        if (leverage == IOracleView.Leverage.SQUARED) exponent = '\u00B2';
        if (leverage == IOracleView.Leverage.CUBED) exponent = '\u00B3';

        name = string(abi.encodePacked(name, exponent));

        string memory symbol = long
            ? string(abi.encodePacked('S-', name))
            : string(abi.encodePacked('F-', name));

        name = long
            ? string(abi.encodePacked('Stip-', name))
            : string(abi.encodePacked('Flip-', name));

        synth = Clones.cloneDeterministic(synthImplementation, key);

        Synth(synth).initialize(
            address(oracle),
            oracleSlot,
            name,
            symbol,
            description,
            long,
            leverage
        );

        synths[key] = synth;
        emit SynthCreated(address(oracle), synth, long);
    }
}
