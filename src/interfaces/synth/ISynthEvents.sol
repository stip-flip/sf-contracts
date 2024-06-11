// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Events emitted by a pool
/// @notice Contains all events emitted by the pool
interface ISynthEvents {
    /// @notice Emitted when a position's liquidity is asked to be removed
    /// @param owner The owner of the position for which the shares are burnt
    /// @param positionTick The upper tick of the position
    /// @param round The round at which the burn was asked
    /// @param claimer The address that is allowed to claim the burn at the next round
    /// @param sharesBurned The amount of shares to burn
    event Burn(
        address indexed owner,
        int24 indexed positionTick,
        uint64 indexed round,
        address claimer,
        uint128 sharesBurned
    );

    /// @notice Emitted when a position's liquidity is claimed
    /// @param owner The address that own the position
    /// @param positionTick The tick of the position
    /// @param round The round at which the burn was asked
    /// @param recipient The address that receives the dividends of the positions
    event ClaimedBurn(
        address indexed owner,
        int24 indexed positionTick,
        uint64 indexed round,
        address recipient
    );

    /// @notice Emitted when liquidity is asked to be minted for a position
    /// @param sender The address that minted the liquidity
    /// @param positionTick The tick of the position
    /// @param round The round at which the mint was asked
    /// @param claimer The address that is allowed to claim the mint at the next round
    /// @param amountSent The amount of liquidity minted
    event Mint(
        address indexed sender,
        int24 indexed positionTick,
        uint64 indexed round,
        address claimer,
        uint96 amountSent
    );

    /// @notice Emitted when a position's liquidity is claimed
    /// @param minter The address that minted the liquidity
    /// @param positionTick The tick of the position
    /// @param round The round at which the mint was asked
    /// @param recipient The address that will receives the position
    event ClaimedMint(
        address indexed minter,
        int24 indexed positionTick,
        uint64 indexed round,
        address recipient
    );

    /// @notice Emitted when fees are collected by the owner of a position
    /// @dev Collect events may be emitted with zero amount0 and amount1 when the caller chooses not to collect fees
    /// @param owner The owner of the position for which fees are collected
    /// @param positionTick The tick of the position
    /// @param recipient The address that receives the collected token fees
    /// @param amount The amount of token fees collected
    event Collect(
        address indexed owner,
        int24 indexed positionTick,
        address recipient,
        uint96 amount
    );

    /// @notice Emitted by the pool for any swaps between token0 and token1
    /// @param liquidityMoved The delta of the token0 balance of the pool
    /// @param tick The log base 1.0001 of price of the pool after the swap
    event Swap(uint96 liquidityMoved, int24 tick);

    /// @notice Emitted when a trade is entered
    /// @param sender The address that entered the trade
    /// @param round The round at which the trade was entered
    /// @param claimer The address that is allowed to claim the trade at the next round
    /// @param amountSent The amount of liquidity sent
    event Entered(
        address indexed sender,
        uint64 indexed round,
        address indexed claimer,
        uint96 amountSent
    );

    /// @notice Emitted when a trade entry is claimed
    /// @param sender The address that entered the trade
    /// @param recipient The address that receives the trade
    /// @param round The round at which the trade was entered
    event ClaimedEnter(
        address indexed sender,
        address indexed recipient,
        uint64 indexed round
    );

    /// @notice Emitted when a trade is exited
    /// @param exitee The address that exited the trade
    /// @param round The round at which the trade was exited
    /// @param claimer The address that is allowed to claim the exit at the next round
    /// @param sharesLocked The amount of shares locked
    event Exited(
        address indexed exitee,
        uint64 indexed round,
        address claimer,
        uint128 sharesLocked
    );

    /// @notice Emitted when a trade exit is claimed
    /// @param exitee The address that exited the trade
    /// @param recipient The address that receives the trade
    /// @param round The round at which the trade was exited
    event ClaimedExit(
        address indexed exitee,
        address indexed recipient,
        uint64 indexed round
    );
}
