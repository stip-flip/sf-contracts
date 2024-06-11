// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.6;

import './IOracleView.sol';

interface IOracle is IOracleView {
    function frequency() external view returns (uint24);

    function roundDuration() external view returns (uint24);

    /// initialisation timestamp
    function initialized() external view returns (uint64);

    function minStake() external view returns (uint256);

    // function description() external view returns (string memory);

    function setPrices(uint256 prices, uint64 round) external;

    function lastPrice(uint8 slot) external view returns (uint64 price);

    function lastPrice(
        uint64 round,
        uint8 slot
    ) external view returns (uint64 price);

    function nextPrice(
        uint64 round,
        uint8 slot
    ) external view returns (uint64 price_);

    function deposit() external payable;

    function withdraw(uint amount, address recipient) external;

    function claim(address recipient) external returns (uint accumulatedBounty);
}
