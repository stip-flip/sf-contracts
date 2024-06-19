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
    uint8[8] public decimals = [7, 2, 3, 8, 5, 5, 4, 7];

    uint8[8] public magnitudes = [5, 5, 5, 5, 5, 5, 5, 5];

    uint price0 = 395256;
    uint price1 = 263803;
    uint price2 = 137066;
    uint price3 = 557310;
    uint price4 = 679207;
    uint price5 = 581974;
    uint price6 = 237074;
    uint price7 = 166363;

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
            magnitudes,
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

    // test an oracle for which initialised would be somewhere in the future
    function testDelayedOracle() public {
        // if the price is expected at a particular time, pass an offset
        uint64 hour = uint64(Date.getHour(block.timestamp));
        uint24 secondsSinceLastHour = uint24(block.timestamp % 3600);

        delete drops;
        // the round should start at 00:00 UTC, offset in hour
        uint64 offset_ = hour * 3600;

        offset_ += secondsSinceLastHour;
        uint64 frequency = 24 hours;

        uint64 delay = 5 days;
        // substracting the frequency to make sure the 0 round is skipped
        uint64 initialized = uint64(block.timestamp) - frequency - offset_;

        console.log('initialised + delay', initialized + delay + frequency);
        oracle = new Oracle(
            decimals,
            magnitudes,
            drops,
            0,
            initialized + delay,
            24 hours, // 1 day frequency
            1 hours, // 1 hour round duration
            5 minutes, // 5 minutes delay for LP versus trader
            0.1 ether,
            'usd, bitcoin, ethereum, dogecoin, monero, solana, binancecoin, cardano, price comming from coingecko.com/, price expressed in ETC, except for ETC'
        );

        deal(vm.addr(1), 100 ether);

        vm.startPrank(vm.addr(1));
        // I should still be able to deposit
        oracle.deposit{value: 1 ether}();

        // but not withdraw (before the initialisation date)
        vm.expectRevert();
        oracle.withdraw(1 ether, vm.addr(1));

        uint256 priceData = oracle.setSlots(
            [
                uint256(price0),
                uint256(price1),
                uint256(price2),
                uint256(price3),
                uint256(price4),
                uint256(price5),
                uint256(price6),
                uint256(price7)
            ]
        );

        // set price is also disabled before the initialisation date
        vm.expectRevert();
        oracle.setPrices(priceData, 1);

        vm.warp(block.timestamp + delay - offset_);

        oracle.setPrices(priceData, 1);

        vm.expectRevert();
        oracle.withdraw(1 ether, vm.addr(1));

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(abi.encodePacked('L'));
        oracle.withdraw(1 ether, vm.addr(1));

        vm.warp(block.timestamp + 2 days);

        oracle.withdraw(1 ether, vm.addr(1));
    }

    function testSetSlots() public {
        uint256 priceData = oracle.setSlots(
            [
                uint256(price0),
                uint256(price1),
                uint256(price2),
                uint256(price3),
                uint256(price4),
                uint256(price5),
                uint256(price6),
                uint256(price7)
            ]
        );

        uint[8] memory slots_ = oracle.getSlots(priceData);

        assertEq(slots_[0], price0);
        assertEq(slots_[1], price1);
        assertEq(slots_[2], price2);
        assertEq(slots_[3], price3);
        assertEq(slots_[4], price4);
        assertEq(slots_[5], price5);
        assertEq(slots_[6], price6);
        assertEq(slots_[7], price7);
        // assertEq(timestamp, 1);
    }

    function testSetPrice() public {
        uint256 priceData = oracle.setSlots(
            [
                uint256(price0),
                uint256(price1),
                uint256(price2),
                uint256(price3),
                uint256(price4),
                uint256(price5),
                uint256(price6),
                uint256(price7)
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
            magnitudes,
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
            [price0, price1, price2, price3, price4, price5, price6, price7]
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
            // console.log('binary digits', oracle.orderOfMagnitude(uint32(p)));

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
