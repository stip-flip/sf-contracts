// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0 <=0.8.20;

import './Constants.sol';
import './LiquidityMath.sol';
import './Tick.sol';
import './TickBitmap.sol';

/// @title Position
/// @notice Positions represent an owner address' liquidity inside a tick
/// @dev Positions store sharesRatio to keep track of the position value in liquidity
library Position {
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint);

    using SafeCast for uint;
    using SafeCast for int;

    // info stored for each user's position
    struct Info {
        // the amount of shares owned by this position
        uint128 shares;
        // the average shares ratio for the liquidity deposited
        uint128 sharesRatio;
    }

    /// @notice Returns the Info struct of a position, given an owner and position boundaries
    /// @param self The mapping containing all user positions
    /// @param owner The address of the position owner
    /// @param positionTick The tick at which this position becomes active
    /// @return position The position info struct of the given owners' position
    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 positionTick
    ) internal view returns (Position.Info storage position) {
        position = self[keccak256(abi.encodePacked(owner, positionTick))];
    }

    /// @notice Returns the Profit and Loss of a position
    /// @param self The individual position to calculate pnl for
    /// @param sharesRatio The average shares ratio accross all ticks for the liquidity deposited
    function pnl(
        Info storage self,
        uint128 sharesRatio
    ) internal view returns (int96) {
        if (self.sharesRatio == sharesRatio) {
            return 0;
        }

        return
            FixedPointMathLib
                .iMulDivDown(
                    int128(sharesRatio) - int128(self.sharesRatio),
                    self.shares,
                    RAY
                )
                .i96();
    }

    /// @notice Returns the Profit and Loss of a position
    /// @param positions The mapping containing all user positions
    /// @param ticks The mapping containing all tick information
    /// @param positionTick The tick at which this position becomes active
    /// @param owner The address of the position owner
    /// @param currentTick The current tick
    /// @param pnl_ The profit and loss of the position
    /// @return The profit and loss of the position
    function pnl(
        mapping(bytes32 => Position.Info) storage positions,
        mapping(int24 => Tick.Info) storage ticks,
        int24 positionTick,
        address owner,
        int24 currentTick,
        uint128 pnl_
    ) external view returns (int96) {
        Position.Info memory self = positions[
            keccak256(abi.encodePacked(owner, positionTick))
        ];
        uint128 sharesRatio = ticks.getSharesRatioInside(
            Tick.SharesRatioInsideParams({
                pnl: pnl_,
                currentTick: currentTick,
                positionTick: positionTick
            })
        );

        if (self.sharesRatio == sharesRatio) {
            return 0;
        }

        return
            FixedPointMathLib
                .iMulDivDown(
                    int128(sharesRatio) - int128(self.sharesRatio),
                    self.shares,
                    RAY
                )
                .i96();
    }

    /// @notice Returns the total value of a position
    function value(
        Info storage self,
        uint128 sharesRatio
    ) internal view returns (uint) {
        return
            uint(FixedPointMathLib.mulDivDown(self.shares, sharesRatio, RAY));
    }

    /// @notice Returns the total value of a position
    /// @param positions The mapping containing all user positions
    /// @param ticks The mapping containing all tick information
    /// @param positionTick The tick at which this position becomes active
    /// @param owner The address of the position owner
    /// @param currentTick The current tick
    /// @param pnl_ The profit and loss of the position
    /// @return The total value of the position
    function value(
        mapping(bytes32 => Position.Info) storage positions,
        mapping(int24 => Tick.Info) storage ticks,
        int24 positionTick,
        address owner,
        int24 currentTick,
        uint128 pnl_
    ) external view returns (uint96) {
        Position.Info memory self = positions[
            keccak256(abi.encodePacked(owner, positionTick))
        ];
        uint128 sharesRatio = ticks.getSharesRatioInside(
            Tick.SharesRatioInsideParams({
                pnl: pnl_,
                currentTick: currentTick,
                positionTick: positionTick
            })
        );

        return
            FixedPointMathLib.mulDivDown(sharesRatio, self.shares, RAY).u96();
    }

    /// @notice Update a position with the given liquidity delta, important note, the pnl is already applied to the liquidity delta
    /// @param self The individual position to update
    /// @param sharesDelta The change in pool liquidity as a result of the position update
    /// @param sharesRatio The average shares ratio accross all ticks for the liquidity deposited
    function update(
        Info storage self,
        int128 sharesDelta,
        uint128 sharesRatio
    ) internal {
        Info memory _self = self;
        // recompute the average sharesRatio of the positions liquidity given the new influx of liquidity
        if (sharesDelta > 0) {
            uint128 sd = uint128(sharesDelta);
            self.sharesRatio = (((uint(_self.shares) *
                uint(_self.sharesRatio)) + (uint(sd) * uint(sharesRatio))) /
                (_self.shares + sd)).u128();
        }

        self.shares = LiquidityMath.addDelta(_self.shares, sharesDelta).u128();
    }
}
