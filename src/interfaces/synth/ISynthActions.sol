// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import '../../logic/Claim.sol';

/// @title Permissionless pool actions
/// @notice Contains pool methods that can be called by anyone
interface ISynthActions {
    /// @notice Adds liquidity for the given recipient/tickLower/tickUpper position, create or update the position
    /// @param positionTick The tick of the position in which to add liquidity
    /// @param claimer The address that will be able to claim the mint at the next round
    function mint(int24 positionTick, address claimer) external payable;

    function claimMint(
        uint64 round,
        bytes32 tickAndFrom,
        address recipient
    ) external;

    // function claimMintFrom(uint64 round, address from) external;

    /// @notice Burn liquidity from the sender and account tokens owed for the liquidity to the position
    /// @dev Fees must be collected separately via a call to #collect
    /// @param positionTick The tick of the position for which to burn liquidity
    /// @param shares_ How much shares to burn
    /// @param claimer Allow a claimer to do the claim in your behalf
    function burn(
        int24 positionTick,
        uint128 shares_,
        address claimer
    ) external;

    function claimBurn(
        uint64 round,
        bytes32 tickAndFrom,
        address recipient
    ) external;

    // function claimBurnFrom(uint64 round, address from) external;

    function claimAllPosition(
        uint64[] calldata mints_,
        int24[] calldata mintTicks,
        uint64[] calldata burns_,
        int24[] calldata burnTicks,
        address recipient
    ) external;

    function claimAllPosition(
        bytes32[] calldata enterees,
        bytes32[] calldata exitees,
        uint64 round,
        uint96 claimFee
    ) external returns (ClaimLogic.ClaimPositionState memory);

    function claimAllSwap(
        uint64[] calldata entries_,
        uint64[] calldata exits_,
        address recipient
    ) external;

    function claimAllSwap(
        address[] calldata enterees,
        address[] calldata exitees,
        uint64 round,
        uint96 claimFee
    ) external;

    function enter(address claimer) external payable;

    function claimEnter(uint64 round, address recipient) external;

    // function claimEnterFrom(uint64 round, address from) external;

    function exit(uint amount, address claimer) external;

    function claimExit(uint64 round, address recipient) external;

    function transferShares(address to, uint shares_) external returns (bool);

    function transferSharesFrom(
        address from,
        address to,
        uint shares_
    ) external returns (bool);
}
