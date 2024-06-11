pragma solidity >=0.8.6;
import '../../src/interfaces/IOracle.sol';

import '../../src/libraries/SafeCast.sol';

import 'forge-std/console.sol';

contract MockOracle is IOracle {
    using SafeCast for uint;
    uint64 internal price;
    uint128 internal timestamp;

    uint64 internal round = 1;

    uint8[8] private _decimals = [6, 0, 0, 0, 0, 0, 0, 0];
    uint24 public override frequency = 1;
    uint24 public override roundDuration = 1;
    uint64 public override initialized = 0;
    uint public override minStake = 0;
    string public description = 'MockOracle';

    function setDecimals(uint8[8] memory decimals_) external {
        _decimals = decimals_;
    }

    function getDecimals(uint8 slot) external view override returns (uint8) {
        return _decimals[0];
    }

    function setPrices(uint256 prices, uint64 block_) external override {}

    function setPrice(uint price_) external {
        price = uint64(price_);
        timestamp = uint128(block.timestamp);
    }

    function getName() public pure returns (string memory) {
        return 'TST';
    }

    function lastPrice(
        uint8 slot
    ) external view override returns (uint64 price_) {
        return price;
    }

    function lastPrice(
        uint64 round,
        uint8 slot
    ) external view override returns (uint64 price_) {
        return price;
    }

    function lastPrice(
        uint8 slot,
        bool long,
        Leverage leverage
    ) external view override returns (uint64 p) {
        return price;
    }

    function nextPrice(
        uint64 round,
        uint8 slot
    ) external view override returns (uint64 price_) {
        return price;
    }

    function getRound(bool withDelay) external view override returns (uint64) {
        return round - 1;
    }

    function getLastRound(
        bool withDelay
    ) external view override returns (uint64) {
        return round - 1;
    }

    function getCurrentRound() public view returns (uint64) {
        return round;
    }

    function incrementRound() external {
        round++;
    }

    function deposit() external payable override {}

    function withdraw(uint amount, address recipient) external override {}

    function claim(
        address recipient
    ) external override returns (uint accumulatedBounty) {}

    receive() external payable {}
}
