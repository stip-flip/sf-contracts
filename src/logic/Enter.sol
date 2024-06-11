// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../libraries/FixedPointMathLib.sol';
import '../libraries/LiquidityMath.sol';
import '../libraries/SafeCast.sol';

library Enter {
    using SafeCast for uint;

    struct PreviewParams {
        int swapIn;
        uint8 decimals;
        uint24 fee;
        uint64 price;
    }

    struct PreviewState {
        bool derivative;
        int96 liquidityToMove;
        int liquidities;
    }

    struct PreviewResult {
        int swapOut;
        uint96 feeAmount;
    }

    function preview(
        PreviewParams memory params
    ) external pure returns (PreviewResult memory r) {
        PreviewState memory state;
        // substract the swap fees from the swap amount and convert to an unsigned integer
        state.derivative = params.swapIn < 0;

        // if swapIn is expressed in underlying token, translate to liquidities at the last price
        if (state.derivative) {
            state.liquidities = int96(
                LiquidityMath.balanceToLiquidity(
                    FixedPointMathLib.mulDivDown(
                        uint(-params.swapIn),
                        1e4 + params.fee,
                        1e4
                    ), // apply the swap fees to swap in
                    params.price,
                    params.decimals
                )
            );
        } else {
            state.liquidities = params.swapIn;
        }

        r.feeAmount = FixedPointMathLib
            .mulDivDown(uint(state.liquidities), params.fee, 1e4)
            .u96();

        if (state.derivative) {
            // swapOut expressed as liquidities
            r.swapOut = state.liquidities;
        } else {
            // swapOut expressed as derivative
            r.swapOut = -int(
                LiquidityMath.liquidityToBalance(
                    uint(params.swapIn).u96() - r.feeAmount,
                    params.price,
                    params.decimals
                )
            );
        }
    }
}
