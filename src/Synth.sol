// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.6;

import './libraries/SafeCast.sol';
import './libraries/Tick.sol';
import './libraries/TickBitmap.sol';
import './libraries/Position.sol';
import './libraries/TransferHelper.sol';
import './libraries/TickMath.sol';
import './libraries/LiquidityMath.sol';
import './libraries/Permit.sol';
import './libraries/Pack.sol';
import './interfaces/IOracleView.sol';
import './interfaces/IERC20.sol';

import './logic/Enter.sol';
import './logic/Exit.sol';
import './logic/Swap.sol';
import './logic/Position.sol';
import './logic/Claim.sol';

contract Synth is ISynth, IERC20 {
    using TickMath for int24;
    using TickMath for int;
    using SafeCast for uint;
    using SafeCast for int;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using PositionLogic for Position.Info;

    /// @inheritdoc ISynthState
    Slot0 public override slot0;

    /// @inheritdoc ISynthState
    Slot1 public override slot1;

    /// @inheritdoc ISynthState
    Slot2 public override slot2;

    /// @notice the pool debt, ie the amount of liquidities that are not backed by collateral
    uint96 public override poolDebt;

    /// @notice on entry, keep track of the amount locked
    mapping(uint64 => mapping(address => uint96)) internal entries;

    /// @notice on exit, keep a track of the shares burned
    mapping(uint64 => mapping(address => uint128)) internal exits;

    /// @notice on mint, keep track of the amount locked and the tick: round => tickAndOwner => amount locked
    mapping(uint64 => mapping(bytes32 => uint96)) internal mints;

    /// @notice on burn, keep track of the amount burnt and the tick: round => tickAndOwner => shares burned
    mapping(uint64 => mapping(bytes32 => uint128)) internal burns;

    /// @notice Each user's shares
    mapping(address => uint) public shares;

    /// @notice The allowance for a claimer to claim the minted/burned shares of a given user, only valid for one round
    mapping(address => mapping(address => uint)) public override allowance;

    /// @notice the allowance for a claimer to claim the position of a given user, only valid for one round
    mapping(bytes32 => mapping(address => uint)) internal claimAllowance;

    /// @notice for each user on each mint/burn, we keep track of the average value of their shares, needed to compute the PnL
    mapping(address => uint) internal averageSharesValue;

    /// @notice the nonces for each permit signature
    mapping(address => uint) public nonces;

    /// @notice all ticks that have been initialized
    mapping(int24 => Tick.Info) internal ticks;

    /// @notice the bitmap of initialized ticks
    mapping(int16 => uint) internal tickBitmap;

    /// @notice the positions of each user
    mapping(bytes32 => Position.Info) internal positions;

    // immutable variables (not mark as such because of the upgradeable nature of the pool)

    /// @notice the oracle contract that will provide the price of the synth
    IOracleView public oracle;

    /// @notice the slot in the oracle that will be used to get the price of the synth
    uint8 public oracleSlot;

    /// @notice the synth is long or short
    bool public long;

    /// @notice the leverage of the synth
    IOracleView.Leverage public leverage;

    /// @notice the synth's name
    string public override name;

    /// @notice the synth's symbol
    string public override symbol;

    /// @notice the synth's description
    string public description;

    /// @notice the synth's decimals
    uint8 public override decimals;

    /// @notice the domain separator for the permit function
    bytes32 internal INITIAL_DOMAIN_SEPARATOR;

    /// @notice the time basis for the funding rate, ie tick 500 will be 5% per year
    uint64 internal constant FR_TIME_BASIS = 365 days; // a year

    /// @notice the fee of the synth, the swap fee on each swap, to be distributed to the LPs and the data providers
    uint24 public constant override FEE = 30; // 0.3% fee
    /// @notice the oracle fee, ie some of the swap fees will go to the oracle contract to be distributed to the data providers
    uint24 public constant override ORACLE_FEE = 30_00; // 30% of the swap fees goes to the data providers

    function initialize(
        address oracle_,
        uint8 oracleSlot_,
        string memory name_,
        string memory symbol_,
        string memory description_,
        bool long_,
        IOracleView.Leverage leverage_
    ) external {
        require(address(oracle) == address(0), 'AER');
        slot0.pnl = uint128(RAY);

        slot1.rightMostInitializedTick = TickMath.MIN_TICK + 1;
        slot1.leftMostInitializedTick = TickMath.MAX_TICK - 1;

        long = long_;
        leverage = leverage_;
        oracle = IOracleView(oracle_);
        oracleSlot = oracleSlot_;

        //@todo see if we should rather check the block, as timestamp can easily be manipulated
        slot2.lastUpdate = uint64(block.timestamp);
        slot2.lastPrice = getPrice();

        // this guarantee that the oracle is already intitalised, and current round is > 0
        require(slot2.lastPrice > 0, 'ORA');

        // initialise the pool as an ERC20
        name = name_;

        symbol = symbol_;

        decimals = 18;

        description = description_;

        INITIAL_DOMAIN_SEPARATOR = Permit.DOMAIN_SEPARATOR(name);
    }

    /// @notice get the last updated price submitted to the oracle, (not the last price of the pool)
    function getPrice() public view returns (uint64) {
        return oracle.lastPrice(oracleSlot, long, leverage);
    }

    /// @notice helper function to get someone's LP position
    /// @param positionTick the tick of the position
    /// @param owner the owner of the position
    function position(
        int24 positionTick,
        address owner
    ) external view returns (Position.Info memory) {
        return positions.get(owner, positionTick);
    }

    // function positionPnL(
    //     int24 positionTick,
    //     address owner
    // ) external view returns (int) {
    //     return positions.pnl(ticks, positionTick, owner, slot1.tick, slot0.pnl);
    // }

    /// @notice helper function to get the current value of a position
    /// @param positionTick the tick of the position
    /// @param owner the owner of the position
    function positionValue(
        int24 positionTick,
        address owner
    ) external view returns (uint) {
        return
            positions.value(ticks, positionTick, owner, slot1.tick, slot0.pnl);
    }

    /// @notice helper function to get the current value of a tick
    /// @param tick the tick of the position
    function tickValue(int24 tick) external view returns (uint) {
        return ticks.value(tick, slot1.tick, slot0.pnl);
    }

    /// @notice helper function to pack an int24 and an address into a bytes32
    /// @param _int24 the int24 to pack
    /// @param _address the address to pack
    function pack(
        int24 _int24,
        address _address
    ) public pure returns (bytes32 p) {
        p = Pack.pack(_int24, _address);
    }

    /// @notice helper function to unpack a byte32 into an int24 and an address
    /// @param _bytes the bytes32 to unpack
    function unpack(
        bytes32 _bytes
    ) public pure returns (int24 tick, address owner) {
        (tick, owner) = Pack.unpack(_bytes);
    }

    /// @notice claim all the minted and burned positions for a given round by a given user/owner
    /// @param mints_ the mints to claim
    /// @param mintTicks the ticks of the mints
    /// @param burns_ the burns to claim
    /// @param burnTicks the ticks of the burns
    /// @param recipient the recipient of the minted/burned positions
    function claimAllPosition(
        uint64[] calldata mints_,
        int24[] calldata mintTicks,
        uint64[] calldata burns_,
        int24[] calldata burnTicks,
        address recipient
    ) external override {
        for (uint i = 0; i < mints_.length; i++) {
            claimMint(mints_[i], pack(mintTicks[i], msg.sender), recipient);
        }
        for (uint i = 0; i < burns_.length; i++) {
            claimBurn(burns_[i], pack(burnTicks[i], msg.sender), recipient);
        }
    }

    /// @notice claim all the minted and burned positions for a given round by an allowed claimer
    /// @param mintees the minted positions to claim, packed as tickAndOwner
    /// @param burnees the burned positions to claim, packed as tickAndOwner
    /// @param round the round for which the claim is made
    /// @param claimFee the fixed fees to be collected by the sender, per claim
    function claimAllPosition(
        bytes32[] calldata mintees,
        bytes32[] calldata burnees,
        uint64 round,
        uint96 claimFee
    ) external override returns (ClaimLogic.ClaimPositionState memory state) {
        rebalance();
        state.lastRound = oracle.getLastRound(true);
        state.round = round;

        require(state.lastRound > state.round, 'LRR');

        for (uint i = 0; i < mintees.length; i++) {
            state.tickAndOwner = mintees[i];
            // check the allowance and bail out if the sender is not allowed for this round and position
            if (state.round != claimAllowance[state.tickAndOwner][msg.sender])
                continue;

            state = ClaimLogic.mint(
                slot0,
                slot1,
                positions,
                ticks,
                tickBitmap,
                state,
                ClaimLogic.MintParams({
                    amountSent: mints[round][state.tickAndOwner],
                    claimFee: claimFee
                })
            );
            // delete the mints to avoid double claiming
            delete mints[state.round][state.tickAndOwner];
        }

        for (uint i = 0; i < burnees.length; i++) {
            state.tickAndOwner = burnees[i];
            if (round != claimAllowance[state.tickAndOwner][msg.sender])
                continue;

            state = ClaimLogic.burn(
                slot0,
                slot1,
                positions,
                ticks,
                tickBitmap,
                state,
                ClaimLogic.BurnParams({
                    shares: burns[round][state.tickAndOwner],
                    claimFee: claimFee
                })
            );

            // delete the burns to avoid double claiming
            delete burns[round][state.tickAndOwner];
        }

        slot0.totalLiquidities = uint96(
            int96(slot0.totalLiquidities) - state.amountToSwap
        );

        _swapWithDebt(int96(poolDebt) + state.amountToSwap);

        // send the bot fees to the bot (claimer)
        if (state.botFees > 0) {
            TransferHelper.safeTransferETH(msg.sender, state.botFees);
        }
    }

    /// @notice register a mint to be claimed at the next round
    /// @param positionTick the tick of the position
    /// @param claimer the address that will also be able to claim the mint later on (if none set to msg.sender)
    function mint(
        int24 positionTick,
        address claimer
    ) external payable override {
        require(msg.value > 0, 'NES');

        positionTick.checkTick();

        uint96 amountSent = uint96(msg.value);

        uint64 oracleRound = oracle.getRound(true);

        bytes32 packed = pack(positionTick, msg.sender);

        // lock the amount sent
        mints[oracleRound][packed] += amountSent;

        if (claimer != msg.sender) {
            claimAllowance[packed][claimer] = oracleRound;
        }

        emit Mint(msg.sender, positionTick, oracleRound, claimer, amountSent);
    }

    /// @notice claim the minted position for a given round, create the position, swap any amount needed, delete the mint entry
    /// @param round the round at which the mint was made
    /// @param tickAndFrom the tick and the owner of the mint packed in a bytes32
    /// @param recipient the recipient of the minted shares
    function claimMint(
        uint64 round,
        bytes32 tickAndFrom,
        address recipient
    ) public override {
        (int24 positionTick, address from) = unpack(tickAndFrom);
        if (from != msg.sender) {
            uint roundAllowed = claimAllowance[tickAndFrom][msg.sender];
            require(roundAllowed == round, 'NAR');
        }
        uint96 amountSent = mints[round][tickAndFrom];
        require(amountSent > 0, 'NES');

        uint64 lastRound = oracle.getLastRound(true);

        require(lastRound > round, 'NPR');
        // if the current round is higher than the entered round + 1, refund and cancel the entry
        if (lastRound != (round + 1)) {
            // pay back the locked eth
            TransferHelper.safeTransferETH(recipient, amountSent);
            // delete the mints to avoid double claiming
            delete mints[round][tickAndFrom];

            emit ClaimedMint(msg.sender, positionTick, round, recipient);
            return;
        }

        // mark a checkpoint and update the pool to the last price if not already done
        rebalance();

        // if depositing in the active range, liquidityActive will be positive
        (, int96 liquidityActive, ) = PositionLogic.mintPosition(
            slot0,
            slot1,
            positions,
            ticks,
            tickBitmap,
            PositionLogic.MintPositionParams({
                owner: recipient,
                positionTick: positionTick,
                liquidityDelta: amountSent
            })
        );

        // depositing in the active range will increase the total liquidities...
        slot0.totalLiquidities += uint96(liquidityActive);

        // ...that will in turn be decreased by the swap
        _swapWithDebt(int96(poolDebt) - liquidityActive);

        // delete the mint to avoid double claiming
        delete mints[round][tickAndFrom];

        emit ClaimedMint(msg.sender, positionTick, round, recipient);
    }

    /// @notice register a burn to be claimed at the next round
    /// @param positionTick the tick of the position
    /// @param shares_ the amount of shares to burn
    /// @param claimer the address that will also be able to claim the burn later on (if none set to msg.sender)
    function burn(
        int24 positionTick,
        uint128 shares_,
        address claimer
    ) external override {
        uint64 oracleLastRound = oracle.getRound(true);
        // get the position that is being burnt
        Position.Info memory position_ = positions.get(
            msg.sender,
            positionTick
        );
        if (shares_ == 0) shares_ = position_.shares;
        require(position_.shares >= shares_, 'NES');
        bytes32 packed = pack(positionTick, msg.sender);
        // lock the amount sent
        burns[oracleLastRound][packed] = shares_;

        if (claimer != msg.sender) {
            claimAllowance[packed][claimer] = oracleLastRound;
        }

        emit Burn(msg.sender, positionTick, oracleLastRound, claimer, shares_);
    }

    /// @notice claim the burned position for a given round, verify the sender, the round, burn the position, swap any amount needed, delete the burn entry
    /// @param round the round at which the burn was asked
    /// @param tickAndFrom the tick and the owner of the burn packed in a bytes32
    /// @param recipient the recipient of the burned shares value in ETC
    function claimBurn(
        uint64 round,
        bytes32 tickAndFrom,
        address recipient
    ) public override {
        (int24 positionTick, address from) = unpack(tickAndFrom);
        if (from != msg.sender) {
            uint roundAllowed = claimAllowance[tickAndFrom][msg.sender];
            require(roundAllowed == round, 'NAR');
        }
        uint128 shares_ = burns[round][tickAndFrom];
        require(shares_ > 0, 'NES');

        uint64 lastRound = oracle.getLastRound(true);

        require(lastRound > round, 'NPR');

        if (lastRound != (round + 1)) {
            delete burns[round][tickAndFrom];
            return;
        }

        // mark a checkpoint and update the pool to the last price if not already done
        rebalance();

        // if removing some liquidity active, liquidityActive will be negative
        (int96 liquidityActive, int96 liquidityInactive) = PositionLogic
            .burnPosition(
                slot0,
                slot1,
                positions,
                ticks,
                tickBitmap,
                PositionLogic.BurnPositionParams({
                    owner: msg.sender,
                    positionTick: positionTick,
                    shares: shares_
                })
            );

        // we can't secure more liquidities than the liquidity active before the burn
        // this is to avoid rounding error that could happen in burnPosition method
        if (uint96(-liquidityActive) > slot0.totalLiquidities) {
            liquidityActive = -int96(slot0.totalLiquidities);
        }

        // depositing in the active range will decrease the total liquidities...
        slot0.totalLiquidities = uint96(
            int96(slot0.totalLiquidities) - liquidityActive
        );

        // ...that will in turn be increased by the swap
        _swapWithDebt(int96(poolDebt) - liquidityActive);

        TransferHelper.safeTransferETH(
            recipient,
            uint96(-liquidityInactive) + uint96(-liquidityActive)
        );

        delete burns[round][tickAndFrom];

        emit ClaimedBurn(from, positionTick, round, recipient);
    }

    /// @notice claim a batch of swap (entry/exit), only callable by the actual swap owner
    /// @param entries_ the entries to claim
    /// @param exits_ the exits to claim
    /// @param recipient the recipient of the claimed shares value in ETC
    function claimAllSwap(
        uint64[] calldata entries_,
        uint64[] calldata exits_,
        address recipient
    ) external override {
        for (uint i = 0; i < entries_.length; i++) {
            claimEnter(entries_[i], recipient);
        }
        for (uint i = 0; i < exits_.length; i++) {
            claimExit(exits_[i], recipient);
        }
    }

    /// @notice used to bundle multiple entries/exits in a single call
    /// the advantage is that we can avoid doing a swap for each trade and have it done once for all trades
    /// then mint/burn the shares for each trader
    /// @param enterees the address of all round enterers
    /// @param exitees the address of all round exiters
    /// @param round the round for which the swap were asked
    /// @param claimFee the fixed fees to be collected by the sender, per claim
    function claimAllSwap(
        address[] calldata enterees,
        address[] calldata exitees,
        uint64 round,
        uint96 claimFee
    ) external override {
        ClaimLogic.ClaimState memory state;

        state.lastRound = oracle.getLastRound(false);

        // first of all rebalance the pool
        rebalance();

        for (uint i = 0; i < enterees.length; i++) {
            address from = enterees[i];
            if (claimAllowance[bytes20(from)][msg.sender] != round) return;
            state = ClaimLogic.enter(
                entries,
                shares,
                averageSharesValue,
                state,
                ClaimLogic.EnterParams({
                    round: round,
                    from: from,
                    recipient: from,
                    amountSent: entries[round][from],
                    totalLiquidities: slot0.totalLiquidities,
                    totalShares: slot2.totalShares,
                    poolDebt: poolDebt,
                    fee: FEE,
                    oracleFee: ORACLE_FEE
                }),
                claimFee
            );
        }
        for (uint i = 0; i < exitees.length; i++) {
            address from = exitees[i];
            if (claimAllowance[bytes20(from)][msg.sender] != round) return;

            uint128 shares_ = exits[round][from];

            // not using sharesValueWithRebalance because we just rebalanced
            uint96 sv = uint96(sharesValue(shares_));

            uint96 asv = uint96((shares_ * averageSharesValue[from]) / WAD);

            state = ClaimLogic.exit(
                exits,
                shares,
                state,
                ClaimLogic.ExitParams({
                    round: round,
                    from: from,
                    shares: shares_,
                    sv: sv,
                    asv: asv,
                    totalLiquidities: slot0.totalLiquidities,
                    poolDebt: poolDebt,
                    fee: FEE,
                    oracleFee: ORACLE_FEE
                }),
                claimFee
            );
        }

        if (state.amountToSwap > 0) {
            _swapWithDebt(int96(poolDebt) + state.amountToSwap);
            Exit.accumulatePnL(
                slot0,
                slot1,
                ticks,
                state.lpPnL + int96(state.swapFees)
            );
        } else {
            Exit.accumulatePnL(
                slot0,
                slot1,
                ticks,
                state.lpPnL + int96(state.swapFees)
            );

            _swapWithDebt(int96(poolDebt) + state.amountToSwap);
        }
        if (state.sharesDiff > 0) {
            slot2.totalShares += uint128(state.sharesDiff);
        } else {
            slot2.totalShares -= uint128(-state.sharesDiff);
        }

        // erase all remaining 'dust' in totalLiquidities if totalShares == 0
        if (slot2.totalShares == 0) {
            slot0.totalLiquidities = 0;
        }

        if (state.oracleFees > 0) {
            TransferHelper.safeTransferETH(address(oracle), state.oracleFees);
        }

        if (state.botFees > 0) {
            TransferHelper.safeTransferETH(msg.sender, state.botFees);
        }
    }

    /// @notice preview the impact of an enter on the pool for the trader, and how much shares they will receive
    /// @param swapIn the amount of token to swap, if positive we swap liquidities else we swap the derivative
    function previewEnter(
        int swapIn
    ) external view returns (Enter.PreviewResult memory) {
        return
            Enter.preview(
                Enter.PreviewParams({
                    swapIn: swapIn,
                    decimals: oracle.getDecimals(oracleSlot),
                    fee: FEE,
                    price: getPrice()
                })
            );
    }

    /// @notice enter an OTC trade in the pool, this trade will be claimable at the next oracle price round
    /// @param claimer the address that will also be able to claim the enter later on (if none set to msg.sender)
    function enter(address claimer) external payable override {
        require(msg.value > 0, 'NES');
        uint96 amountSent = uint96(msg.value);
        uint64 oracleLastRound = oracle.getRound(false);
        // lock the amount sent
        entries[oracleLastRound][msg.sender] += amountSent;

        if (claimer != msg.sender) {
            claimAllowance[bytes20(msg.sender)][claimer] = oracleLastRound;
        }
        emit Entered(msg.sender, oracleLastRound, claimer, amountSent);
    }

    /// @notice claim the minted shares for a given round
    /// @dev pool ratio will not change, the shares diff between entry and settlement will be burned at the current pool ratio
    /// @param round the round for which the swap was asked
    /// @param recipient the recipient of the minted shares
    function claimEnter(uint64 round, address recipient) public override {
        uint96 amountSent = entries[round][msg.sender];
        require(amountSent > 0, 'NES');

        uint64 lastRound = oracle.getLastRound(false);

        require(lastRound > round, 'NPR');
        // if the current round is higher than the entered round + 1, refund and cancel the entry
        if (lastRound != (round + 1)) {
            TransferHelper.safeTransferETH(recipient, amountSent);
            delete entries[round][msg.sender];
            emit ClaimedEnter(msg.sender, recipient, round);
            return;
        }

        // mark a checkpoint and update the pool to the last price if not already done
        rebalance();

        (
            uint128 sharesMinted,
            int96 amountToSwap,
            uint96 swapFees,
            uint96 oracleFees
        ) = ClaimLogic.compoundEnter(
                entries,
                shares,
                averageSharesValue,
                ClaimLogic.EnterParams({
                    round: round,
                    from: msg.sender,
                    recipient: recipient,
                    amountSent: amountSent,
                    totalLiquidities: slot0.totalLiquidities,
                    totalShares: slot2.totalShares,
                    poolDebt: poolDebt,
                    fee: FEE,
                    oracleFee: ORACLE_FEE
                })
            );

        unchecked {
            slot2.totalShares += sharesMinted;
        }

        _swapWithDebt(int96(poolDebt) + int96(amountToSwap));

        // settle the swapFees in the pool
        Exit.accumulatePnL(slot0, slot1, ticks, int96(swapFees));

        if (oracleFees > 0) {
            TransferHelper.safeTransferETH(address(oracle), oracleFees);
        }

        emit ClaimedEnter(msg.sender, recipient, round);
    }

    /// @notice preview the impact of an exit on the pool for the trader, and how much liquidity/derivative they will burn/receive
    /// @param swapIn the amount of token to swap, if positive we swap the derivative in else we swap the liquidities in
    function previewExit(
        int swapIn
    ) external view returns (Exit.PreviewResult memory) {
        return
            Exit.preview(
                slot2,
                Exit.PreviewParams({
                    swapIn: swapIn,
                    sharesBalance: shares[msg.sender],
                    balance: balanceOf(msg.sender),
                    fee: FEE,
                    price: getPrice(),
                    totalLiquidities: slot0.totalLiquidities,
                    accFR: _accumulatedFR(),
                    poolDebt: poolDebt,
                    decimals: oracle.getDecimals(oracleSlot)
                })
            );
    }

    /// @notice exit the pool, burning the shares and receiving the collateral
    /// @param amount the amount of **derivative** to burn
    /// @param claimer the address that will also be able to actually claim the enter later on, if none, set to msg.sender
    function exit(uint amount, address claimer) public override {
        // passing amount 0 will fully exit the trader position
        if (amount == 0) amount = balanceOf(msg.sender);
        // translate the amount of derivatives to shares
        uint128 shares_ = FixedPointMathLib
            .mulDivDown(amount, shares[msg.sender], balanceOf(msg.sender))
            .u128();

        uint sharesBalance = shares[msg.sender];

        require(shares_ <= sharesBalance, 'NES');

        // remove the shares from the sender balance, don't touch the totalsupply (keep them in the pool for now)
        shares[msg.sender] -= shares_;

        uint64 oracleLastRound = oracle.getRound(false);

        // lock the shares
        exits[oracleLastRound][msg.sender] += shares_;

        if (claimer != msg.sender) {
            claimAllowance[bytes20(msg.sender)][claimer] = oracleLastRound;
        }

        emit Exited(msg.sender, oracleLastRound, claimer, shares_);
    }

    /// @notice claim the burned shares for a given round
    /// @param round the round for which the claim is made
    /// @param recipient the recipient of the burned shares value in ETC
    function claimExit(uint64 round, address recipient) public override {
        uint128 shares_ = exits[round][msg.sender];

        uint64 lastRound = oracle.getLastRound(false);

        require(shares_ > 0, 'NES');
        // if the lastround is not higher than round, the claim is too soon
        require(lastRound > round, 'NPR');

        // if the current round is higher than the entered round + 1, refund and cancel the exit
        if (lastRound != (round + 1)) {
            // refund the shares
            shares[msg.sender] += shares_;
            delete exits[round][msg.sender];
            emit ClaimedExit(msg.sender, recipient, round);
            return;
        }

        rebalance();

        // not using sharesValueWithRebalance because we just rebalanced
        uint96 sv = sharesValue(shares_).u96();

        uint96 asv = FixedPointMathLib
            .mulDivDown(shares_, averageSharesValue[msg.sender], WAD)
            .u96();

        (
            int96 amountToSwap,
            int96 traderPnL,
            uint96 swapFees,
            uint96 oracleSwapFees,
            uint96 totalEarned
        ) = ClaimLogic.compoundExit(
                exits,
                ClaimLogic.ExitParams({
                    round: round,
                    from: msg.sender,
                    shares: shares_,
                    sv: sv,
                    asv: asv,
                    totalLiquidities: slot0.totalLiquidities,
                    poolDebt: poolDebt,
                    fee: FEE,
                    oracleFee: ORACLE_FEE
                })
            );
        int96 liquidityProviderPnL = int96(swapFees) - traderPnL;

        // accumulate the trader PnL resulting from the price change
        Exit.accumulatePnL(slot0, slot1, ticks, liquidityProviderPnL);

        _swapWithDebt(int96(poolDebt) - amountToSwap);

        TransferHelper.safeTransferETH(recipient, totalEarned);

        if (oracleSwapFees > 0) {
            TransferHelper.safeTransferETH(address(oracle), oracleSwapFees);
        }

        // Cannot underflow because a user's shares balance
        // will never be larger than the total supply.
        unchecked {
            slot2.totalShares -= shares_;
            // if all shares have been burnt, take it as an opportunity to erase all dust leftovers in the pool
            if (slot2.totalShares == 0) {
                slot1.tickRatio = 0;
                slot0.totalLiquidities = 0;
            }
        }

        emit ClaimedExit(msg.sender, recipient, round);
    }

    /// @notice Compute how much liquidity are to be rebalanced given a new price and or accumulated FR the pool debt is automatically added to the amount to rebalance
    /// @param price the new price to rebalance the pool
    function _amountToRebalance(
        uint64 price
    ) internal view returns (int96 amountToRebalance) {
        // first apply the accumulatedFR to the totalLiquidities
        // the price impact can only be calculated once the accFR is deducted from the existing liquidities
        int96 accFR = _accumulatedFR();

        uint96 ttl = accFR > int96(slot0.totalLiquidities + poolDebt)
            ? 0
            : uint96(int96(slot0.totalLiquidities + poolDebt) - accFR);

        amountToRebalance = LiquidityMath.rebalance(
            ttl,
            slot2.lastPrice,
            price
        );

        amountToRebalance -= accFR;

        if (poolDebt != 0) {
            // try to secure the pool debt if any
            amountToRebalance += int96(poolDebt);
        }
    }

    /// @notice public function used to update price and accumulated FR of the pool on each rebalance, we'll try to repay the debt of the pool, if any can be called by anyone but only once per block
    function rebalance() public {
        // do nothing as no time has passed and consequently the price nor the accFR could have changed
        if (block.timestamp - slot2.lastUpdate == 0) {
            return;
        }
        uint64 price = getPrice();

        // mark a checkpoint before moving the liquidities around
        if (slot0.totalLiquidities == 0) {
            // if the pool is empty, no need to rebalance, no accumulated FR or price swing would be able to rebalance the pool
            // update lastPrice and lastUpdate as ttl will not be 0 after this rebalance, and this will serve as the previous checkpoint
            slot2.lastPrice = getPrice();
            slot2.lastUpdate = uint64(block.timestamp);
            return;
        }

        int96 amountToRebalance = _amountToRebalance(price);

        slot2.lastPrice = price;
        slot2.lastUpdate = uint64(block.timestamp);

        // we do have to swap on each update to avoid inconsistencies with the shares value
        _swapWithDebt(amountToRebalance);
    }

    /// @notice internal utility function that will preform a swap and keep accounting of the pool debt as well
    /// @param amountToSwap the amount of liquidities to swap, the amountToSwap is concatenated with the current debt hence 'swapWithDebt'
    function _swapWithDebt(int96 amountToSwap) internal {
        if (amountToSwap == 0) {
            //if the swap result in 0 liquidity to move, the debt has been resolved
            if (poolDebt != 0) {
                poolDebt = 0;
            }
        }
        if (amountToSwap > 0) {
            // swapping left to right
            uint96 liquidityMoved = SwapLogic.swap(
                slot0,
                slot1,
                ticks,
                tickBitmap,
                SwapLogic.SwapParams({
                    amountToSwap: amountToSwap,
                    frLimit: slot1.rightMostInitializedTick.iToFR()
                })
            );

            if (liquidityMoved != uint96(amountToSwap)) {
                slot0.totalLiquidities += liquidityMoved;
                poolDebt = uint96(amountToSwap) - liquidityMoved;
            } else {
                slot0.totalLiquidities += liquidityMoved;
                poolDebt = 0;
            }
        } else if (amountToSwap < 0) {
            //if the swap result in a release of active liquidities, the debt has been resolved
            if (poolDebt != 0) {
                poolDebt = 0;
            }
            // release the added liquidities, swapping right to left
            uint96 liquidityMoved = SwapLogic.swap(
                slot0,
                slot1,
                ticks,
                tickBitmap,
                SwapLogic.SwapParams({
                    amountToSwap: amountToSwap,
                    frLimit: slot1.leftMostInitializedTick.iToFR()
                })
            );
            slot0.totalLiquidities -= liquidityMoved;
        }
    }

    /// @notice compute the accumulated FR since the last update
    /// do not take into account the pool debt, which is not to be considered as a liquidity
    function _accumulatedFR() internal view returns (int96 frAccumulated) {
        // compute the fr from the tick
        int80 fr = slot1.tick.iToFR();
        frAccumulated = FixedPointMathLib
            .iMulDivDown(
                fr * int(block.timestamp - slot2.lastUpdate),
                slot0.totalLiquidities,
                FR_TIME_BASIS * 1e4 * TickMath.FR_PRECISION
            )
            .i96();
    }

    /// @notice return the current user PnL
    /// @param user the address of the user
    // function traderPnL(address user) public view returns (int) {
    //     return
    //         int(sharesValueWithRebalance(shares[user])) -
    //         int(
    //             FixedPointMathLib.mulDivDown(
    //                 averageSharesValue[user],
    //                 shares[user],
    //                 1e18
    //             )
    //         );
    // }

    /// @notice return the balance of a trader, expressed in derivatives
    /// @param owner the address of the user balance
    function balanceOf(address owner) public view override returns (uint) {
        return
            FixedPointMathLib.mulDivDown(
                sharesValueWithRebalance(shares[owner]),
                10 ** oracle.getDecimals(oracleSlot),
                getPrice()
            );
    }

    /// @notice return the total supply of the pool, expressed in derivatives
    function totalSupply() public view returns (uint) {
        return
            FixedPointMathLib.mulDivDown(
                sharesValueWithRebalance(slot2.totalShares),
                10 ** oracle.getDecimals(oracleSlot),
                getPrice()
            );
    }

    /// @notice approve a spender to spend a certain amount of shares on behalf of the owner
    /// @param spender the address of the spender
    /// @param shares_ the amount of shares to approve
    function approve(
        address spender,
        uint shares_
    ) public override returns (bool) {
        allowance[msg.sender][spender] = shares_;

        emit Approval(msg.sender, spender, shares_);

        return true;
    }

    /// @notice get the shares value of a given amount
    /// @param shares_ the amount of shares to convert
    /// @return the value of the shares
    function sharesValue(uint shares_) internal view returns (uint) {
        if (slot2.totalShares == 0) return 0;
        return
            FixedPointMathLib.mulDivDown(
                shares_,
                slot0.totalLiquidities + poolDebt,
                slot2.totalShares
            );
    }

    /// @notice get the shares value, while applying a virtual rebalancing to the pool, ie updating the accumulated FR and price change
    /// @param shares_ the amount of shares to convert
    /// @return the value of the shares
    function sharesValueWithRebalance(
        uint shares_
    ) public view returns (uint96) {
        if (slot2.totalShares == 0) return 0;

        uint64 price = getPrice();

        int96 amountToRebalance = _amountToRebalance(price);

        return
            FixedPointMathLib
                .mulDivDown(
                    shares_,
                    uint96(int96(slot0.totalLiquidities) + amountToRebalance),
                    slot2.totalShares
                )
                .u96();
    }

    /// @notice transfer an amount of derivative from msg.sender to another address
    /// @param to the address of the recipient
    /// @param amount the amount of derivative to transfer
    function transfer(address to, uint amount) public override returns (bool) {
        // translate the amount passed in to shares
        uint shares_ = FixedPointMathLib.mulDivDown(
            amount,
            shares[msg.sender],
            balanceOf(msg.sender)
        );

        return transferShares(to, shares_);
    }

    /// @notice transfer an amount of shares from msg.sender to another address
    /// @param to the address of the recipient
    /// @param shares_ the amount of shares to transfer
    function transferShares(
        address to,
        uint shares_
    ) public override returns (bool) {
        // just let it underflow if shares is too high
        shares[msg.sender] -= shares_;

        averageSharesValue[to] = _averageSharesValueOnTransfer(
            msg.sender,
            to,
            shares_
        );
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            shares[to] += shares_;
        }

        emit Transfer(msg.sender, to, shares_);

        return true;
    }

    /// @notice transfer an amount of derivative from a given address to another
    /// @dev the allowance check is done in the transferSharesFrom function
    /// @param from the address of the sender
    /// @param to the address of the recipient
    /// @param amount the amount of derivative to transfer
    function transferFrom(
        address from,
        address to,
        uint amount
    ) public override returns (bool) {
        // translate the amount passed in to shares
        uint shares_ = FixedPointMathLib.mulDivDown(
            amount,
            shares[from],
            balanceOf(from)
        );

        return transferSharesFrom(from, to, shares_);
    }

    /// @notice transfer an amount of shares from a given address to another
    /// @dev check the shares given allowance by msg.sender to from, and recompute the averageSharesValue of the recipient
    /// @param from the address of the sender
    /// @param to the address of the recipient
    /// @param shares_ the amount of shares to transfer
    /// @return bool if the transfer was successful
    function transferSharesFrom(
        address from,
        address to,
        uint shares_
    ) public override returns (bool) {
        uint allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.
        if (allowed != type(uint).max)
            allowance[from][msg.sender] = allowed - shares_;

        // just let it underflow if shares is higher than balance
        shares[from] -= shares_;

        averageSharesValue[to] = _averageSharesValueOnTransfer(
            from,
            to,
            shares_
        );
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            shares[to] += shares_;
        }

        emit Transfer(from, to, shares_);

        return true;
    }

    /// @notice re-compute the average shares value (in case of a transfer)
    /// @param from the address of the sender
    /// @param to the address of the recipient
    /// @param amount the amount of shares to transfer
    function _averageSharesValueOnTransfer(
        address from,
        address to,
        uint amount
    ) internal view returns (uint) {
        unchecked {
            return
                (shares[to] *
                    averageSharesValue[to] +
                    amount *
                    averageSharesValue[from]) / (shares[to] + amount);
        }
    }

    /// @notice permit a spender to spend a certain amount of shares on behalf of the owner
    /// @param owner the address of the owner
    /// @param spender the address of the spender
    /// @param value the amount of shares to approve
    /// @param deadline the deadline for the permit
    /// @param v the v part of the signature
    /// @param r the r part of the signature
    /// @param s the s part of the signature
    function permit(
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        Permit.permit(
            Permit.PermitParams({
                owner: owner,
                spender: spender,
                value: value,
                deadline: deadline,
                v: v,
                r: r,
                s: s,
                domainSeparator: INITIAL_DOMAIN_SEPARATOR
            }),
            nonces,
            allowance
        );
    }
}
