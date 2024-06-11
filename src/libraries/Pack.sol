// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.6;

library Pack {
    int24 constant MAX_INT24 = 8388607;

    uint24 constant MAX_UINT24 = 0xFFFFFF;

    // Function to pack an int24 and an address into a byte32
    function pack(
        int24 _int24,
        address _address
    ) internal pure returns (bytes32) {
        uint256 int24AsUint = uint24(_int24) & MAX_UINT24;
        if (_int24 < 0) {
            // If the int24 is negative, extend the sign to the full uint256.
            int24AsUint |= uint256(uint24(MAX_INT24)) << 24;
        }
        return
            (bytes32(uint256(uint160(_address)))) |
            (bytes32(int24AsUint) << 160);
    }

    // Function to unpack a byte32 into an int24 and an address
    function unpack(bytes32 _bytes) internal pure returns (int24, address) {
        address _address = address(uint160(uint256(_bytes)));
        int24 _int24 = int24(uint24((uint256(_bytes) >> 160) & MAX_UINT24));
        if (uint24(_int24) & uint24(MAX_INT24) != 0) {
            // If the most significant bit of the int24 is set, extend the sign.
            _int24 = int24(uint24(_int24) | ~MAX_UINT24);
        }
        return (_int24, _address);
    }
}
