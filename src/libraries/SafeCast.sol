// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Safe casting methods
/// @notice Contains methods for safely casting between types
library SafeCast {
    // @notice Cast a uint256 to a uint160, revert on overflow
    // @param y The uint256 to be downcasted
    // @return z The downcasted integer, now type uint160
    function u160(uint256 y) internal pure returns (uint160 z) {
        require((z = uint160(y)) == y, 'cast-u160');
    }

    // @notice Cast a uint256 to a uint128, revert on overflow
    // @param y The uint256 to be downcasted
    // @return z The downcasted integer, now type uint128
    function u128(uint256 y) internal pure returns (uint128 z) {
        require((z = uint128(y)) == y, 'cast-u128');
    }

    // @notice Cast a uint256 to a uint96, revert on overflow
    // @param y The uint256 to be downcasted
    // @return z The downcasted integer, now type uint96
    function u96(uint256 y) internal pure returns (uint96 z) {
        require((z = uint96(y)) == y, 'cast-u96');
    }

    // @notice Cast a uint256 to a uint64, revert on overflow
    // @param y The uint256 to be downcasted
    // @return z The downcasted integer, now type uint64
    function u64(uint256 y) internal pure returns (uint64 z) {
        require((z = uint64(y)) == y, 'cast-u64');
    }

    // @notice Cast an int256, check if it's not negative
    // @param y The uint256 to be downcasted
    // @return z The downcasted integer, now type uint160
    function u256(int256 y) internal pure returns (uint256 z) {
        require(y >= 0, 'cast-u256');
        z = uint256(y);
    }

    // @notice Cast a int256 to a int24, revert on overflow or underflow
    // @param y The int256 to be downcasted
    // @return z The downcasted integer, now type int24
    function i24(int256 y) internal pure returns (int24 z) {
        require((z = int24(y)) == y, 'cast-i24');
    }

    // @notice Cast a int256 to a int80, revert on overflow or underflow
    // @param y The int256 to be downcasted
    // @return z The downcasted integer, now type int80
    function i80(int256 y) internal pure returns (int80 z) {
        require((z = int80(y)) == y, 'cast-i80');
    }

    // @notice Cast a int256 to a int96, revert on overflow or underflow
    // @param y The int256 to be downcasted
    // @return z The downcasted integer, now type int96
    function i96(int256 y) internal pure returns (int96 z) {
        require((z = int96(y)) == y, 'cast-i96');
    }

    // @notice Cast a int256 to a int128, revert on overflow or underflow
    // @param y The int256 to be downcasted
    // @return z The downcasted integer, now type int128
    function i128(int256 y) internal pure returns (int128 z) {
        require((z = int128(y)) == y, 'cast-i128');
    }

    // @notice Cast a uint256 to a int256, revert on overflow
    // @param y The uint256 to be casted
    // @return z The casted integer, now type int256
    function i256(uint256 y) internal pure returns (int256 z) {
        require(y < 2 ** 255, 'cast-i256');
        z = int256(y);
    }
}
