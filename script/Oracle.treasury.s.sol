pragma solidity ^0.8.6;

import 'forge-std/Script.sol';

import './lib/Strings.sol';
import './lib/Date.sol';
import '../src/oracles/Oracle.sol';

function addressToString(address a) pure returns (string memory) {
    return Strings.toHexString(uint(uint160(a)), 20);
}

contract TreasuryOracleScript is Script {
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

        uint8 weekDay = uint8(Date.getWeekday(block.timestamp));

        // if the price is expected at a particular time, pass an offset
        uint8 hour = uint8(Date.getHour(block.timestamp));

        uint24 secondsSinceLastHour = uint24(block.timestamp % 3600);

        console.log(secondsSinceLastHour);
        // the round should start at 21:00 UTC, offset in hour
        int24 offset = int24(int(int8(hour) - 21) * int(3600));

        offset += int24(secondsSinceLastHour);

        int24 frequency = 24 hours;

        uint64 initialized = uint64(
            int64(uint64(block.timestamp)) - frequency - offset
        );

        drops.push((6 + (7 - weekDay)) % 7);
        drops.push((7 + (7 - weekDay)) % 7);

        Oracle treasuryOracle = new Oracle(
            [6, 6, 6, 6, 6, 6, 6, 6],
            drops,
            7,
            initialized,
            uint24(frequency), // 1 day frequency
            1 hours, // 1 hour round duration
            5 minutes, // 5 minutes delay for LP versus trader
            0.1 ether,
            'DGS1MO, DGS6MO, DGS1, DGS2, DGS5, DGS10, DGS20, DGS30, daily frequency, data coming from fred.stlouisfed.org/'
        );

        // be the first staker
        treasuryOracle.deposit{value: 0.1 ether}();

        vm.writeLine(path, 'TREASURY_ORACLE: ');
        vm.writeLine(path, addressToString(address(treasuryOracle)));
    }
}
