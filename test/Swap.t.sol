// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import './base/Base.sol';

contract SwapTest is Base {
    function setUp() public {
        mockOracle.setPrice(1e6);
        synth.initialize(
            address(mockOracle),
            1,
            'TST',
            'TST',
            'Testing',
            true,
            IOracleView.Leverage.NONE
        );

        for (uint i = 1; i < 10; i++) {
            vm.deal(vm.addr(i), 1000 ether);
        }
    }

    function testEnter() public {
        // avoid round 0
        mockOracle.incrementRound();
        uint64 r = mockOracle.getCurrentRound();

        vm.prank(vm.addr(1));
        synth.enter{value: 1 ether}(vm.addr(2));

        mockOracle.incrementRound();

        enterees.push(vm.addr(1));
        entries.push(r - 1);

        // synth should have a balance of 1 ether
        assertEq(address(synth).balance, 1 ether, 'synth balance = 1 ether');

        vm.prank(vm.addr(3));
        synth.claimAllSwap(enterees, exitees, r - 1, 0);

        vm.prank(vm.addr(3));
        vm.expectRevert(abi.encodePacked('NES'));
        synth.claimAllSwap(entries, exits, vm.addr(3));

        // addr(1) has no shares because addr(3) is not the claimer
        assertEq(synth.shares(vm.addr(1)), 0, 'shares');

        vm.prank(vm.addr(2));
        synth.claimAllSwap(enterees, exitees, r - 1, 0);

        assertEq(
            synth.shares(vm.addr(1)),
            1 ether - swapFees(1 ether),
            'shares'
        );

        // synth should have a balance of 1 ether - oracle fees
        assertEq(
            address(synth).balance,
            1 ether - oracleFees(1 ether),
            'synth balance'
        );
    }

    function testEnterWithFees() public {
        // avoid round 0
        mockOracle.incrementRound();
        uint64 r = mockOracle.getCurrentRound();

        vm.prank(vm.addr(1));
        synth.enter{value: 1 ether}(vm.addr(2));

        // synth should have a balance of 1 ether
        assertEq(address(synth).balance, 1 ether, 'synth balance = 1 ether');

        mockOracle.incrementRound();

        enterees.push(vm.addr(1));

        vm.prank(vm.addr(2));
        synth.claimAllSwap(enterees, exitees, r - 1, 0.1 ether);

        assertEq(
            synth.shares(vm.addr(1)),
            1 ether - 0.1 ether - swapFees(0.9 ether), // 0.1 ether fee
            'shares'
        );

        // synth should have a balance of 1 ether
        assertEq(
            address(synth).balance,
            1 ether - 0.1 ether - oracleFees(0.9 ether),
            'synth balance'
        );
    }

    function testExit() public {
        vm.startPrank(vm.addr(1));
        // avoid round 0
        mockOracle.incrementRound();
        uint64 r = mockOracle.getCurrentRound();

        synth.enter{value: 1 ether}(vm.addr(2));

        mockOracle.incrementRound();

        entries.push(r - 1);

        synth.claimAllSwap(entries, exits, vm.addr(3));

        delete entries;

        vm.stopPrank();

        vm.startPrank(vm.addr(3));

        r = mockOracle.getCurrentRound();

        synth.exit(synth.balanceOf(vm.addr(3)), vm.addr(4));

        mockOracle.incrementRound();

        exits.push(r - 1);

        synth.claimAllSwap(entries, exits, vm.addr(3));

        vm.stopPrank();
    }

    function testExitWithFees() public {
        vm.startPrank(vm.addr(1));
        // avoid round 0
        mockOracle.incrementRound();
        uint64 r = mockOracle.getCurrentRound();

        synth.enter{value: 1 ether}(vm.addr(2));

        mockOracle.incrementRound();

        entries.push(r - 1);

        synth.claimAllSwap(entries, exits, vm.addr(3));

        delete entries;

        vm.stopPrank();

        vm.startPrank(vm.addr(3));

        r = mockOracle.getCurrentRound();

        synth.exit(synth.balanceOf(vm.addr(3)), vm.addr(4));

        mockOracle.incrementRound();

        exitees.push(vm.addr(3));

        vm.stopPrank();

        uint balanceBefore = vm.addr(4).balance;

        vm.startPrank(vm.addr(4));

        synth.claimAllSwap(enterees, exitees, r - 1, 0.1 ether);

        assertEq(
            vm.addr(4).balance - balanceBefore,
            0.1 ether,
            'periph balance'
        );

        assertEq(address(synth).balance, mintFees(1 ether), 'synth balance');
    }
}
