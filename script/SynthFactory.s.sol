// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import '../src/SynthFactory.sol';
import './lib/Strings.sol';
import 'forge-std/Script.sol';

function addressToString(address a) pure returns (string memory) {
    return Strings.toHexString(uint(uint160(a)), 20);
}

contract SynthFactoryScript is Script {
    function run() public {
        string memory path = string(
            abi.encodePacked(
                './addresses/',
                Strings.toString(block.chainid),
                '/synthfactory'
            )
        );

        vm.startBroadcast();
        SynthFactory factory = new SynthFactory();

        vm.writeLine(path, 'SYNTH_FACTORY: ');
        vm.writeLine(path, addressToString(address(factory)));

        vm.stopBroadcast();
    }
}
