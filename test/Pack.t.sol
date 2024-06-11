// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import '../src/libraries/Pack.sol';

import 'forge-std/Test.sol';

contract PackTest is Test {
    mapping(uint64 => mapping(address => bytes32)) internal packs;
    function testPack(int24 tick) public {
        bytes32 packed = Pack.pack(tick, vm.addr(1));

        (int24 t, address addr) = Pack.unpack(packed);

        assertEq(t, tick, 'tick');
        assertEq(addr, vm.addr(1), 'address');
    }

    function testUnpackEmpty() public {
        (int24 t, address addr) = Pack.unpack(packs[0][address(0)]);

        assertEq(t, 0, 'tick');
        assertEq(addr, address(0), 'amount');
    }
}
