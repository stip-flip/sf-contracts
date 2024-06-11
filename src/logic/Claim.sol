// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.6;

import '../libraries/SafeCast.sol';
import '../libraries/FixedPointMathLib.sol';
import '../libraries/Constants.sol';
import '../libraries/TransferHelper.sol';
import '../libraries/Position.sol';
import '../libraries/Pack.sol';

import '../interfaces/synth/ISynthState.sol';

import './Position.sol';

library ClaimLogic {
    using SafeCast for uint;
    using SafeCast for int;

    using Pack for int24;
    using Pack for bytes32;

    event ClaimedMint(
        address indexed owner,
        int24 indexed positionTick,
        uint64 indexed round,
        address recipient
    );

    event ClaimedBurn(
        address indexed owner,
        int24 indexed positionTick,
        uint64 indexed round,
        address recipient
    );

    event ClaimedEnter(
        address indexed sender,
        address indexed recipient,
        uint64 indexed round
    );

    event ClaimedExit(
        address indexed sender,
        address indexed recipient,
        uint64 indexed round
    );

    struct ClaimPositionState {
        int96 amountToSwap;
        uint96 botFees;
        bytes32 tickAndOwner;
        uint64 lastRound;
        uint64 round;
    }

    struct MintParams {
        uint96 amountSent;
        uint96 claimFee;
    }

    /// @notice Mint a position, check the round, the amount sent and the fees, mint the position and keep track of the fees and amountToSwap in the state struct
    /// @dev this function is meant to be used in a loop containing many mints, the amount of shares to mint and liquidity to swap is kept in the state
    /// @param slot0 the slot0 storage of the synth
    /// @param slot1 the slot1 storage of the synth
    /// @param positions the positions mapping of the synth
    /// @param ticks the ticks mapping of the synth
    /// @param tickBitmap the tickBitmap mapping of the synth
    /// @param state the current state of the claim (claimAll)
    /// @param p the different mint parameters (MintParams)
    function mint(
        ISynthState.Slot0 storage slot0,
        ISynthState.Slot1 storage slot1,
        mapping(bytes32 => Position.Info) storage positions,
        mapping(int24 => Tick.Info) storage ticks,
        mapping(int16 => uint) storage tickBitmap,
        ClaimPositionState memory state,
        MintParams memory p
    ) external returns (ClaimPositionState memory) {
        (int24 tick, address owner) = state.tickAndOwner.unpack();
        if (p.amountSent == 0) return state;

        if (p.amountSent < p.claimFee) {
            state.botFees += p.amountSent;
            return state;
        } else {
            p.amountSent -= p.claimFee;
            state.botFees += p.claimFee;
        }

        // if the current round is higher than the entered round + 1, refund and cancel the mint
        if (state.lastRound != (state.round + 1)) {
            TransferHelper.safeTransferETH(owner, p.amountSent);
            emit ClaimedMint(owner, tick, state.round, owner);
            return state;
        }
        // if we deposited in the active range, liquidityActive is positive, 0 otherwise
        (, int96 liquidityActive, ) = PositionLogic.mintPosition(
            slot0,
            slot1,
            positions,
            ticks,
            tickBitmap,
            PositionLogic.MintPositionParams({
                owner: owner,
                positionTick: tick,
                liquidityDelta: p.amountSent
            })
        );

        state.amountToSwap -= liquidityActive;

        emit ClaimedMint(owner, tick, state.round, owner);

        return state;
    }

    struct BurnParams {
        uint128 shares;
        uint96 claimFee;
    }

    /// @notice Burn a position, verify the round, burn the shares and take the fees (bot fees)
    /// @dev this function is meant to be used in a loop containing many burns, the amount to swap and shares to mint is kept in the state
    /// @param slot0 the slot0 storage of the synth
    /// @param slot1 the slot1 storage of the synth
    /// @param positions the positions mapping of the synth
    /// @param ticks the ticks mapping of the synth
    /// @param tickBitmap the tickBitmap mapping of the synth
    /// @param state the current state of the claim (claimAll)
    /// @param p the different burn parameters (BurnParams)
    function burn(
        ISynthState.Slot0 storage slot0,
        ISynthState.Slot1 storage slot1,
        mapping(bytes32 => Position.Info) storage positions,
        mapping(int24 => Tick.Info) storage ticks,
        mapping(int16 => uint) storage tickBitmap,
        ClaimPositionState memory state,
        BurnParams memory p
    ) external returns (ClaimPositionState memory) {
        (int24 tick, address owner) = state.tickAndOwner.unpack();

        if (p.shares == 0) return state;

        if (state.lastRound != (state.round + 1)) {
            emit ClaimedBurn(owner, tick, state.round, owner);
            return state;
        }

        (int96 liquidityActive, int96 liquidityInactive) = PositionLogic
            .burnPosition(
                slot0,
                slot1,
                positions,
                ticks,
                tickBitmap,
                PositionLogic.BurnPositionParams({
                    owner: owner,
                    positionTick: tick,
                    shares: p.shares
                })
            );

        uint96 totalEarned = uint96(-liquidityActive - liquidityInactive);

        state.amountToSwap -= liquidityActive;

        if (totalEarned > p.claimFee) {
            TransferHelper.safeTransferETH(owner, totalEarned - p.claimFee);
            state.botFees += p.claimFee;
        } else {
            state.botFees += totalEarned;
        }

        emit ClaimedBurn(owner, tick, state.round, owner);

        return state;
    }

    /// @notice Aggregate all the claim (mint and burn) in one call

    struct ClaimState {
        uint64 lastRound;
        uint96 oracleFees;
        uint96 swapFees;
        uint96 botFees;
        int96 amountToSwap;
        int96 lpPnL;
        int128 sharesDiff;
    }

    struct EnterParams {
        uint64 round;
        address from;
        address recipient;
        uint96 amountSent;
        uint96 totalLiquidities;
        uint128 totalShares;
        uint96 poolDebt;
        uint24 fee;
        uint24 oracleFee;
    }

    /// @notice Perform a claim on an enter, verify the round, take the claim fees and mint the shares
    /// @dev this function is used in a loop containing many claims, it performs a claim on an enter, take the claim fees and mint the shares check the allowance and keep a state that will be shared between all the claims
    /// @param entries the entries mapping
    /// @param shares the shares mapping
    /// @param averageSharesValue the averageSharesValue mapping
    /// @param state The current state of the claim (claimAll)
    /// @param p the different function parameters
    /// @param claimFee the fee to be taken from the claim amount
    function enter(
        mapping(uint64 => mapping(address => uint96)) storage entries,
        mapping(address => uint) storage shares,
        mapping(address => uint) storage averageSharesValue,
        ClaimState memory state,
        EnterParams memory p,
        uint96 claimFee
    ) external returns (ClaimState memory) {
        if (p.amountSent <= claimFee) {
            state.botFees += p.amountSent;
            p.amountSent = 0;
            // bail out
            return state;
        } else {
            p.amountSent -= claimFee;
            state.botFees += claimFee;
        }
        // if the current round is higher than the entered round + 1, refund and cancel the entry
        if (state.lastRound != (p.round + 1)) {
            TransferHelper.safeTransferETH(p.from, p.amountSent);
            delete entries[p.round][p.from];
            emit ClaimedEnter(p.from, p.from, p.round);
            return state;
        }
        (
            uint128 sharesMinted,
            int96 amountToSwap,
            uint96 swapFees_,
            uint96 oracleFees_
        ) = compoundEnter(entries, shares, averageSharesValue, p);
        state.amountToSwap += amountToSwap;
        state.swapFees += swapFees_;
        state.oracleFees += oracleFees_;
        state.sharesDiff += int128(sharesMinted);

        emit ClaimedEnter(p.from, p.from, p.round);

        return state;
    }

    /// @notice Isolated enter logic, compute and mint the shares, the average shares value, the amount to swap, the swap fees and the oracle fees, delete the entry to avoid double claiming
    /// @param entries the entries mapping
    /// @param shares the shares mapping
    /// @param averageSharesValue the averageSharesValue mapping
    /// @param p the different function parameters (EnterParams)
    function compoundEnter(
        mapping(uint64 => mapping(address => uint96)) storage entries,
        mapping(address => uint) storage shares,
        mapping(address => uint) storage averageSharesValue,
        EnterParams memory p
    )
        public
        returns (
            uint128 sharesMinted,
            int96 amountToSwap,
            uint96 swapFees,
            uint96 oracleFees
        )
    {
        swapFees = FixedPointMathLib.mulDivDown(p.amountSent, p.fee, 1e4).u96();

        oracleFees = FixedPointMathLib
            .mulDivDown(swapFees, p.oracleFee, 1e4)
            .u96();

        p.amountSent -= swapFees;

        // remove the oracleFees from the swapFees, for not having them aggregating in the pool
        swapFees -= oracleFees;
        // amount to swap is the amountSent minus the fees, minus the swapFees that will coumpound in the previous liquidity
        amountToSwap += int96(p.amountSent) - int96(swapFees);

        if (p.totalShares == 0) {
            sharesMinted = p.amountSent;
        } else {
            sharesMinted = FixedPointMathLib
                .mulDivDown(
                    p.amountSent,
                    p.totalShares,
                    p.totalLiquidities + p.poolDebt
                )
                .u128();
        }

        averageSharesValue[p.recipient] = averageSharesValueOnEnter(
            shares,
            averageSharesValue,
            p.from,
            sharesMinted,
            p.amountSent
        );

        shares[p.recipient] += sharesMinted;

        delete entries[p.round][p.from];
    }

    /// @notice Re-compute the average shares value on enter for a given address
    /// @param shares the shares mapping
    /// @param averageSharesValue the averageSharesValue mapping
    /// @param to the address to compute the average shares value for
    /// @param sharesMinted the amount of shares minted
    /// @param amountSent the amount sent
    function averageSharesValueOnEnter(
        mapping(address => uint) storage shares,
        mapping(address => uint) storage averageSharesValue,
        address to,
        uint sharesMinted,
        uint amountSent
    ) internal view returns (uint) {
        return
            (shares[to] * averageSharesValue[to] + amountSent * WAD) /
            (shares[to] + sharesMinted);
    }

    struct ExitParams {
        uint64 round;
        uint128 shares;
        address from;
        uint96 sv;
        uint96 asv;
        uint96 totalLiquidities;
        uint96 poolDebt;
        uint24 fee;
        uint24 oracleFee;
    }

    /// @notice Perform a claim on an exit, verify the round, take the claim fees and burn the shares, keep track of the pnl, amount to swap and fees in the state structure, delete the exit entry
    /// @dev this function is used in a loop containing many claims, it performs a claim on an exit, take the claim fees and burn the shares check the allowance and keep a state that will be shared between all the claims
    /// @param exits the exits mapping
    /// @param shares the shares mapping
    /// @param state the current state of the claim (claimAll)
    /// @param p the different function parameters (ExitParams)
    /// @param claimFee the fee to be taken from the claim amount
    function exit(
        mapping(uint64 => mapping(address => uint128)) storage exits,
        mapping(address => uint) storage shares,
        ClaimState memory state,
        ExitParams memory p,
        uint96 claimFee
    ) external returns (ClaimState memory) {
        if (p.shares == 0) return state;

        state.sharesDiff -= int128(p.shares);

        // if the current round is higher than the entered round + 1, refund and cancel the exit
        if (state.lastRound != (p.round + 1)) {
            // refund the shares
            shares[p.from] += p.shares;
            delete exits[p.round][p.from];
            emit ClaimedExit(p.from, p.from, p.round);
            return state;
        }
        (
            int96 amountToSwap,
            int96 traderPnL,
            uint96 swapFees,
            uint96 oracleFees,
            uint96 totalEarned
        ) = compoundExit(exits, p);

        state.swapFees += swapFees;
        state.oracleFees += oracleFees;
        state.amountToSwap -= amountToSwap;
        state.lpPnL -= traderPnL;

        if (totalEarned > claimFee) {
            TransferHelper.safeTransferETH(p.from, totalEarned - claimFee);
            state.botFees += claimFee;
        } else {
            state.botFees += totalEarned;
        }

        emit ClaimedExit(p.from, p.from, p.round);

        return state;
    }

    /// @notice Compute all the values for the exit claim, delete the claim and return the values
    /// @param exits the exits mapping
    /// @param p the different function parameters (ExitParams)
    function compoundExit(
        mapping(uint64 => mapping(address => uint128)) storage exits,
        ExitParams memory p
    )
        public
        returns (
            int96 amountToSwap,
            int96 traderPnL,
            uint96 swapFees,
            uint96 oracleFees,
            uint96 totalEarned
        )
    {
        // apply the pool debt to the trader pnl
        traderPnL = FixedPointMathLib
            .iMulDivDown(
                int96(p.sv) - int96(p.asv),
                p.totalLiquidities,
                p.totalLiquidities + p.poolDebt
            )
            .i96();

        // apply the pool debt to the shares value
        uint96 svWithDebt = FixedPointMathLib
            .mulDivDown(
                p.sv,
                p.totalLiquidities,
                p.totalLiquidities + p.poolDebt
            )
            .u96();

        swapFees = FixedPointMathLib.mulDivDown(svWithDebt, p.fee, 1e4).u96();

        oracleFees = FixedPointMathLib
            .mulDivDown(swapFees, p.oracleFee, 1e4)
            .u96();

        totalEarned = uint96(int96(p.asv) + traderPnL - int96(swapFees));

        swapFees -= oracleFees;

        // amountToSwap is equal to the shares value (with debt), minus the swapFees (accumulated in the liquidities prior to the swap),
        // minus the traderPnL (also substracted from the liquidities prior to the swap)
        amountToSwap = int96(p.sv) + int96(swapFees) - traderPnL;

        delete exits[p.round][p.from];
    }
}
