// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import './FixedPointMathLib.sol';

import './SafeCast.sol';

import './TickMath.sol';

/// @title Math library for liquidity
library LiquidityMath {
    using SafeCast for int;
    using SafeCast for uint;

    int public constant IMAX_UINT24 = 2 ** 24;
    uint public constant MAX_UINT24 = 2 ** 24;

    function uint24toInt(uint24 x) internal pure returns (int converted) {
        unchecked {
            converted = x < 2 ** 23
                ? int24(x)
                : int(int24(x - 2 ** 23)) + 2 ** 23;
            return converted;
        }
    }

    function uint160toInt(uint160 x) internal pure returns (int converted) {
        unchecked {
            converted = x < 2 ** 159
                ? int160(x)
                : int(int160(x - 2 ** 159)) + 2 ** 159;
            return converted;
        }
    }

    function tickDelta(
        int24 tick0,
        int24 tick1
    ) internal pure returns (uint24 delta) {
        unchecked {
            delta = tick0 < tick1
                ? uint24(tick1 - tick0)
                : uint24(tick0 - tick1);
        }
    }

    function frDelta(
        int80 fr0,
        int80 fr1
    ) internal pure returns (uint80 delta) {
        unchecked {
            delta = fr0 < fr1 ? uint80(fr1 - fr0) : uint80(fr0 - fr1);
        }
    }

    function subFRDelta(int80 fr, uint80 delta) internal pure returns (int80) {
        if (fr < 0) {
            return -int80(delta + uint80(-fr));
        } else {
            return
                delta > uint80(fr)
                    ? -int80(delta - uint80(fr))
                    : int80(uint80(fr) - delta);
        }
    }

    function addFRDelta(int80 fr, uint80 delta) internal pure returns (int80) {
        if (fr < 0) {
            return
                delta > uint80(-fr)
                    ? int80(delta - uint80(-fr))
                    : -int80(uint80(-fr) - delta);
        } else {
            return int80(uint80(fr) + delta);
        }
    }

    /// @notice Add a signed liquidity delta to liquidity and revert if it overflows or underflows
    /// @param x The liquidity before change
    /// @param y The delta by which liquidity should be changed
    /// @return z The liquidity delta
    function addDelta(uint x, int y) internal pure returns (uint z) {
        if (y < 0) {
            require((z = x - uint(-y)) < x, 'LS');
        } else {
            require((z = x + uint(y)) >= x, 'LA');
        }
    }

    /// @notice given an amount of liquidity to move, and the current oracle price, get the amount of underlying token we can expect
    /// @param liquidityMoved the amount of liquidity to move
    /// @param lastPrice the last oracle price, 6 decimals precision
    function liquidityToBalance(
        uint96 liquidityMoved,
        uint lastPrice,
        uint8 decimals
    ) internal pure returns (uint balance) {
        unchecked {
            balance = FixedPointMathLib.mulDivUp(
                liquidityMoved,
                10 ** decimals,
                lastPrice
            );
        }
    }

    /// @notice given a balance amount, and the current oracle price, get the amount of liquidity to move
    /// @param balance the amount of balance to move
    /// @param lastPrice the last oracle price, 6 decimals precision
    function balanceToLiquidity(
        uint balance,
        uint lastPrice,
        uint8 decimals
    ) internal pure returns (uint96 liquidityMoved) {
        unchecked {
            liquidityMoved = uint96(
                FixedPointMathLib.mulDivUp(balance, lastPrice, 10 ** decimals)
            );
        }
    }

    /// @notice this function is used to compute the amount of liquidity to move in order to rebalance the pool after a price update
    function rebalance(
        uint96 totalLiquidities,
        uint64 lastPrice,
        uint64 newPrice
    ) internal pure returns (int96 rebalanced) {
        rebalanced = newPrice > lastPrice
            ? int(
                FixedPointMathLib.mulDivUp(
                    totalLiquidities,
                    newPrice - lastPrice,
                    lastPrice
                )
            ).i96()
            : -int(
                FixedPointMathLib.mulDivUp(
                    totalLiquidities,
                    lastPrice - newPrice,
                    lastPrice
                )
            ).i96();
    }

    function deltaFR(
        uint liquidity,
        uint liquidityPerTickX24
    ) internal pure returns (uint80 delta) {
        delta = uint80(
            FixedPointMathLib.mulDivDown(
                liquidity,
                MAX_UINT24 * TickMath.FR_PRECISION,
                liquidityPerTickX24
            )
        );
    }
}
