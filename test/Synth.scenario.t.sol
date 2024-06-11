// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import './base/Base.sol';

contract PoolFactoryTest is Base {
    // total amount minted in the synth for testing
    uint96 public constant minted = 100 ether;

    // total amount to enter with
    uint96 public constant entered = 20 ether;
    // total amount to actually be exposed to
    uint96 public constant exposed = 80 ether;

    function fillMarket(address minter) public {
        // fill the market
        mintAndClaim(minted, -1200, minter);
    }

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
        fillMarket(vm.addr(1));
    }

    function testEntryPriceDecreaseOtherEntry() public {
        enterAndClaim(entered, vm.addr(2));
        console.log('hey', vm.addr(2).balance);

        assertEq(
            getSlot0().totalLiquidities,
            (entered * (1e4 - synth.FEE())) / 1e4,
            'total liquidities'
        );
        console.log(
            '1',
            synth.sharesValueWithRebalance(synth.balanceOf(vm.addr(2))),
            synth.balanceOf(vm.addr(2))
        );
        // set the price to half it's value
        mockOracle.setPrice(0.5 * 1e6);

        // synth.rebalance();

        console.log(
            '2',
            synth.sharesValueWithRebalance(synth.balanceOf(vm.addr(2))),
            synth.balanceOf(vm.addr(2))
        );

        // have someone else enter the synth
        // vm.stopPrank();

        // vm.prank(vm.addr(3));
        enterAndClaim(entered, vm.addr(3));
        console.log(
            'aadr3',
            synth.balanceOf(vm.addr(3)),
            synth.sharesValueWithRebalance(synth.balanceOf(vm.addr(3)))
        );
        vm.prank(vm.addr(2));
        console.log(
            'addr2',
            synth.balanceOf(vm.addr(2)),
            synth.sharesValueWithRebalance(synth.balanceOf(vm.addr(2)))
        );
    }

    function testNegativeFundingRate() public {
        // vm.startPrank(vm.addr(2));
        enterAndClaim(entered, vm.addr(2));

        assertEq(
            getSlot0().totalLiquidities,
            (entered * (1e4 - synth.FEE())) / 1e4,
            'total liquidities'
        );

        assertEq(
            getSlot0().totalLiquidities,
            getSlot2().totalShares,
            'ttl=trl'
        );

        assertEq(
            synth.sharesValueWithRebalance(synth.balanceOf(vm.addr(2))),
            (entered * (1e4 - synth.FEE())) / 1e4,
            'shares value'
        );

        assertEq(
            synth.balanceOf(vm.addr(2)),
            (entered * (1e4 - synth.FEE())) / 1e4,
            'balance'
        );
        // assertLt(getSlot0().fr, 0, 'funding rate');

        uint sharesValueBeforeWarp = synth.sharesValueWithRebalance(
            synth.shares(vm.addr(2))
        );

        // go forward in time to accumulate one day worth of funding rate
        vm.warp(block.timestamp + 365 days);

        uint sharesValueAfterWarp = synth.sharesValueWithRebalance(
            synth.shares(vm.addr(2))
        );

        uint accumulatedFR = sharesValueAfterWarp - sharesValueBeforeWarp;

        assertGt(
            sharesValueAfterWarp,
            sharesValueBeforeWarp,
            'negative FR, shares value increase'
        );

        // the diff in shares value divided by the shares value before the warp should be equal to the funding rate
        assertEq(
            ((sharesValueAfterWarp - sharesValueBeforeWarp) * 1e4) /
                sharesValueBeforeWarp,
            1200,
            'verifying FR calculation'
        );

        // exit the synth
        exitAndClaim(synth.balanceOf(vm.addr(2)), vm.addr(2));

        // verify the position pnl
        assertApproxEqAbs(
            positionPnL(-1200, vm.addr(1)),
            int96(mintFees(entered)) +
                int96(mintFees(sharesValueAfterWarp)) -
                int(accumulatedFR),
            1,
            'position pnl'
        );

        assertEq(getSlot0().totalLiquidities, 0, 'total liquidities');
        assertEq(getSlot2().totalShares, 0, 'trader liquidities');
        // vm.stopPrank();
    }

    function testSuccessiveDepositAndEnter() public {
        // the current tick and fr should be at -1200
        assertEq(getSlot1().tick, -1200, 'tick');
        // assertEq(
        //     getSlot0().fr,
        //     -1200 * TickMath.IFR_PRECISION,
        //     'funding rate'
        // );
        // make another deposit in the -synth.FEE() tick
        mintAndClaim(20 ether, -500, vm.addr(2));

        uint96 amountToEnter = 80 ether;

        // enter the synth so that we get in the -synth.FEE() tick
        enterAndClaim(amountToEnter, vm.addr(3));
        assertEq(
            getSlot0().totalLiquidities,
            (amountToEnter * (1e4 - synth.FEE())) / 1e4,
            'total liquidities'
        );
        assertEq(
            getSlot0().totalLiquidities,
            getSlot2().totalShares,
            'ttl=trl'
        );
        assertEq(
            synth.sharesValueWithRebalance(synth.balanceOf(vm.addr(3))),
            (amountToEnter * (1e4 - synth.FEE())) / 1e4,
            'shares value'
        );
        assertEq(
            synth.balanceOf(vm.addr(3)),
            (amountToEnter * (1e4 - synth.FEE())) / 1e4,
            'balance'
        );
    }

    function testMintThenBurnOnly() public {
        uint sf = swapFees(exposed);
        console.log('balance', address(synth).balance);

        enterAndClaim(exposed, vm.addr(2));
        console.log('balance', address(synth).balance);
        // swap fees should have accumulated in the synth synth
        assertEq(
            positionPnL(-1200, vm.addr(1)),
            int96(mintFees(exposed)),
            'pnl'
        );
        uint traderBalanceBeforeExit = synth.balanceOf(vm.addr(2));

        exitAndClaim(synth.balanceOf(vm.addr(2)), vm.addr(2));

        console.log('balance', address(synth).balance);
        // vm.stopPrank();
        // swap fees should have accumulated again
        assertApproxEqAbs(
            uint(positionPnL(-1200, vm.addr(1))),
            mintFees(exposed) + mintFees(traderBalanceBeforeExit),
            // ((exposed * synth.FEE()) / 1e4) + ((traderBalanceBeforeExit * synth.FEE()) / 1e4),
            1,
            'pnl2'
        );

        // vm.startPrank(vm.addr(1));

        uint balanceBeforeCollect = vm.addr(1).balance;

        // burn the position
        burnAndClaim(0, -1200, vm.addr(1));

        uint128 shares = synth.position(int24(-1200), vm.addr(1)).shares;
        uint enterAndExitFees = ((exposed * synth.FEE()) / 1e4) +
            ((traderBalanceBeforeExit * synth.FEE()) / 1e4);
        assertEq(shares, 0, 'shares');
        uint expectedTokensOwed = minted +
            mintFees(exposed) +
            mintFees(traderBalanceBeforeExit);
        console.log('expectedTokensOwed', expectedTokensOwed);

        assertEq(getSlot1().tick, -1200, 'tick');
        assertApproxEqAbs(
            vm.addr(1).balance,
            balanceBeforeCollect + expectedTokensOwed,
            1,
            'balance'
        );
    }

    function testMintThenBurnWithPriceChanges() public {
        // set the price to 1 ether on the oracle
        mockOracle.setPrice(1e6);
        console.log('trader balance', vm.addr(2).balance);
        assertEq(vm.addr(2).balance, 1000 ether, 'trader balance');

        enterAndClaim(exposed, vm.addr(2));

        assertEq(vm.addr(2).balance, 920 ether, 'trader balance');
        // swap fees should have accumulated in the synth synth
        assertEq(
            positionPnL(-1200, vm.addr(1)),
            int96(mintFees(exposed)),
            'position pnl'
        );

        uint svBeforeAccFR = synth.sharesValueWithRebalance(
            synth.shares(vm.addr(2))
        );

        vm.warp(block.timestamp + 365 days);

        uint svBeforePriceMove = synth.sharesValueWithRebalance(
            synth.shares(vm.addr(2))
        );
        // have a 10% decrease in price
        mockOracle.setPrice(0.9 * 1e6);
        // move up in time so that the rebalance rebalance the synth

        uint svBeforeExit = synth.sharesValueWithRebalance(
            synth.shares(vm.addr(2))
        );

        console.log(
            mintFees(exposed),
            mintFees(svBeforeExit),
            ((svBeforePriceMove * 10_00) / 1e4),
            ((svBeforeAccFR * 12_00) / 1e4)
        );

        int positionPnlAfterExit = int96(mintFees(exposed)) + // entry swap fees
            int96(mintFees(svBeforeExit)) + //exit swap fees
            int(((svBeforePriceMove * 10_00) / 1e4)) - // price moves
            int(((svBeforeAccFR * 12_00) / 1e4)); // accumulated negative funding rate

        console.log('positionPnlAfterExit');
        console.logInt(positionPnlAfterExit);
        // Exit.PreviewResult memory r = synth.previewExit(
        //     -int(synth.balanceOf(vm.addr(2))) // by passing it as negative, we swap the derivative
        // );
        // // console.log('liquidityMoved', liquidityMoved);
        // console.log('feeAmount', r.feeAmount);
        // console.log('frAfter', uint80(-r.frAfter));
        // console.log('pnl_', uint(-pnl_));
        exitAndClaim(synth.balanceOf(vm.addr(2)), vm.addr(2));
        uint oracleBalanceAfterExit = address(mockOracle).balance;
        assertEq(
            vm.addr(2).balance,
            uint(
                int(1000 ether) -
                    int(positionPnlAfterExit) -
                    int(oracleBalanceAfterExit)
            ),
            'trader balance after exit'
        );
        // console.log('positionPnlAfterExit', positionPnlAfterExit);
        console.log('trader balance', vm.addr(2).balance);

        // swap fees and trader pnl should have accumulated
        assertApproxEqAbs(
            positionPnL(-1200, vm.addr(1)),
            positionPnlAfterExit,
            1,
            'position pnl2'
        );

        uint balanceBeforeCollect = vm.addr(1).balance;

        // burn the position
        burnAndClaim(0, -1200, vm.addr(1));

        uint128 positionShares = synth
            .position(int24(-1200), vm.addr(1))
            .shares;
        assertEq(positionShares, 0, 'positionshares == 0');
        uint expectedTokensOwed = uint(int96(minted) + positionPnlAfterExit); // 10% decrease in price;

        assertEq(getSlot1().tick, -1200, 'tick');

        burnAndClaim(0, -1200, vm.addr(1));

        assertApproxEqAbs(
            vm.addr(1).balance,
            balanceBeforeCollect + expectedTokensOwed,
            1,
            'addr(1) balance'
        );
    }

    function testFeeGrowth() public {
        // 1. open a position to the left of the current liquidity deposit
        mintAndClaim(10 ether, -2200, vm.addr(3));
        assertEq(getSlot1().tick, -2200, 'tick');

        uint balanceBeforeEnter1 = vm.addr(2).balance;
        // enter with 80 ether, overing both ticks
        enterAndClaim(exposed, vm.addr(2));

        uint balanceAfterEnter1 = vm.addr(2).balance;
        assertEq(
            getSlot0().totalLiquidities,
            (exposed * (1e4 - synth.FEE())) / 1e4,
            'total liquidities'
        );
        console.logInt(positionPnL(-2200, vm.addr(3)));
        console.logInt(positionPnL(-1200, vm.addr(1)));

        uint sf = swapFees(exposed);
        uint mf = mintFees(exposed);
        uint oraclefees = oracleFees(exposed);

        assertApproxEqAbs(
            uint(positionPnL(-2200, vm.addr(3))) +
                uint(positionPnL(-1200, vm.addr(1))),
            mf,
            1,
            'positions pnls = mintFees'
        );

        assertEq(address(mockOracle).balance, oraclefees, 'oracle fees');

        assertEq(
            getSlot0().totalLiquidities,
            getSlot2().totalShares,
            'ttl=trl'
        );
        assertEq(
            synth.sharesValueWithRebalance(synth.balanceOf(vm.addr(2))),
            (exposed * (1e4 - synth.FEE())) / 1e4,
            'shares value'
        );
        assertEq(
            synth.balanceOf(vm.addr(2)),
            (exposed * (1e4 - synth.FEE())) / 1e4,
            'balance'
        );
        // make sure the FR is still negative
        // assertLt(getSlot0().fr, 0, 'funding rate');

        // go forward in time to accumulate one day worth of funding rate
        vm.warp(block.timestamp + 1 days);

        // exit the synth
        exitAndClaim(synth.balanceOf(vm.addr(2)), vm.addr(2));

        uint balanceAfterExit1 = vm.addr(2).balance;

        // the diff in balance for the trader should equal the diff in fees for LPs and the oracle
        assertApproxEqAbs(
            balanceBeforeEnter1 - balanceAfterExit1,
            uint(positionPnL(-2200, vm.addr(3))) +
                uint(positionPnL(-1200, vm.addr(1))) +
                address(mockOracle).balance,
            3, // 3 maximum because there is 3 fees split, which could result in 1 wei difference each, after division
            'fee distribution after exit'
        );

        // and the trader fee cost must always be higher than the fees gained by LPs and the oracle, when considering the rounding errors
        assertGe(
            balanceBeforeEnter1 - balanceAfterExit1,
            uint(positionPnL(-2200, vm.addr(3))) +
                uint(positionPnL(-1200, vm.addr(1))) +
                address(mockOracle).balance,
            'trader fee cost > LPs and oracle fees gains'
        );

        assertEq(getSlot0().totalLiquidities, 0, 'total liquidities');
        assertEq(getSlot2().totalShares, 0, 'trader liquidities');

        // deposit another position
        mintAndClaim(10 ether, 0, vm.addr(1));
        console.log(
            'shares ratio at entry',
            synth.position(0, vm.addr(1)).sharesRatio
        );

        assertEq(
            uint(positionPnL(0, vm.addr(1))),
            0,
            'just minted position pnl'
        );
    }

    function testExitInMultipleSteps() public {
        enterAndClaim(exposed, vm.addr(2));

        exitAndClaim(74 ether, vm.addr(2));

        exitAndClaim(6 ether - swapFees(exposed), vm.addr(2));

        assertEq(getSlot0().totalLiquidities, 0, 'total liquidities');
        assertEq(getSlot2().totalShares, 0, 'trader shares');
    }

    function testEntryExitAndAnotherEntryExitLater() public {
        uint balanceBeforeEnter1 = vm.addr(2).balance;
        console.log('balance before enter 1:', balanceBeforeEnter1);

        enterAndClaim(exposed, vm.addr(2));

        console.log(
            'synth balance before exit 1: ',
            synth.balanceOf(vm.addr(2))
        );

        console.log('position pnl 1: ', uint(positionPnL(-1200, vm.addr(1))));

        mockOracle.setPrice(0.99 * 1e6);

        exitAndClaim(synth.balanceOf(vm.addr(2)), vm.addr(2));

        assertEq(getSlot0().totalLiquidities, 0, 'total liquidities 0');
        assertEq(getSlot2().totalShares, 0, 'trader liquidities 0');

        console.log(
            'synth balance after exit 1: ',
            synth.balanceOf(vm.addr(2))
        );
        // go forward in time to accumulate 10 days worth of funding rate, should be 0 since no liquidities are in there
        vm.warp(block.timestamp + 10 days);

        uint balanceBeforeEnter2 = vm.addr(2).balance;
        console.log(
            'balance before enter 2:',
            balanceBeforeEnter1 - balanceBeforeEnter2,
            uint(positionPnL(-1200, vm.addr(1)))
        );

        assertApproxEqAbs(
            positionPnL(-1200, vm.addr(1)),
            int(
                (uint(int(balanceBeforeEnter1) - int(balanceBeforeEnter2)) *
                    (1e4 - synth.ORACLE_FEE())) / 1e4
            ),
            1,
            'pnl 1'
        );

        enterAndClaim(exposed, vm.addr(2));

        console.log('before exit 2: ', synth.balanceOf(vm.addr(2)));

        console.log('total liquidities: ', getSlot0().totalLiquidities);
        console.log('trader liquidities: ', getSlot2().totalShares);

        mockOracle.setPrice(1 * 1e6);

        exitAndClaim(synth.balanceOf(vm.addr(2)), vm.addr(2));

        assertEq(getSlot0().totalLiquidities, 0, 'total liquidities 1');
        assertEq(getSlot2().totalShares, 0, 'trader liquidities 1');

        console.log('after exit 2: ', synth.balanceOf(vm.addr(2)));
        // go forward in time to accumulate 10 days worth of funding rate, should be 0 since no liquidities are in there
        vm.warp(block.timestamp + 10 days);

        uint balanceBeforeEnter3 = vm.addr(2).balance;
        console.log('balance before enter 3:', balanceBeforeEnter3);

        assertApproxEqAbs(
            positionPnL(-1200, vm.addr(1)),
            int(
                (uint(int(balanceBeforeEnter1) - int(balanceBeforeEnter3)) *
                    (1e4 - synth.ORACLE_FEE())) / 1e4
            ),
            2,
            'pnl 2'
        );

        enterAndClaim(exposed, vm.addr(2));

        console.log('before exit 3: ', synth.balanceOf(vm.addr(2)));

        vm.warp(block.timestamp + 1 days);

        exitAndClaim(synth.balanceOf(vm.addr(2)), vm.addr(2));

        assertEq(getSlot0().totalLiquidities, 0, 'total liquidities');
        assertEq(getSlot2().totalShares, 0, 'trader liquidities');
    }
}
