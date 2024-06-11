pragma solidity ^0.8.6;

import 'forge-std/Script.sol';

import './lib/Strings.sol';
import './lib/Date.sol';
import '../src/periphery/Trader.sol';

function addressToString(address a) pure returns (string memory) {
    return Strings.toHexString(uint(uint160(a)), 20);
}

contract PeripheryScript is Script {
    function run() public {
        string memory path = string(
            abi.encodePacked(
                './addresses/',
                Strings.toString(block.chainid),
                '/periphery'
            )
        );

        vm.startBroadcast();

        TraderPeriphery traderPeriphery = new TraderPeriphery();

        vm.writeLine(path, 'TRADER_PERIPHERY: ');
        vm.writeLine(path, addressToString(address(traderPeriphery)));

        vm.stopBroadcast();
    }
}
