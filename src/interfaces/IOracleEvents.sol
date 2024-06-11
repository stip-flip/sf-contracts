// SPDX-License-Identifier: GPL-2.0-or-later
interface IOracleEvents {
    event Deposit(address indexed sender, uint amount);

    event Withdraw(address indexed sender, address recipient, uint amount);

    event PricesSet(address indexed sender, uint256 prices, uint64 round);

    event Slashed(
        address indexed liquidator,
        address indexed owner,
        uint64 round,
        uint8 slot,
        uint amountSlashed
    );

    event Claimed(address indexed owner, address recipient, uint rewards);
}
