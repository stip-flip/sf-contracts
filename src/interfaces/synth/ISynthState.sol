// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Synth state that can change
/// @notice These methods compose the pool's state, and can change with any frequency including multiple times
/// per transaction
interface ISynthState {
    struct Slot0 {
        // the ratio of liquidity per shares since pool inception
        uint128 pnl;
        // total liquidies are the liquidities needed to secure the counterparty for trader trades
        uint96 totalLiquidities;
    }

    struct Slot1 {
        // for the current active tick, what is the ratio of liquidity being active, RAY, 100% = 1e27
        uint128 tickRatio;
        // the current tick (do we really need to store it if we know the fr)
        int24 tick;
        // the right most initialized tick
        int24 rightMostInitializedTick;
        // the left most initialized tick
        int24 leftMostInitializedTick;
    }

    struct Slot2 {
        // the amount of shares currently minted in the pool
        uint128 totalShares;
        // the last time the pool was rebalanced, either by a swap, a mint
        uint64 lastUpdate;
        // the last price the pool has been updated to
        uint64 lastPrice;
    }

    /// @notice The 0th storage slot in the pool stores many values, and is exposed as a single method to save gas
    /// when accessed externally.
    /// @return pnl the pnl for all LPs, accumulated since pool creation, per unit of liquidity WAD
    /// totalLiquidities The liquidities being secured by the traders in the pool.
    function slot0()
        external
        view
        returns (uint128 pnl, uint96 totalLiquidities);

    /// @notice The 1st storage slot in the pool stores many values, and is exposed as a single method to save gas
    /// when accessed externally.
    /// @return tickRatio the amount of liquidity per tick, WAD * 2^24
    /// tick the current tick (do we really need to store it if we know the fr)
    /// rightMostInitializedTick the right most initialized tick
    /// leftMostInitializedTick the left most initialized tick
    function slot1()
        external
        view
        returns (
            uint128 tickRatio,
            int24 tick,
            int24 rightMostInitializedTick,
            int24 leftMostInitializedTick
        );

    /// @notice The 2nd storage slot in the pool stores many values, and is exposed as a single method to save gas
    /// when accessed externally.
    /// @return totalShares the liquidities being used by the traders in the pool
    /// lastUpdate the last time the pool was rebalanced, either by a swap, a mint, or an oracle update
    /// lastPrice the last price the pool has been updated to, this has a 6 decimals precision
    function slot2()
        external
        view
        returns (uint128 totalShares, uint64 lastUpdate, uint64 lastPrice);

    /// @notice the pool debt, ie the amount of liquidities that are not backed by collateral
    function poolDebt() external view returns (uint96);
}
