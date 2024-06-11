// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import './base/Base.sol';

contract DebtTest is Base {
    function setUp() public {
        mockOracle.setPrice(1e6);

        deal(vm.addr(1), 100 ether);

        synth.initialize(
            address(mockOracle),
            1,
            'TST',
            'TST',
            'Testing',
            true,
            IOracleView.Leverage.NONE
        );
    }

    function testEmptyPoolEntryAndExit() public {
        // verify that the synth has zero liquidity
        // just make sure this does not revert
        enterAndClaim(1 ether, vm.addr(1));

        (uint128 pnl, uint96 totalLiquidities) = synth.slot0();
        assertEq(totalLiquidities, 0, 'ttl = 0');

        assertEq(
            synth.poolDebt(),
            1 ether - swapFees(1 ether) - mintFees(1 ether),
            'synth debt = 0'
        );

        exitAndClaim(0, vm.addr(1));

        assertEq(synth.poolDebt(), 0, 'synth debt == 0 | 1');
        assertEq(synth.shares(vm.addr(1)), 0, 'shares == 0');
        assertEq(synth.balanceOf(vm.addr(1)), 0, 'balance == 0');

        // there should be the entry swap fees that accumulated in the synth
        // no one can actually claim them since no liquidities or ticks were filled at entry, that's ok
        assertEq(
            address(synth).balance,
            mintFees(1 ether),
            'synth balance > 0'
        );
    }

    function testDebtIncreaseDecrease() public {
        mintAndClaim(1 ether, 0, vm.addr(1));

        enterAndClaim(1 ether, vm.addr(1));

        console.log('total liquidities', getSlot0().totalLiquidities);

        assertEq(synth.poolDebt(), 0, 'synth debt 0');

        // // simulate a 10% price increase, the trader should be able to exit with a profit
        mockOracle.setPrice(1.1 * 1e6);
        // move up in time so that the rebalance does not ignore the price change
        vm.warp(block.timestamp + 1 days);

        synth.rebalance();

        console.log('synth debt', synth.poolDebt());
        assertGt(synth.poolDebt(), 0, 'synth debt 1');
        // set the price back to 1e6
        mockOracle.setPrice(1e6);
        // move up in time so that the rebalance does not ignore the price change
        vm.warp(block.timestamp + 1 days);

        synth.rebalance();

        console.log('synth debt', synth.poolDebt());

        assertEq(synth.poolDebt(), 0, 'synth debt 2');

        console.log('total liquidities', getSlot0().totalLiquidities);

        exitAndClaim(0, vm.addr(1));

        assertEq(getSlot0().totalLiquidities, 0, 'total liquidities');
    }

    function testExitInDebt() public {
        mintAndClaim(1 ether, 100, vm.addr(1));

        enterAndClaim(1 ether, vm.addr(1));

        mockOracle.setPrice(1.1 * 1e6);
        // move up in time so that the rebalance does not ignore the price change
        vm.warp(block.timestamp + 1 days);

        exitAndClaim(0, vm.addr(1));

        console.log('synth debt', synth.poolDebt());
        assertEq(synth.poolDebt(), 0, 'synth debt');

        console.log('total liquidities', getSlot0().totalLiquidities);
        assertEq(getSlot0().totalLiquidities, 0, 'total liquidities');

        burnAndClaim(0, 100, vm.addr(1));
    }

    function testMintDebt() public {
        mintAndClaim(1 ether, 100, vm.addr(1));

        enterAndClaim(1 ether, vm.addr(1));

        console.log('ttl', getSlot0().totalLiquidities);
        console.log('position value 0', synth.positionValue(100, vm.addr(1)));

        assertEq(synth.poolDebt(), 0, 'synth debt 0');
        assertEq(
            getSlot0().totalLiquidities,
            1 ether - swapFees(1 ether),
            'total liquidities 0'
        );

        assertEq(
            synth.positionValue(100, vm.addr(1)),
            1 ether + mintFees(1 ether),
            'position value 0'
        );

        burnAndClaim(0.5 ether, 100, vm.addr(1));

        console.log('position value 1', synth.positionValue(100, vm.addr(1)));

        // since we burn half the shares, position value should be halved
        assertEq(
            synth.positionValue(100, vm.addr(1)),
            0.5 ether + mintFees(0.5 ether),
            'position value 1'
        );

        assertEq(
            synth.poolDebt() + getSlot0().totalLiquidities,
            (1 ether * (1e4 - uint(synth.FEE()))) / 1e4,
            'ttl + debt'
        );

        assertGt(synth.poolDebt(), 0, 'synth debt > 0');

        console.log('ttl', getSlot0().totalLiquidities);
        console.log('synth debt', synth.poolDebt());

        exitAndClaim(0, vm.addr(1));

        assertEq(synth.poolDebt(), 0, 'poolDebt = 0 | 1');

        console.log('synth balance', address(synth).balance);

        console.log('position value 2', synth.positionValue(100, vm.addr(1)));

        console.log('ttl', getSlot0().totalLiquidities);

        burnAndClaim(0, 100, vm.addr(1));
    }
}
