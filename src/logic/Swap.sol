// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../libraries/Tick.sol';
import '../interfaces/ISynth.sol';
import '../libraries/Constants.sol';

/// @notice Swap logic lib enables the pool to swap without charging fees, it can goes left to right or right to left
/// depending on the sign of amountToSwap
library SwapLogic {
    using TickBitmap for mapping(int16 => uint);
    using Tick for mapping(int24 => Tick.Info);
    using TickMath for int24;

    using LiquidityMath for uint96;
    using LiquidityMath for uint;

    using SafeCast for uint;
    using SafeCast for int;

    event Swap(uint96 liquidityMoved, int24 tick);

    // the top level state of the swap, the results of which are recorded in storage at the end
    struct SwapState {
        // the amount remaining to be swapped
        uint96 amountSpecifiedRemaining;
        // the current tick we are on
        int24 tick;
        // the current pnl of the pool
        uint128 pnl;
        // the current tick ratio of active/inactive liquidity, all liquidity active is RAY 1e27
        uint128 tickRatio;
    }

    struct StepComputations {
        // how much is being swapped in in this step
        uint96 liquidityMoved;
    }

    struct SwapParams {
        int96 amountToSwap;
        int80 frLimit;
    }

    /// @notice Swap a certain amount (int) accross ticks with a FR limit, update the storage tick (FR) and tickRatio of the synth if needed
    /// @param slot0 storage slot0 of the synth
    /// @param slot1 storage slot1 of the synth
    /// @param ticks storage mapping of ticks
    /// @param tickBitmap storage mapping of tickBitmap
    /// @param params SwapParams struct containing the amount to swap and the FR limit
    /// @return liquidityMoved the amount of liquidity moved
    function swap(
        ISynth.Slot0 storage slot0,
        ISynth.Slot1 storage slot1,
        mapping(int24 => Tick.Info) storage ticks,
        mapping(int16 => uint) storage tickBitmap,
        SwapParams memory params
    ) external returns (uint96 liquidityMoved) {
        bool enter = params.amountToSwap > 0;

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: params.amountToSwap > 0
                ? uint96(params.amountToSwap)
                : uint96(-params.amountToSwap),
            tick: slot1.tick,
            tickRatio: slot1.tickRatio,
            pnl: slot0.pnl
        });

        // continue swapping as long as we haven't used the entire input and haven't reached the fr limit
        while (
            state.amountSpecifiedRemaining != 0 &&
            (
                enter
                    ? state.tick.iToFR() <= params.frLimit
                    : state.tick.iToFR() >= params.frLimit
            )
        ) {
            StepComputations memory step;

            uint128 sharesRatio = ticks[state.tick].ratioInside;

            if (!enter) {
                (step.liquidityMoved, , ) = ticks.liquiditiesAvailable(
                    sharesRatio,
                    state.tickRatio,
                    state.tick
                );
            } else {
                (, step.liquidityMoved, ) = ticks.liquiditiesAvailable(
                    sharesRatio,
                    state.tickRatio,
                    state.tick
                );
            }

            // if liquidity remaining is higher than liquidity moved
            if (state.amountSpecifiedRemaining > step.liquidityMoved) {
                state.amountSpecifiedRemaining -= step.liquidityMoved;

                // we need to get to the next tick
                int24 tickNext = tickBitmap.nextInitializedTick(
                    enter ? state.tick : state.tick - 1,
                    !enter
                );

                if (enter) {
                    if (tickNext.iToFR() <= params.frLimit) {
                        ticks[state.tick].ratioOutside = FixedPointMathLib
                            .mulDivDown(
                                state.pnl,
                                RAY,
                                ticks[state.tick].ratioInside
                            )
                            .u128();
                    } else {
                        // stay on the same tick and mark the tickRatio as full (RAY)
                        state.tickRatio = RAY.u128();
                        break;
                    }
                } else {
                    if (tickNext.iToFR() >= params.frLimit) {
                        ticks[tickNext].ratioInside = FixedPointMathLib
                            .mulDivDown(
                                state.pnl,
                                RAY,
                                ticks[tickNext].ratioOutside
                            )
                            .u128();
                    } else {
                        // stay on the same tick and mark the tickRatio as empty (RAY)
                        state.tickRatio = 0;
                        break;
                    }
                }

                state.tickRatio = (enter ? 0 : RAY).u128();
                // move on to the next tick
                state.tick = tickNext;
            }
            // if liquidity remaining is lower that liquidity moved
            else {
                step.liquidityMoved = state.amountSpecifiedRemaining;
                state.amountSpecifiedRemaining = 0;

                // recompute the tickRatio
                state.tickRatio = ticks.newTickRatio(
                    sharesRatio,
                    state.tickRatio,
                    step.liquidityMoved,
                    state.tick,
                    enter
                );
            }
        }

        // update slot0 and slot1 storage variables
        if (state.tick != slot1.tick) {
            slot1.tick = state.tick;
        }

        if (slot1.tickRatio != state.tickRatio) {
            slot1.tickRatio = state.tickRatio;
        }

        liquidityMoved =
            (
                params.amountToSwap > 0
                    ? uint96(params.amountToSwap)
                    : uint96(-params.amountToSwap)
            ) -
            state.amountSpecifiedRemaining;

        emit Swap(liquidityMoved, state.tick);
    }

    struct PreviewSwapState {
        // the amount remaining to be swapped
        uint96 amountSpecifiedRemaining;
        // the current tick
        int24 tick;
        // the current tick ratio of active/inactive liquidity, all liquidity active is RAY 1e27
        uint128 tickRatio;
    }

    struct PreviewSwapParams {
        uint128 pnl;
        int96 amountToSwap;
        int80 frLimit;
    }

    /// @notice Preview a swap, it will not modify the synth storage, it will return the state as if the swap was executed
    /// @param ticks storage mapping of ticks
    /// @param tickBitmap storage mapping of tickBitmap
    /// @param state PreviewSwapState struct containing the current state of the swap
    /// @param params PreviewSwapParams struct containing the amount to swap and the FR limit
    function previewSwap(
        mapping(int24 => Tick.Info) storage ticks,
        mapping(int16 => uint) storage tickBitmap,
        PreviewSwapState memory state,
        PreviewSwapParams memory params
    ) external view returns (PreviewSwapState memory) {
        bool enter = params.amountToSwap > 0;
        state.amountSpecifiedRemaining = params.amountToSwap > 0
            ? uint96(params.amountToSwap)
            : uint96(-params.amountToSwap);
        while (
            state.amountSpecifiedRemaining != 0 &&
            (
                enter
                    ? state.tick.iToFR() < params.frLimit
                    : state.tick.iToFR() > params.frLimit
            )
        ) {
            StepComputations memory step;

            uint128 sharesRatio = ticks[state.tick].ratioInside;

            if (!enter) {
                (step.liquidityMoved, , ) = ticks.liquiditiesAvailable(
                    sharesRatio,
                    state.tickRatio,
                    state.tick
                );
            } else {
                (, step.liquidityMoved, ) = ticks.liquiditiesAvailable(
                    sharesRatio,
                    state.tickRatio,
                    state.tick
                );
            }

            // if liquidity remaining is higher than liquidity moved
            if (state.amountSpecifiedRemaining > step.liquidityMoved) {
                state.amountSpecifiedRemaining -= step.liquidityMoved;

                // we need to get to the next tick
                int24 tickNext = tickBitmap.nextInitializedTick(
                    state.tick,
                    !enter
                );

                state.tickRatio = (enter ? 0 : RAY).u128();

                // move on to the next tick
                state.tick = tickNext;
            }
            // if liquidity remaining is lower that liquidity moved, we compute the FR after the swap
            else {
                step.liquidityMoved = state.amountSpecifiedRemaining;
                state.amountSpecifiedRemaining = 0;

                // recompute the tickRatio
                state.tickRatio = ticks.newTickRatio(
                    sharesRatio,
                    state.tickRatio,
                    step.liquidityMoved,
                    state.tick,
                    enter
                );
            }
        }
        return state;
    }
}
