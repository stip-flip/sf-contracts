// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.6;

interface IOracleView {
    enum Leverage {
        NONE,
        SQUARED,
        CUBED
    }

    function getRound(bool withDelay) external view returns (uint64 round);

    function getLastRound(
        bool withDelay
    ) external view returns (uint64 lastRound);

    function getDecimals(uint8 slot) external view returns (uint8);

    function lastPrice(
        uint8 slot,
        bool long,
        Leverage leverage
    ) external view returns (uint64 p);
}
