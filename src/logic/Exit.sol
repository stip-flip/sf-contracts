// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../libraries/Tick.sol';
import '../libraries/Shares.sol';
import '../interfaces/ISynth.sol';

import './Swap.sol';

library Exit {
    using TickBitmap for mapping(int16 => uint);
    using Tick for mapping(int24 => Tick.Info);
    using TickMath for int24;

    using LiquidityMath for uint96;
    using LiquidityMath for uint;
    using LiquidityMath for int96;

    using SafeCast for uint;
    using SafeCast for int;

    struct PreviewParams {
        int swapIn;
        uint sharesBalance;
        uint balance;
        uint24 fee;
        uint64 price;
        uint96 totalLiquidities;
        int96 accFR;
        uint96 poolDebt;
        uint8 decimals;
    }

    struct PreviewResult {
        int swapOut;
        uint96 feeAmount;
    }

    function preview(
        ISynthState.Slot2 storage slot2,
        PreviewParams memory params
    ) external view returns (PreviewResult memory r) {
        if (params.swapIn == 0) params.swapIn = int(params.sharesBalance);
        // substract the swap fees from the swap amount and convert to an unsigned integer

        int liquidities = _liquidities(slot2, params, params.swapIn > 0);

        r.feeAmount = FixedPointMathLib
            .mulDivDown(uint(liquidities), params.fee, 1e4)
            .u96();

        if (params.swapIn > 0) {
            // swapIn expressed as liquidities
            // @todo remove the fee amount
            r.swapOut = -liquidities;
        } else {
            // swapIn expressed as derivative
            // @todo remove the fee amount
            r.swapOut = int(
                LiquidityMath.liquidityToBalance(
                    uint(-params.swapIn).u96(),
                    params.price,
                    params.decimals
                )
            );
        }
    }

    function _liquidities(
        ISynthState.Slot2 storage slot2,
        PreviewParams memory params,
        bool derivative
    ) internal view returns (int liquidities) {
        uint shares_;

        if (derivative) {
            shares_ = FixedPointMathLib.mulDivDown(
                uint(params.swapIn),
                params.sharesBalance,
                params.balance
            );

            liquidities = int(sharesValueWithRebalance(slot2, params, shares_));
        } else {
            liquidities = -params.swapIn;

            shares_ = FixedPointMathLib.mulDivDown(
                uint(liquidities),
                slot2.totalShares,
                params.totalLiquidities + params.poolDebt
            );
        }
    }

    /// @notice get the shares value, while applying a virtual rebalancing to the pool before, ie updating the accumulated FR and price change
    function sharesValueWithRebalance(
        ISynthState.Slot2 storage slot2,
        PreviewParams memory params,
        uint shares_
    ) internal view returns (uint) {
        if (slot2.totalShares == 0) return 0;
        int96 liquidityToMove = LiquidityMath.rebalance(
            params.totalLiquidities + params.poolDebt,
            slot2.lastPrice,
            params.price
        );

        uint96 ttl = params.totalLiquidities +
            (
                liquidityToMove > 0
                    ? uint96(liquidityToMove)
                    : uint96(-liquidityToMove)
            ) +
            (params.accFR > 0 ? uint96(params.accFR) : uint96(-params.accFR)) +
            params.poolDebt;

        return FixedPointMathLib.mulDivDown(shares_, ttl, slot2.totalShares);
    }

    /// @notice accumulate fees in the pool once and for all
    /// slot0.totoLiquidities will be updated accordingly, as the pnl is compounded into existing active liquidities
    function accumulatePnL(
        ISynth.Slot0 storage slot0,
        ISynth.Slot1 storage slot1,
        mapping(int24 => Tick.Info) storage ticks,
        int96 liquidityProviderPnL
    ) external {
        // if totalLIquidities is zero return
        if (slot0.totalLiquidities == 0) return;
        (uint96 liquidityAvailable, uint96 upperLiquidity, ) = ticks
            .liquiditiesAvailable(
                ticks[slot1.tick].ratioInside,
                slot1.tickRatio,
                slot1.tick
            );

        slot0.pnl = Shares.computeRatioWithPnL(
            slot0.pnl,
            liquidityProviderPnL,
            slot0.totalLiquidities
        );

        ticks[slot1.tick].ratioInside = Shares.computeRatioWithPnL(
            ticks[slot1.tick].ratioInside,
            FixedPointMathLib
                .iMulDivDown(
                    liquidityProviderPnL,
                    liquidityAvailable,
                    slot0.totalLiquidities
                )
                .i96(),
            liquidityAvailable + upperLiquidity
        );

        // we also need to update the tickRatio,
        // to have the fee accumulate on the liquidityAvailable side
        // and not on the upper liquidity side

        // how much fees accumulated in the current tick
        int96 tickFees = FixedPointMathLib
            .iMulDivDown(
                liquidityProviderPnL,
                liquidityAvailable,
                slot0.totalLiquidities
            )
            .i96();

        // how much fees accumulated in the upper tick
        int96 upperTickFees = FixedPointMathLib
            .iMulDivUp(
                tickFees,
                upperLiquidity,
                liquidityAvailable + upperLiquidity
            )
            .i96();

        // once the pnl is settled, we report that pnl to the total liquidities
        slot0.totalLiquidities = uint96(
            int96(slot0.totalLiquidities) + liquidityProviderPnL
        );

        if (upperTickFees == 0) return;

        // move the tick ratio
        if (upperTickFees > 0) {
            slot1.tickRatio = ticks.newTickRatio(
                ticks[slot1.tick].ratioInside,
                slot1.tickRatio,
                uint96(upperTickFees),
                slot1.tick,
                true
            );
        } else {
            slot1.tickRatio = ticks.newTickRatio(
                ticks[slot1.tick].ratioInside,
                slot1.tickRatio,
                uint96(-upperTickFees),
                slot1.tick,
                false
            );
        }
    }
}
