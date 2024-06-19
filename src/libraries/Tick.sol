// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0 <=0.8.20;
import './LowGasSafeMath.sol';
import './SafeCast.sol';
import './TickMath.sol';
import './LiquidityMath.sol';
import './Position.sol';
import './TickBitmap.sol';
import './Constants.sol';

/// @title Tick
/// @notice Contains functions for managing tick processes and relevant calculations
library Tick {
    using TickBitmap for mapping(int16 => uint);
    using LowGasSafeMath for uint128;
    using SafeCast for uint;

    // info stored for each initialized individual tick
    struct Info {
        // the total position liquidity that references this tick
        // uint liquidityGross;
        // amount of net shares added when tick is crossed from left to right
        uint128 netShares;
        // liquidity to shares (ratio = liquidity / shares) ratio accumulated after the tick went in range
        // takes into account the case where that tick is partially filled
        // per unit of shares RAY
        uint128 ratioInside;
        // shares to liquidity ratio accumulated before the tick went in range
        // per unit of shares RAY
        uint128 ratioOutside;
    }

    /// @notice Derives max liquidity per tick from given tick spacing
    /// @dev Executed within the pool constructor
    /// @param tickSpacing The amount of required tick separation, realized in multiples of `tickSpacing`
    ///     e.g., a tickSpacing of 3 requires ticks to be initialized every 3rd tick i.e., ..., -6, -3, 0, 3, 6, ...
    /// @return maxLiquidityPerTick The maximum amount of liquidity that can be stored in a tick
    // function tickSpacingToMaxLiquidityPerTick(
    //     int24 tickSpacing
    // ) internal pure returns (uint128 maxLiquidityPerTick) {
    //     int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
    //     int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
    //     uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
    //     maxLiquidityPerTick = type(uint128).max / numTicks;
    // }

    struct SharesRatioInsideParams {
        uint128 pnl;
        int24 currentTick;
        int24 positionTick;
    }

    /// @notice Retrieves the average shares ratio below the position's tick
    /// @param self The mapping containing all tick information for initialized ticks
    /// @param params The parameters for calculating fee growth
    /// @return sharesRatio The average shares ratio accross the full range of liquidities deposited in a position
    function getSharesRatioInside(
        mapping(int24 => Tick.Info) storage self,
        SharesRatioInsideParams memory params
    ) public view returns (uint128 sharesRatio) {
        if (params.positionTick < params.currentTick) {
            // the position tick is below the active tick, formula will be PnL / positionTick.ratioOutside
            sharesRatio = FixedPointMathLib
                .mulDivDown(
                    params.pnl,
                    RAY,
                    self[params.positionTick].ratioOutside
                )
                .u128();
        } else {
            // the tick delta is above or wrapping the current tick, we just take the ratioInside of the next tick
            sharesRatio = self[params.positionTick].ratioInside;
        }
    }

    /// @notice For a given tick and netShares returns the amount of USDC it holds
    /// @param self The mapping containing all tick information for initialized ticks
    /// @param tick The tick for which to calculate the value
    /// @param sharesRatio The ratio of shares to liquidity
    function value(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint128 sharesRatio
    ) internal view returns (uint128) {
        return
            FixedPointMathLib
                .mulDivDown(self[tick].netShares, sharesRatio, RAY)
                .u128();
    }

    function value(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int24 currentTick,
        uint128 pnl
    ) external view returns (uint) {
        uint128 sharesRatio = getSharesRatioInside(
            self,
            SharesRatioInsideParams({
                pnl: pnl,
                currentTick: currentTick,
                positionTick: tick
            })
        );
        return value(self, tick, sharesRatio);
    }

    /// @notice return the current shareRatio in the active tick
    /// always return the current shareRatio in the active tick
    // function ratioInRange(
    //     mapping(int24 => Tick.Info) storage self,
    //     uint128 pnl,
    //     int24 positionTick
    // ) internal view returns (uint128) {
    //     return
    //         FixedPointMathLib
    //             .mulDivDown(pnl, RAY, self[positionTick].ratioOutside)
    //             .u128();
    // }

    function liquiditiesAvailable(
        mapping(int24 => Tick.Info) storage self,
        uint128 sharesRatio,
        uint128 tickRatio,
        int24 tick
    )
        internal
        view
        returns (uint96 liquidity0, uint96 liquidity1, uint96 liquidity)
    {
        Tick.Info storage info = self[tick];
        liquidity = FixedPointMathLib
            .mulDivDown(info.netShares, sharesRatio, RAY)
            .u96();
        liquidity0 = FixedPointMathLib
            .mulDivDown(liquidity, tickRatio, RAY)
            .u96();
        // liquidity = uint96((uint(info.netShares) * uint(sharesRatio)) / RAY);
        // liquidity0 = uint96((uint(liquidity) * uint(tickRatio)) / RAY);
        liquidity1 = liquidity - liquidity0;
    }

    function newTickRatio(
        mapping(int24 => Tick.Info) storage self,
        uint128 sharesRatio,
        uint128 tickRatio,
        uint96 liquidityMoved,
        int24 tick,
        bool enter
    ) internal view returns (uint128) {
        Tick.Info storage info = self[tick];
        uint liquidity = FixedPointMathLib.mulDivDown(
            info.netShares,
            sharesRatio,
            RAY
        );
        uint liquidity0 = FixedPointMathLib.mulDivUp(liquidity, tickRatio, RAY);
        if (enter) {
            return
                FixedPointMathLib
                    .mulDivUp(liquidity0 + liquidityMoved, RAY, liquidity)
                    .u128();
        } else {
            return
                FixedPointMathLib
                    .mulDivUp(
                        liquidity0 > liquidityMoved
                            ? liquidity0 - liquidityMoved
                            : 0,
                        RAY,
                        liquidity
                    )
                    .u128();
        }
    }

    struct InitializeParams {
        uint128 pnl;
        int24 currentTick;
        int24 positionTick;
        int24 rightMostInitializedTick;
    }

    function initialize(
        mapping(int24 => Tick.Info) storage self,
        mapping(int16 => uint) storage tickBitmap,
        InitializeParams memory params
    ) internal returns (uint128 sharesRatio) {
        Tick.Info storage info = self[params.positionTick];
        require(info.netShares == 0, 'T:AI');

        int24 nextTick = params.positionTick >= params.rightMostInitializedTick
            ? TickMath.MAX_TICK
            : tickBitmap.nextInitializedTick(params.positionTick, false);
        if (params.positionTick >= params.currentTick) {
            // if the tick is above the active tick, we take the ratioInside of the next tick
            // the ratioOutside does not matter and can remain at 0 as it will be updated in the cross that will eventually activate that tick
            info.ratioInside = self[nextTick].ratioInside == 0
                ? uint128(RAY)
                : self[nextTick].ratioInside;

            info.ratioOutside = RAY.u128();

            sharesRatio = info.ratioInside;
        } else {
            // if the tick is below the active tick, we take the ratioOutside of the next tick
            // the ratioInside does not matter and can remain at 0 as it will be updated in the cross that will eventually activate that tick
            info.ratioOutside = self[nextTick].ratioOutside == 0
                ? uint128(RAY)
                : self[nextTick].ratioOutside;

            info.ratioInside = RAY.u128();

            sharesRatio = FixedPointMathLib
                .mulDivDown(params.pnl, RAY, info.ratioOutside)
                .u128();
        }
    }

    /// @notice Updates a tick
    /// @param self The mapping containing all tick information for initialized ticks
    /// @param shares The amount of shares to add or remove
    /// @param tick The tick that will be updated
    /// @param mint Whether the shares are being added or removed
    function update(
        mapping(int24 => Tick.Info) storage self,
        uint128 shares,
        int24 tick,
        bool mint
    ) internal {
        Tick.Info storage info = self[tick];
        // when the tick is crossed left to right (right to left), liquidity must be added (removed)
        info.netShares = mint
            ? info.netShares.add(shares).u128()
            : info.netShares.sub(shares).u128();
    }

    /// @notice Clears tick data
    /// @param self The mapping containing all initialized tick information for initialized ticks
    /// @param tick The tick that will be cleared
    function clear(
        mapping(int24 => Tick.Info) storage self,
        int24 tick
    ) internal {
        delete self[tick];
    }
}
