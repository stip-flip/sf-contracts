// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import './base/Base.sol';

contract PositionTest is Base {
    using Pack for int24;
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

    function testMint() public {
        int24 tick = -1200;
        uint64 r = mockOracle.getCurrentRound();

        vm.prank(vm.addr(1));
        synth.mint{value: 1 ether}(tick, vm.addr(2));

        mockOracle.incrementRound();

        mintees.push(tick.pack(vm.addr(1)));

        vm.prank(vm.addr(2));
        synth.claimAllPosition(mintees, burnees, r - 1, 0);

        vm.prank(vm.addr(2));
        synth.claimAllPosition(mintees, burnees, r - 1, 0);

        assertEq(synth.position(tick, vm.addr(1)).shares, 1 ether, 'shares');
    }

    function testMintWithClaimFees() public {
        mockOracle.incrementRound();

        int24 tick = -1200;
        uint64 r = mockOracle.getCurrentRound();

        vm.prank(vm.addr(1));
        synth.mint{value: 1 ether}(tick, vm.addr(2));

        // the synth balance should now be 1 eth
        assertEq(address(synth).balance, 1 ether, 'synth balance = 1 ether');

        mockOracle.incrementRound();

        mintees.push(tick.pack(vm.addr(1)));

        // try to claim from an unallowed sender, with claim fees
        vm.prank(vm.addr(3));
        synth.claimAllPosition(mintees, burnees, r - 1, 0.1 ether);

        // the synth balance should still be 1 eth since no mint was claimed
        assertEq(address(synth).balance, 1 ether, 'synth balance = 1 ether');

        // no position should be minted
        assertEq(synth.position(tick, vm.addr(1)).shares, 0, 'empty position');

        vm.prank(vm.addr(2));
        synth.claimAllPosition(mintees, burnees, r - 1, 0.1 ether);

        // the claimer charge 0.1 ether per mint/burn, we have one mint so the synth balance should be 0.9 eth
        assertEq(
            address(synth).balance,
            1 ether - 0.1 ether,
            'synth balance = 0.9 eth'
        );

        vm.prank(vm.addr(2));
        synth.claimAllPosition(mintees, burnees, r - 1, 0.1 ether);

        // since there is no mint left to claim, the claim fee should not be deducted
        assertEq(
            address(synth).balance,
            1 ether - 0.1 ether,
            'synth balance = 0.9 eth'
        );

        assertEq(synth.position(tick, vm.addr(1)).shares, 0.9 ether, 'shares');
    }

    function testBurn() public {
        int24 tick = -1200;

        vm.prank(vm.addr(1));
        vm.expectRevert(abi.encodePacked('NES'));
        synth.burn(tick, 1 ether, vm.addr(2));

        mintAndClaim(1 ether, tick, vm.addr(1));

        assertEq(synth.position(tick, vm.addr(1)).shares, 1 ether, 'shares');

        uint64 r = mockOracle.getCurrentRound();

        uint balanceBeforeBurn = vm.addr(1).balance;

        vm.prank(vm.addr(1));
        synth.burn(tick, 1 ether, vm.addr(2));

        mockOracle.incrementRound();

        burnees.push(tick.pack(vm.addr(1)));

        vm.prank(vm.addr(2));
        synth.claimAllPosition(mintees, burnees, r - 1, 0);

        vm.prank(vm.addr(2));
        synth.claimAllPosition(mintees, burnees, r - 1, 0);

        assertEq(synth.position(tick, vm.addr(1)).shares, 0, 'shares');

        assertEq(
            vm.addr(1).balance - balanceBeforeBurn,
            1 ether,
            'burn profit = 1 ether'
        );
    }

    function testBurnWithClaimFees() public {
        int24 tick = -1200;

        mintAndClaim(1 ether, tick, vm.addr(1));

        assertEq(synth.position(tick, vm.addr(1)).shares, 1 ether, 'shares');

        uint64 r = mockOracle.getCurrentRound();

        uint balanceBeforeBurn = vm.addr(1).balance;

        // burn more shares than the position has
        vm.prank(vm.addr(1));
        vm.expectRevert(abi.encodePacked('NES'));
        synth.burn(tick, 2 ether, vm.addr(2));

        vm.prank(vm.addr(1));
        synth.burn(tick, 1 ether, vm.addr(2));

        mockOracle.incrementRound();

        burnees.push(tick.pack(vm.addr(1)));

        uint balanceBeforeClaim = vm.addr(2).balance;

        vm.prank(vm.addr(2));
        synth.claimAllPosition(mintees, burnees, r - 1, 0.1 ether);

        assertEq(
            vm.addr(1).balance - balanceBeforeBurn,
            1 ether - 0.1 ether,
            'burn profit = 1 ether - 0.1 ether'
        );

        assertEq(
            vm.addr(2).balance - balanceBeforeClaim,
            0.1 ether,
            'claim fee = 0.1 ether'
        );

        assertEq(address(synth).balance, 0, 'synth balance = 0');

        assertEq(synth.position(tick, vm.addr(1)).shares, 0, 'shares');
    }
}
