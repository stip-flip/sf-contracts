// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import './base/Base.sol';

contract EnterExitTest is Base {
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

    function testClean() public {
        mintAndClaim(4 ether, 100, vm.addr(1));

        enterAndClaim(2 ether, vm.addr(1));

        console.log('position value', synth.positionValue(100, vm.addr(1)));
        // simulate a 10% price increase, the trader should be able to exit with a profit
        // mockOracle.setPrice(1.1 * 1e6);
        exitAndClaim(0, vm.addr(1));
    }

    function testTwoMint() public {
        // deposit some initial liquidities in the synth
        mintAndClaim(1 ether, -1200, vm.addr(1));

        mintAndClaim(3 ether, 100, vm.addr(1));

        enterAndClaim(2 ether, vm.addr(1));

        console.log(
            'position value',
            // synth.positionValue(-1200, vm.addr(1)),
            // synth.positionValue(100, vm.addr(1)),
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(-1200, vm.addr(1))
        );

        // simulate a 10% price increase, the trader should be able to exit with a profit
        // mockOracle.setPrice(1.1 * 1e6);

        exitAndClaim(0, vm.addr(1));

        console.log(
            'position value',
            synth.positionValue(-1200, vm.addr(1)),
            synth.positionValue(100, vm.addr(1)),
            synth.positionValue(-1200, vm.addr(1)) +
                synth.positionValue(100, vm.addr(1))
        );
    }

    function testThreeMint() public {
        // deposit some initial liquidities in the synth
        mintAndClaim(0.5 ether, -1200, vm.addr(1));

        mintAndClaim(0.5 ether, -600, vm.addr(1));

        mintAndClaim(3 ether, 100, vm.addr(1));

        enterAndClaim(2 ether, vm.addr(1));

        console.log(
            'position value',
            // synth.positionValue(-1200, vm.addr(1)),
            // synth.positionValue(100, vm.addr(1)),
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(-600, vm.addr(1)) +
                synth.positionValue(-1200, vm.addr(1))
        );

        // simulate a 10% price increase, the trader should be able to exit with a profit
        // mockOracle.setPrice(1.1 * 1e6);

        exitAndClaim(0, vm.addr(1));

        console.log(
            'position value',
            // synth.positionValue(-1200, vm.addr(1)),
            // synth.positionValue(100, vm.addr(1)),
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(-600, vm.addr(1)) +
                synth.positionValue(-1200, vm.addr(1))
        );
    }

    function testTwoEnterExit() public {
        mintAndClaim(4 ether, 100, vm.addr(1));

        enterAndClaim(2 ether, vm.addr(1));

        console.log('position value 0', synth.positionValue(100, vm.addr(1)));
        // simulate a 10% price increase, the trader should be able to exit with a profit
        // mockOracle.setPrice(1.1 * 1e6);

        exitAndClaim(0, vm.addr(1));

        console.log('synth tick ratio', getSlot1().tickRatio);
        console.log('synth liquidities', getSlot0().totalLiquidities);
        console.log('position value 1', synth.positionValue(100, vm.addr(1)));

        enterAndClaim(2 ether, vm.addr(1));

        console.log('position value 2', synth.positionValue(100, vm.addr(1)));

        exitAndClaim(0, vm.addr(1));

        console.log('position value 3', synth.positionValue(100, vm.addr(1)));
        console.log(getSlot1().tickRatio);
    }

    function testTwoMintAndEnterExit() public {
        mintAndClaim(1 ether, 100, vm.addr(1));
        mintAndClaim(3 ether, 200, vm.addr(1));

        enterAndClaim(2 ether, vm.addr(1));

        console.log(
            'position value 0',
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(200, vm.addr(1))
        );
        // simulate a 10% price increase, the trader should be able to exit with a profit
        // mockOracle.setPrice(1.1 * 1e6);

        exitAndClaim(0, vm.addr(1));

        console.log(
            'position value 1',
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(200, vm.addr(1))
        );
        console.log(getSlot1().tickRatio);

        enterAndClaim(2 ether, vm.addr(1));

        console.log(
            'position value 2',
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(200, vm.addr(1))
        );

        exitAndClaim(0, vm.addr(1));

        console.log(
            'position value 3',
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(200, vm.addr(1))
        );
        console.log(getSlot1().tickRatio);
    }

    function testEnterExitMintEnterExit() public {
        mintAndClaim(1 ether, 100, vm.addr(1));
        mintAndClaim(3 ether, 200, vm.addr(1));

        enterAndClaim(2 ether, vm.addr(1));

        console.log(
            'position value',
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(200, vm.addr(1))
        );

        mintAndClaim(2 ether, 100, vm.addr(1));

        console.log(
            'position value',
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(200, vm.addr(1))
        );

        exitAndClaim((synth.balanceOf(vm.addr(1)) * 3) / 4, vm.addr(1));

        console.log('ttl', getSlot0().totalLiquidities);

        console.log(
            'position value',
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(200, vm.addr(1))
        );

        // synth.swap(1 ether);

        console.log('---tick ratio----', getSlot1().tickRatio);

        console.log('ttl', getSlot0().totalLiquidities);

        exitAndClaim(0, vm.addr(1));

        console.log(
            'position value 1',
            synth.positionValue(100, vm.addr(1)),
            synth.positionValue(200, vm.addr(1)),
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(200, vm.addr(1))
        );

        enterAndClaim(2 ether, vm.addr(1));

        console.log(
            'position value 2',
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(200, vm.addr(1))
        );

        exitAndClaim((synth.balanceOf(vm.addr(1)) / 2), vm.addr(1));

        exitAndClaim(0, vm.addr(1));

        console.log(
            'position value 3',
            synth.positionValue(100, vm.addr(1)) +
                synth.positionValue(200, vm.addr(1))
        );
        console.log(getSlot1().tickRatio);
    }
}
