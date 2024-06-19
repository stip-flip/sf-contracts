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

        // if the price is expected at a particular time, pass an offset
        uint64 hour = uint64(Date.getHour(block.timestamp));
        console.log('hour: ', hour);
        uint24 secondsSinceLastHour = uint24(block.timestamp % 3600);

        console.log(secondsSinceLastHour);

        // the round should start at 00:00 UTC, offset in hour
        uint64 offset = hour * 3600;

        offset += secondsSinceLastHour;
        uint64 frequency = 24 hours;
        // substracting the frequency to make sure the 0 round is skipped
        uint64 initialized = uint64(block.timestamp) - frequency - offset;

        uint8[8] memory magnitudes = [5, 5, 5, 5, 5, 5, 5, 5];

        Oracle cryptoOracle = new Oracle(
            [7, 2, 3, 8, 5, 5, 4, 7],
            magnitudes,
            drops,
            0,
            initialized + 5 days,
            24 hours, // 1 day frequency
            1 hours, // 1 hour round duration
            5 minutes, // 5 minutes delay for LP versus trader
            1 ether,
            'etc/usd, btc/etc, eth/etc, doge/etc, xmr/etc, sol/etc, bnb/etc, ada/etc, price coming from https://min-api.cryptocompare.com/data/v2/histoday, price expressed in ETC, except for ETC in USD. Fetched after midnight UTC for the day before'
        );

        // be the first staker
        // cryptoOracle.deposit{value: 1 ether}();

        vm.writeLine(path, 'CRYPTO_ORACLE_PROD: ');
        vm.writeLine(path, addressToString(address(cryptoOracle)));
    }
}
