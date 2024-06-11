// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import '../../src/oracles/Oracle.sol';
import '../../src/interfaces/IOracleView.sol';
import '../../script/lib/Date.sol';

import 'forge-std/Test.sol';

contract OracleTest is Test {
    Oracle public oracle;
    uint8[] public drops;

    uint24 offset;
    //"EthereumClassic", "Bitcoin", "Ethereum", "Dogecoin", "Monero", "Solana", "Bnb", "Cardano"
    uint8[8] public decimals = [6, 4, 5, 7, 6, 6, 5, 7];

    function setUp() public {
        console.log('setup');
        uint goerliFork = vm.createFork(vm.envString('RPC_MORDOR'));
        vm.selectFork(goerliFork);

        uint8 weekDay = uint8(Date.getWeekday(block.timestamp));

        // if the price is expected at a particular time, pass an offset
        uint8 hour = uint8(Date.getHour(block.timestamp));

        console.log(hour);

        uint24 secondsSinceLastHour = uint24(block.timestamp % 3600);

        // the round should start at 21:00 UTC, offset the initializing by the appropriate time
        // since the round 0 last 24 hour, make sure round 1 start at 21:00 UTC
        offset = ((21 + (24 - hour)) % 24) * 3600;

        console.log('offset', offset / 3600);

        offset -= secondsSinceLastHour;

        // drops.push((3 + (7 - weekDay)) % 7);
        drops.push((6 + (7 - weekDay)) % 7);
        drops.push((7 + (7 - weekDay)) % 7);

        oracle = new Oracle(
            decimals,
            drops,
            7,
            uint64(block.timestamp) - 24 hours + offset,
            24 hours, // 1 day frequency
            1 hours, // 1 hour round duration
            5 minutes, // 5 minutes delay for LP versus trader
            0.1 ether,
            'usd, bitcoin, ethereum, dogecoin, monero, solana, binancecoin, cardano, price comming from coingecko.com/, price expressed in ETC, except for ETC'
        );

        console.log(drops[0], drops[1]);

        oracle.deposit{value: 0.1 ether}();
    }

    function testSetSlots() public {
        uint256 priceData = oracle.setSlots(
            [
                uint256(2000 * 1e3),
                uint256(25 * 1e6),
                uint256(8277.35 * 1e3),
                uint256(2211.65 * 1e3),
                uint256(82.23 * 1e6),
                uint256(1.6793 * 1e6),
                uint256(6.5172 * 1e6),
                uint256(4.52 * 1e6)
            ]
        );

        uint[8] memory slots_ = oracle.getSlots(priceData);

        assertEq(slots_[0], 2000 * 1e3);
        assertEq(slots_[1], 25 * 1e6);
        assertEq(slots_[2], 8277.35 * 1e3);
        assertEq(slots_[3], 2211.65 * 1e3);
        assertEq(slots_[4], 82.23 * 1e6);
        assertEq(slots_[5], 1.6793 * 1e6);
        assertEq(slots_[6], 6.5172 * 1e6);
        assertEq(slots_[7], 4.52 * 1e6);
        // assertEq(timestamp, 1);
    }

    function testSetPrice() public {
        uint256 priceData = oracle.setSlots(
            [
                uint256(2000 * 1e6),
                uint256(25 * 1e6),
                uint256(8277.35 * 1e6),
                uint256(2211.65 * 1e6),
                uint256(82.23 * 1e6),
                uint256(1.6793 * 1e6),
                uint256(6.5172 * 1e6),
                uint256(4.52 * 1e6)
            ]
        );

        vm.expectRevert(abi.encodePacked('OBC'));
        oracle.setPrices(priceData, 1);

        vm.warp(block.timestamp + offset);
        oracle.setPrices(priceData, 1);

        // being the only staker, I should get one MANA after one price update
        assertEq(oracle.mana(address(this)), 1 ether, 'MANA=1');

        // you can submit a price only once per round
        vm.expectRevert(abi.encodePacked('OBS'));
        oracle.setPrices(priceData, 1);

        vm.warp(block.timestamp + offset + 1 hours);
        vm.expectRevert(abi.encodePacked('OBC'));
        oracle.setPrices(priceData, 1);
    }

    function testSetRealPrice() public {
        uint256 priceData = oracle.setSlots(
            [
                uint(35799411 * (10 ** decimals[0])) / 1e9,
                uint(2367542330095 * (10 ** decimals[1])) / 1e9,
                uint(114216887371 * (10 ** decimals[2])) / 1e9,
                uint(5670464 * (10 ** decimals[3])) / 1e9,
                uint(4406433408 * (10 ** decimals[4])) / 1e9,
                uint(5542511647 * (10 ** decimals[5])) / 1e9,
                uint(21706807366 * (10 ** decimals[6])) / 1e9,
                uint(18391314 * (10 ** decimals[7])) / 1e9
            ]
        );

        uint256[8] memory slots = oracle.getSlots(priceData);

        assertEq(slots[0], (35799411 * (10 ** decimals[0])) / 1e9);
        assertEq(slots[1], (2367542330095 * (10 ** decimals[1])) / 1e9);
        assertEq(slots[2], (114216887371 * (10 ** decimals[2])) / 1e9);
        assertEq(slots[3], (5670464 * (10 ** decimals[3])) / 1e9);
        assertEq(slots[4], (4406433408 * (10 ** decimals[4])) / 1e9);
        assertEq(slots[5], (5542511647 * (10 ** decimals[5])) / 1e9);
        assertEq(slots[6], (21706807366 * (10 ** decimals[6])) / 1e9);
        assertEq(slots[7], (18391314 * (10 ** decimals[7])) / 1e9);

        vm.warp(block.timestamp + offset);

        oracle.setPrices(priceData, 1);

        vm.warp(block.timestamp + 1 hours);

        for (uint8 i = 0; i < 8; i++) {
            console.log('------', i, '------');
            uint64 p = oracle.lastPrice(i, true, IOracleView.Leverage.NONE);

            console.log('price', p);
        }
    }

    function testGetPrice() public {
        vm.warp(block.timestamp + 24 hours);
        oracle.lastPrice(0);
    }

    function testCryptoOracle() public {
        Oracle cryptoOracle = new Oracle(
            [3, 3, 3, 8, 4, 4, 4, 8],
            drops,
            0,
            0,
            10 minutes, // 10 min frequency
            1 minutes, // 1 min round duration
            1 minutes, // 1 min delay for LP versus trader
            0.1 ether,
            'ethereum-classic, bitcoin, ethereum, dogecoin, monero, solana, binancecoin, cardano, price comming from coingecko.com/, price expressed in ETC, except for ETC'
        );

        cryptoOracle.deposit{value: 0.1 ether}();

        uint64 round = cryptoOracle.getCurrentRound();

        console.log('round', block.timestamp, round);

        vm.warp(block.timestamp + 1 minutes);

        console.log('round', block.timestamp, cryptoOracle.getCurrentRound());

        vm.warp(block.timestamp + 1 seconds);

        console.log('round', block.timestamp, cryptoOracle.getCurrentRound());

        vm.warp(block.timestamp + 9 minutes);

        console.log('round', block.timestamp, cryptoOracle.getCurrentRound());

        vm.warp(block.timestamp + 30 seconds);

        console.log('round', block.timestamp, cryptoOracle.getCurrentRound());
    }

    function testFlip() public {
        uint256 priceData = oracle.setSlots(
            [
                uint(35799411 * (10 ** decimals[0])) / 1e9,
                uint(2367542330095 * (10 ** decimals[1])) / 1e9,
                uint(114216887371 * (10 ** decimals[2])) / 1e9,
                uint(5670464 * (10 ** decimals[3])) / 1e9,
                uint(4406433408 * (10 ** decimals[4])) / 1e9,
                uint(5542511647 * (10 ** decimals[5])) / 1e9,
                uint(21706807366 * (10 ** decimals[6])) / 1e9,
                uint(18391314 * (10 ** decimals[7])) / 1e9
            ]
        );

        vm.warp(block.timestamp + offset);

        oracle.setPrices(priceData, 1);

        // move after the round duration
        vm.warp(block.timestamp + 1 hours);

        for (uint8 i = 1; i < 8; i++) {
            console.log('------', i, '------');
            uint64 max32Price = uint64(2 ** 32) / 100;
            uint64 max64Price = uint64(2 ** 64 - 1) / 100;

            uint64 p = oracle.lastPrice(i, true, IOracleView.Leverage.NONE);

            assertGt(p, 10_000, 'stip price >= 1e4');

            assertLt(p, max32Price, 'stip price < 2^32 / 100');

            console.log('stip price', p);

            p = oracle.lastPrice(i, true, IOracleView.Leverage.SQUARED);

            assertGt(p, 10_000, 'stip^2 price >= 1e4');

            assertLt(p, max64Price, 'stip^2 price < 2^64 / 100');

            console.log('stip^2 price', p);

            p = oracle.lastPrice(i, true, IOracleView.Leverage.CUBED);

            assertGt(p, 10_000, 'stip^3 price >= 1e4');

            assertLt(p, max64Price, 'stip^3 price < 2^64 / 100');

            console.log('stip^3 price', p);

            p = oracle.lastPrice(i, false, IOracleView.Leverage.NONE);

            assertGt(p, 10_000, 'flip price >= 1e4');

            assertLt(p, max64Price, 'flip price < 2^64 / 100');

            console.log('flip price', p);

            p = oracle.lastPrice(i, false, IOracleView.Leverage.SQUARED);

            assertGt(p, 10_000, 'flip^2 price >= 1e4');

            assertLt(p, max64Price, 'flip^2 price < 2^64 / 100');

            console.log('flip^2 price', p);

            p = oracle.lastPrice(i, false, IOracleView.Leverage.CUBED);

            assertGt(p, 1_000, 'flip^3 price >= 1e4');

            assertLt(p, max64Price, 'flip^3 price < 2^64 / 100');

            console.log('flip^3 price', p);
        }
    }
}
