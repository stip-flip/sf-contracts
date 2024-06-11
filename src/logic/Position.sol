// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '../libraries/Position.sol';
import '../libraries/SafeCast.sol';
import '../libraries/TickMath.sol';
import '../libraries/TickBitmap.sol';
import '../libraries/LiquidityMath.sol';
import '../interfaces/synth/ISynthState.sol';

library PositionLogic {
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using Tick for mapping(int24 => Tick.Info);
    /// @inheritdoc ISynthState
    using TickBitmap for mapping(int16 => uint);

    using SafeCast for uint;

    /// @notice Emitted when liquidity is minted for a given position
    /// @param sender The address that minted the liquidity
    /// @param owner The owner of the position and recipient of any minted liquidity
    /// @param positionTick The tick of the position
    /// @param liquidityDelta The amount of liquidity minted
    event Mint(
        address sender,
        address indexed owner,
        int24 indexed positionTick,
        uint96 liquidityDelta
    );

    /// @notice Emitted when a position's liquidity is removed
    /// @dev Does not withdraw any fees earned by the liquidity position, which must be withdrawn via #collect
    /// @param owner The owner of the position for which liquidity is removed
    /// @param positionTick The lower tick of the position
    /// @param liquidityDelta The amount of liquidity that was removed
    event Burn(
        address indexed owner,
        int24 indexed positionTick,
        uint96 liquidityDelta
    );

    /// @dev Common checks for valid tick inputs.
    function checkTicks(int24 tickLower, int24 tickUpper) internal pure {
        require(tickLower < tickUpper, 'TLU');
        require(tickLower >= TickMath.MIN_TICK, 'TLM');
        require(tickUpper <= TickMath.MAX_TICK, 'TUM');
    }

    function checkTick(int24 tick) internal pure {
        require(tick >= TickMath.MIN_TICK, 'TLM');
        require(tick <= TickMath.MAX_TICK, 'TUM');
    }

    struct MintPositionParams {
        // the address that owns the position
        address owner;
        // the lower and upper tick of the position
        int24 positionTick;
        /// @notice the amount of liquidity to add/remove
        uint96 liquidityDelta;
    }

    function mintPosition(
        ISynthState.Slot0 storage slot0,
        ISynthState.Slot1 storage slot1,
        mapping(bytes32 => Position.Info) storage positions,
        mapping(int24 => Tick.Info) storage ticks,
        mapping(int16 => uint) storage tickBitmap,
        MintPositionParams memory params
    )
        external
        returns (
            Position.Info storage position,
            int96 liquidityActive,
            int96 liquidityInactive
        )
    {
        // check that the tick is inside the max FR bound range for a pool
        checkTick(params.positionTick);

        if (
            slot0.totalLiquidities == 0 &&
            slot1.leftMostInitializedTick > params.positionTick
        ) {
            slot1.tick = params.positionTick;
        }

        position = positions.get(params.owner, params.positionTick);

        uint128 sharesRatio;
        // flip the ticks if not initialized yet
        if (ticks[params.positionTick].netShares == 0) {
            tickBitmap.flipTick(params.positionTick);
            sharesRatio = ticks.initialize(
                tickBitmap,
                Tick.InitializeParams({
                    pnl: slot0.pnl,
                    currentTick: slot1.tick,
                    positionTick: params.positionTick,
                    rightMostInitializedTick: slot1.rightMostInitializedTick
                })
            );
        } else {
            sharesRatio = ticks.getSharesRatioInside(
                Tick.SharesRatioInsideParams({
                    pnl: slot0.pnl,
                    positionTick: params.positionTick,
                    currentTick: slot1.tick
                })
            );
        }

        uint128 netShares = FixedPointMathLib
            .mulDivDown(params.liquidityDelta, RAY, sharesRatio)
            .u128();
        // update the netShares amount in that tick
        ticks.update(netShares, params.positionTick, true);

        (liquidityActive, liquidityInactive) = TickMath.getAmounts(
            params.positionTick,
            slot1.tick,
            int96(params.liquidityDelta), // @todo check this casting out
            slot1.tickRatio
        );

        if (params.positionTick > slot1.rightMostInitializedTick) {
            slot1.rightMostInitializedTick = params.positionTick;
        }
        if (params.positionTick < slot1.leftMostInitializedTick) {
            slot1.leftMostInitializedTick = params.positionTick;
        }

        // update the position with the net shares added to the tick
        position.update(int128(netShares), sharesRatio);
    }

    struct BurnPositionParams {
        // the address that owns the position
        address owner;
        // the tick of the position
        int24 positionTick;
        /// @notice the amount of shares to remove
        uint128 shares;
    }

    function burnPosition(
        ISynthState.Slot0 storage slot0,
        ISynthState.Slot1 storage slot1,
        mapping(bytes32 => Position.Info) storage positions,
        mapping(int24 => Tick.Info) storage ticks,
        mapping(int16 => uint) storage tickBitmap,
        BurnPositionParams memory params
    ) external returns (int96 liquidityActive, int96 liquidityInactive) {
        ticks.update(params.shares, params.positionTick, false);

        Position.Info storage position = positions.get(
            params.owner,
            params.positionTick
        );

        uint128 sharesRatio = ticks.getSharesRatioInside(
            Tick.SharesRatioInsideParams({
                pnl: slot0.pnl,
                positionTick: params.positionTick,
                currentTick: slot1.tick
            })
        );

        position.update(-int128(params.shares), sharesRatio);

        uint96 liquidityDelta = FixedPointMathLib
            .mulDivDown(params.shares, sharesRatio, RAY)
            .u96();

        (liquidityActive, liquidityInactive) = TickMath.getAmounts(
            params.positionTick,
            slot1.tick,
            -int96(liquidityDelta),
            slot1.tickRatio
        );

        // if the tick has no more netShares, unflip it
        if (ticks[params.positionTick].netShares == 0) {
            tickBitmap.flipTick(params.positionTick);
        }
    }
}
