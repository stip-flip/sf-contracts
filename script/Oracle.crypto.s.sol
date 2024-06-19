pragma solidity ^0.8.6;

import 'forge-std/Script.sol';

import './lib/Strings.sol';
import './lib/Date.sol';
import '../src/oracles/Oracle.sol';

function addressToString(address a) pure returns (string memory) {
    return Strings.toHexString(uint(uint160(a)), 20);
}

contract CryptoOracleScript is Script {
    uint8[] public drops;

    function run() public {
        string memory path = string(
            abi.encodePacked(
                './addresses/',
                Strings.toString(block.chainid),
                '/oracle'
            )
        );

        vm.startBroadcast();

        uint8[8] memory orders = [4, 7, 7, 4, 6, 6, 6, 5];

        /// all "crypto" prices expressed in ETC
        Oracle cryptoOracle = new Oracle(
            [6, 4, 5, 7, 6, 6, 5, 7],
            orders,
            drops,
            0,
            uint64(block.timestamp),
            10 minutes, // 10 min frequency
            1 minutes, // 1 min round duration
            1 minutes, // 1 min delay for LP versus trader
            0.1 ether,
            'usd, bitcoin, ethereum, dogecoin, monero, solana, binancecoin, cardano, price comming from coingecko.com/, price expressed in ETC, except for ETC'
        );

        // be the first staker
        cryptoOracle.deposit{value: 0.1 ether}();

        vm.writeLine(path, 'CRYPTO_ORACLE: ');
        vm.writeLine(path, addressToString(address(cryptoOracle)));
    }
}
