// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0 <=0.8.20;

import './LiquidityMath.sol';
import './SafeCast.sol';
import './Constants.sol';
import './FixedPointMathLib.sol';

/// @title Math library for computing sqrt prices from ticks and vice versa
library TickMath {
    using SafeCast for int96;
    using SafeCast for uint;
    using SafeCast for int;

    int24 internal constant MIN_TICK = -604_460;
    int24 internal constant MAX_TICK = -MIN_TICK;

    uint internal constant FR_PRECISION = 1e18;
    int internal constant IFR_PRECISION = 1e18;

    using LiquidityMath for int96;

    function checkTick(int24 tick) internal pure {
        require(tick >= MIN_TICK && tick <= MAX_TICK, 'T');
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function getTickAtFR(int160 fr) internal pure returns (int24 tick) {
        int frInt = (fr - (fr % IFR_PRECISION)) / IFR_PRECISION;
        tick = int24(frInt);
    }

    // function iToFR(int256 tick) internal pure returns (int256 fr) {
    //     // fr precision is 9 decimals
    //     fr = int256(tick) * 1e9;
    // }

    function iToFR(int tick) internal pure returns (int80 fr) {
        // fr precision is 9 decimals
        fr = (tick * IFR_PRECISION).i80();
    }

    function toFR(uint tick) internal pure returns (uint fr) {
        // fr precision is 9 decimals
        fr = tick * FR_PRECISION;
    }

    function iFromFR(int80 fr) internal pure returns (int24 tick) {
        tick = (fr / IFR_PRECISION).i24();
    }

    function fromFR(uint fr) internal pure returns (uint tick) {
        tick = fr / FR_PRECISION;
    }

    function deltaFR(int80 fr1, int80 fr2) internal pure returns (uint80) {
        return
            uint80(
                fr1 > fr2
                    ? uint(int(fr1) - int(fr2))
                    : uint(int(fr2) - int(fr1))
            );
    }

    /// @dev Returns the amount deposited below and above the currentTick, + the liquidity delta fo all impacted ticks.
    /// @param positionTick The position tick
    /// @param currentTick The current tick
    /// @param liquidityDelta The amount of liquidity to add or remove
    /// @param currentTickRatio The current tick ratio
    /// @return liquidityActive The amount of token deposited below the current tick
    /// @return liquidityInactive The amount of token deposited above the current tick
    function getAmounts(
        int24 positionTick,
        int24 currentTick,
        int96 liquidityDelta,
        uint128 currentTickRatio
    ) public pure returns (int96 liquidityActive, int96 liquidityInactive) {
        if (positionTick < currentTick) {
            liquidityActive = liquidityDelta;
        } else if (positionTick == currentTick) {
            // remove less of the liquidityActive (mulDivDown)
            liquidityActive = liquidityDelta > 0
                ? int(
                    FixedPointMathLib.mulDivDown(
                        uint96(liquidityDelta),
                        currentTickRatio,
                        RAY
                    )
                ).i96()
                : -int(
                    FixedPointMathLib.mulDivDown(
                        uint96(-liquidityDelta),
                        currentTickRatio,
                        RAY
                    )
                ).i96();
            liquidityInactive = liquidityDelta - liquidityActive;
        } else {
            liquidityInactive = liquidityDelta;
        }
    }
}
