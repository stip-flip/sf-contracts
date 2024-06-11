// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.6;

import './Constants.sol';
import './FixedPointMathLib.sol';

library Shares {
    /// @notice for each unit of liquidity in the pool and given the pnl snapshot, compute the new shares ratio
    /// @param sharesRatio the current shares to liquidity ratio of the pool
    /// @param fees the fees or trader pnl used to compute the new ratio, from the perspective of the liquidity provider, a trader reporting gains need to pass a negative value and vice-versa
    /// @param totalLiquidities the total active liquidities of the pool
    function computeRatio(
        uint128 sharesRatio,
        uint96 fees,
        uint96 totalLiquidities
    ) internal pure returns (uint128) {
        if (fees == 0) return sharesRatio;
        uint newRatio = FixedPointMathLib.mulDivDown(
            totalLiquidities + fees,
            RAY,
            totalLiquidities
        );
        return
            uint128(FixedPointMathLib.mulDivDown(newRatio, sharesRatio, RAY));
    }

    /// @notice for each unit of liquidity in the pool and given the pnl snapshot, compute the new shares ratio
    /// @param sharesRatio the current shares to liquidity ratio of the pool
    /// @param pnl the trader pnl used to compute the new ratio, from the perspective of the liquidity provider, a trader reporting gains need to pass a negative value and vice-versa
    /// @param totalLiquidities the total active liquidities of the pool
    function computeRatioWithPnL(
        uint128 sharesRatio,
        int96 pnl,
        uint96 totalLiquidities
    ) internal pure returns (uint128) {
        if (pnl == 0) return sharesRatio;
        uint newRatio = pnl > 0
            ? FixedPointMathLib.mulDivDown(
                totalLiquidities + uint96(pnl),
                RAY,
                totalLiquidities
            )
            : FixedPointMathLib.mulDivDown(
                totalLiquidities - uint96(-pnl),
                RAY,
                totalLiquidities
            );
        return
            uint128(FixedPointMathLib.mulDivDown(newRatio, sharesRatio, RAY));
    }
}
