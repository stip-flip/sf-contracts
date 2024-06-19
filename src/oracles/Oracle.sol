// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.6;

import '../interfaces/synth/ISynthActions.sol';
import '../interfaces/synth/ISynthState.sol';

import '../interfaces/IOracle.sol';
import '../interfaces/IOracleEvents.sol';

import '../libraries/FixedPointMathLib.sol';
import '../libraries/TransferHelper.sol';
import '../libraries/Constants.sol';

/// @notice Oracle contract, price are submitted on every block, by anyone
contract Oracle is IOracle, IOracleEvents {
    uint internal constant SLOT_0_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000; // prettier-ignore
    uint internal constant SLOT_1_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFF; // prettier-ignore
    uint internal constant SLOT_2_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFF; // prettier-ignore
    uint internal constant SLOT_3_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint internal constant SLOT_4_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint internal constant SLOT_5_MASK = 0xFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint internal constant SLOT_6_MASK = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint internal constant SLOT_7_MASK = 0x00000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore

    uint8[8] internal _decimals;
    uint8[8] internal _magnitudes;

    /// @notice drops are used to drop some round, for example, if the frequency is daily, but saturday and sunday does not
    /// have any price, the drops 6 and 7 would be passed in, with a modulo of 7 (week)
    uint8[] internal _drops;
    /// for daily update, having a modulo of 7 would allow us to skip some days, with hourly, a modulo of 24 would allow us to drop some hours
    uint8 internal _modulo;
    uint24 public immutable override frequency; // the frequency of the oracle in seconds, could be 24 hours for example
    uint24 public immutable override roundDuration; // how long does a round last, in seconds
    uint64 public override initialized; // when was the oracle initialized

    /// the minimum stake required to submit a price
    uint public immutable override minStake;

    string public description;
    /// @notice for each round, the price that was accepted and mined
    mapping(uint64 => uint256) public lastPrices;
    /// @notice for each round, the mana of the price that has the most of it
    mapping(uint64 => uint256) public manas;
    /// @notice the prices submitted during this round, mapping price to mana
    mapping(uint64 => mapping(uint256 => uint256)) public priceToMana;
    /// @notice the submitters of the prices at a given round
    mapping(uint64 => mapping(address => uint256)) public submitters;

    /// @notice mana is acquired for each successful price update, and is used to compute the weight of each price submission
    /// but also the bounty that will be distributed to the data providers
    mapping(address => uint256) public mana;
    /// @notice each user has a stake corresponding to the amount of ETC deposited, that is used to compute the mana minted for the depositor
    mapping(address => uint256) public stakes;
    /// @notice used to keep track of the rewards owed to the data providers, can be negative in case of a withdraw
    mapping(address => int256) public debt;

    uint public totalStakes;

    uint public totalMana;

    uint internal accBountyPerShare;
    /// @notice the delay is used to avoid frontrunning by LP
    uint24 public immutable delay;

    modifier onlyEOA() {
        // @todo remove this modifier for testing
        // if (tx.origin == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38) {
        //     _;
        //     return;
        // }
        require(msg.sender == tx.origin, 'EOA');
        _;
    }

    /// @notice the constructor of the oracle, the oracle is initialized with a set of parameters
    /// @param decimals_ the number of decimals for each slot
    /// @param magnitudes_ the order of magnitude expected for each price, for example, if the price is 1000, the order is 3, useful for leverage and flip price calculations
    /// @param drops_ the drops, for example, if the frequency is daily, and we want to skip saturday and sunday, we would pass [6, 7]
    /// @param modulo_ the modulo of the oracle, for example, if the frequency is daily, the modulo would be 7 for a week
    /// @param initialized_ the timestamp at which the oracle was initialized, when is round 0 starting
    /// @param frequency_ the frequency of the oracle, in seconds
    /// @param roundDuration_ the duration of a round, in seconds
    /// @param minStake_ the minimum stake required to submit a price
    /// @param description_ the description of the oracle, where and when the data is coming from
    constructor(
        uint8[8] memory decimals_,
        uint8[8] memory magnitudes_,
        uint8[] memory drops_,
        uint8 modulo_,
        uint64 initialized_,
        uint24 frequency_,
        uint24 roundDuration_,
        uint24 delay_,
        uint minStake_,
        string memory description_
    ) {
        _decimals = decimals_;
        _magnitudes = magnitudes_;
        frequency = frequency_;
        _drops = drops_;
        _modulo = modulo_;
        roundDuration = roundDuration_;
        minStake = minStake_;
        description = description_;
        initialized = initialized_;
        delay = delay_;
    }

    function isRoundAllowed(uint64 round) public view returns (bool isAllowed) {
        for (uint i = 0; i < _drops.length; i++) {
            if (round % _modulo == _drops[i]) {
                isAllowed = false;
                break;
            }
        }
        isAllowed = true;
    }

    function getDecimals(uint8 slot) public view override returns (uint8) {
        return _decimals[slot];
    }

    /// @notice returns the current round, for which we might not have a price yet
    /// @dev used for position and swap
    function getRound(
        bool withDelay
    ) public view override returns (uint64 round) {
        if (withDelay) {
            return
                (uint64(block.timestamp + roundDuration + delay) -
                    initialized) / frequency;
        } else {
            return
                (uint64(block.timestamp + roundDuration) - initialized) /
                frequency;
        }
    }

    /// @notice returns the last completed round for which a price is available
    /// @dev used for claim position and claim swap
    function getLastRound(
        bool withDelay
    ) public view override returns (uint64 lastRound) {
        if (withDelay) {
            lastRound =
                (uint64(block.timestamp) -
                    (initialized + roundDuration + delay)) /
                frequency;
        } else {
            lastRound =
                (uint64(block.timestamp) - (initialized + roundDuration)) /
                frequency;
        }

        while (!isRoundAllowed(lastRound)) {
            lastRound--;
        }
    }

    /// @notice used for price submission, returns the current round expected for a price update
    /// returns 0 if no round is "current" and available for a price update
    function getCurrentRound() public view returns (uint64 currentRound) {
        uint lastRound = (uint64(block.timestamp) - initialized) / frequency;
        if ((uint64(block.timestamp) - initialized) % frequency > roundDuration)
            return 0;
        return uint64(lastRound);
    }

    function getSlots(
        uint256 data
    ) public pure returns (uint256[8] memory slots) {
        slots[0] = data & ~SLOT_0_MASK;
        slots[1] = (data & ~SLOT_1_MASK) >> 32;
        slots[2] = (data & ~SLOT_2_MASK) >> 64;
        slots[3] = (data & ~SLOT_3_MASK) >> 96;
        slots[4] = (data & ~SLOT_4_MASK) >> 128;
        slots[5] = (data & ~SLOT_5_MASK) >> 160;
        slots[6] = (data & ~SLOT_6_MASK) >> 192;
        slots[7] = (data & ~SLOT_7_MASK) >> 224;
    }

    function getAccumulatedRewards(
        address user
    ) public view returns (uint rewards) {
        rewards = FixedPointMathLib.mulDivDown(
            mana[user],
            accBountyPerShare,
            WAD
        );

        if (debt[user] > 0) {
            rewards -= uint(debt[user]);
        } else {
            rewards += uint(-debt[user]);
        }
    }

    /// @notice returns the last price submitted
    /// @param slot the slot to get the price from
    /// @return price_ the last price submitted
    function lastPrice(
        uint8 slot
    ) public view override returns (uint64 price_) {
        uint64 i = 0;
        uint64 lastRound = (uint64(block.timestamp) -
            (initialized + roundDuration)) / frequency;
        if (lastRound == 0) return 0;
        uint256 p = lastPrices[lastRound];
        while (p == 0 && lastRound - i > 0) {
            i++;
            p = lastPrices[lastRound - i];
        }
        if (lastPrices[lastRound - i] == 0) return 0;
        return uint32(getSlots(p)[slot]);
    }

    /// @notice utility function that returns the last price submitted, with long/short and leverage applied
    /// @param slot the slot to get the price from
    /// @param long whether the price is for a long or short (stip or flip) position
    /// @param leverage the leverage to apply to the price
    function lastPrice(
        uint8 slot,
        bool long,
        Leverage leverage
    ) public view override returns (uint64 price) {
        price = lastPrice(slot);
        // useful one off casting for calculations
        uint p = uint(price);

        if (leverage == Leverage.SQUARED) {
            price = uint64((p * p) / 10 ** _magnitudes[slot]);
        }
        if (leverage == Leverage.CUBED) {
            price = uint64((p * p * p) / 10 ** (_magnitudes[slot] * 2));
        }
        if (!long) {
            price = uint64(10 ** ((_magnitudes[slot] + 1) * 2) / uint(price));
        }
    }

    /// @notice return the last price submitted from a slot and at a given round
    /// @param round the round to get the price from
    /// @param slot the slot to get the price from
    /// @return price_ the last price submitted
    function lastPrice(
        uint64 round,
        uint8 slot
    ) public view override returns (uint64 price_) {
        uint64 i = 0;
        if (round == 0) return 0;
        uint256 p = lastPrices[round];
        while (p == 0) {
            i++;
            p = lastPrices[round - i];
        }
        return uint32(getSlots(p)[slot]);
    }

    /// @notice return the next price available from a slot and at a given round
    /// @param round the round to get the next price from
    /// @param slot the slot to get the price from
    /// @return price_ the next price available
    function nextPrice(
        uint64 round,
        uint8 slot
    ) public view override returns (uint64 price_) {
        require(round != 0, 'OB');
        uint64 i = 1;
        uint256 p = lastPrices[round + i];
        while (p == 0) {
            i++;
            p = lastPrices[round + i];
        }
        return uint32(getSlots(p)[slot]);
    }

    function setSlots(uint[8] memory slots) public pure returns (uint data) {
        data = (data & SLOT_0_MASK) | slots[0];
        data = (data & SLOT_1_MASK) | (slots[1] << 32);
        data = (data & SLOT_2_MASK) | (slots[2] << 64);
        data = (data & SLOT_3_MASK) | (slots[3] << 96);
        data = (data & SLOT_4_MASK) | (slots[4] << 128);
        data = (data & SLOT_5_MASK) | (slots[5] << 160);
        data = (data & SLOT_6_MASK) | (slots[6] << 192);
        data = (data & SLOT_7_MASK) | (slots[7] << 224);
    }

    /// @notice set the price for a given round, the round argument is used to avoid having the transaction
    /// stuck in the pool for too long, if it is the case, the setPrices would revert rather
    /// than submitting a wrong price at the wrong round
    /// @dev since the deposit is protected via onlyEOA, setPrices cannot be used by non EOA accounts

    function setPrices(uint256 prices_, uint64 round) public override {
        // make sure the transaction was not late, revert otherwise
        require(round != 0, 'OB');
        require(isRoundAllowed(round), 'OBA');
        require(round == getCurrentRound(), 'OBC');
        require(prices_ != 0, 'P0');
        // make sure the price is not already submitted
        require(submitters[round][msg.sender] == 0, 'OBS');

        require(stakes[msg.sender] >= minStake, 'Z');

        uint newMana = FixedPointMathLib.mulDivDown(
            stakes[msg.sender],
            WAD,
            totalStakes
        );

        // for every successful price update, the oracle provider mint an amount of mana pro rata to the stakes of the provider
        mana[msg.sender] += newMana;
        totalMana += newMana;

        // increase the debt with the new mana minted, to guarantee the existing distributed rewards are not being stolen
        debt[msg.sender] += int(
            FixedPointMathLib.mulDivDown(newMana, accBountyPerShare, WAD)
        );

        submitters[round][msg.sender] = prices_;

        priceToMana[round][prices_] += mana[msg.sender];

        if (priceToMana[round][prices_] > manas[round]) {
            manas[round] = priceToMana[round][prices_];
            lastPrices[round] = prices_;
        }

        emit PricesSet(msg.sender, prices_, round);
    }

    /// @notice increase the user stake
    function deposit() public payable override onlyEOA {
        stakes[msg.sender] += msg.value;
        totalStakes += msg.value;

        emit Deposit(msg.sender, msg.value);
    }

    /// @notice decrease the user stake, and decrease tha amount of mana pro-rata to the stakes retrieved
    /// a cooldown period of 2 rounds is applied to allow liquidator to liquidate bad actors
    /// @param amount the amount of stake to withdraw
    function withdraw(uint256 amount, address recipient) public override {
        uint64 lastRound = getLastRound(false);
        require(amount <= stakes[msg.sender], 'LOW');
        // grace period, you cannot withdraw if you submitted a price in the last 2 rounds
        require(submitters[lastRound - 2][msg.sender] == 0, 'L');
        require(submitters[lastRound - 1][msg.sender] == 0, 'L');

        uint manaToBurn = FixedPointMathLib.mulDivDown(
            amount,
            mana[msg.sender],
            stakes[msg.sender]
        );

        debt[msg.sender] -= int(
            FixedPointMathLib.mulDivDown(manaToBurn, accBountyPerShare, WAD)
        );

        mana[msg.sender] -= manaToBurn;

        totalMana -= manaToBurn;

        // just let it underflow if amount is more than the user stake
        stakes[msg.sender] -= amount;
        totalStakes -= amount;

        // send the amount back to the recipient
        TransferHelper.safeTransferETH(recipient, amount);

        emit Withdraw(msg.sender, recipient, amount);
    }

    /// @notice claim the bounties in the synths
    /// @param recipient the address that will receive the bounty
    /// @return rewards the amount of rewards accumulated by the user
    function claim(address recipient) public override returns (uint rewards) {
        rewards = getAccumulatedRewards(msg.sender);

        TransferHelper.safeTransferETH(recipient, rewards);

        debt[msg.sender] = int(
            FixedPointMathLib.mulDivDown(
                mana[msg.sender],
                accBountyPerShare,
                WAD
            )
        );

        emit Claimed(msg.sender, recipient, rewards);
    }

    function liquidate(address user, uint64 round, uint8 slot) public onlyEOA {
        require(round != 0, 'OB');
        require(msg.sender != user, 'OBU');

        // you cannot liquidate for a price that is not yet settled
        require(round != getCurrentRound(), 'OBC');

        // find the data submitted by the user
        uint256 userData = submitters[round][user];
        require(userData != 0, 'UD0');

        // find the actual data used for this round
        uint256 data = lastPrices[round];
        require(data != 0, 'D0');

        // get the actual price at the given slot
        uint64 userPrice = uint32(getSlots(userData)[slot]);
        uint64 price = uint32(getSlots(data)[slot]);

        require(userPrice != price, 'P0');

        uint deviation = FixedPointMathLib.mulDivDown(
            uint(userPrice > price ? userPrice - price : price - userPrice),
            1e4,
            price
        );
        // slash the price, passing the price deviation as argument
        uint amountSlashed = slash(
            user,
            uint24(deviation > 1e4 ? 1e4 : deviation)
        );

        // send the amount slashed to the liquidator
        TransferHelper.safeTransferETH(msg.sender, amountSlashed);

        emit Slashed(msg.sender, user, round, slot, amountSlashed);
    }

    /// @notice slashing is called by the liquidator function, for any submitter that is outside the accepted price
    /// MANA gets back to 0, the stake is slashed pro-rata to the price deviation
    /// the pending rewards of the slashee is distributed to the other data providers
    /// the amount slashed will go to the liquidator
    function slash(
        address user,
        uint24 divergeance
    ) internal returns (uint amountSlashed) {
        // if the user has no mana, it was either slashed already or never submitted a price
        require(mana[user] > 0, 'OIN');
        uint rewards = getAccumulatedRewards(user);
        totalMana -= mana[user];
        mana[user] = 0;

        amountSlashed = FixedPointMathLib.mulDivDown(
            stakes[user],
            divergeance,
            1e4
        );

        stakes[user] -= amountSlashed;
        totalStakes -= amountSlashed;

        if (totalMana > 0) {
            // send the bounty unclaimed to all the stakers
            accBountyPerShare += FixedPointMathLib.mulDivDown(
                rewards,
                WAD,
                totalMana
            );
        }

        debt[user] = 0;
    }

    receive() external payable {
        require(totalMana > 0, 'OIN');
        // increase the total bounty tracking of the oracle
        accBountyPerShare += FixedPointMathLib.mulDivDown(
            msg.value,
            WAD,
            totalMana
        );
    }
}
