// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import '../src/libraries/TickBitmap.sol';
import '../src/libraries/TickMath.sol';

import 'forge-std/Test.sol';

contract TickBitmapTest is Test {
    using TickBitmap for mapping(int16 => uint);
    mapping(int16 => uint) public tickBitmap;

    /// @notice Return the positive number of an int256 or zero if it was negative
    /// @param a the number we want to normalize
    /// @return zero or a positive number
    function pos(int a) public pure returns (uint) {
        return (a >= 0) ? uint(a) : uint(-a);
    }

    function logInt(int a) public view {
        console.log(a > 0 ? '' : '-', pos(a));
    }

    function testTickBitMap() public {
        tickBitmap.flipTick(-1200);
        tickBitmap.flipTick(1200);

        int24 startTick = 1201;
        // logInt(startTick);

        int24 currentTick = startTick;

        console.log('----------- to the left ------------');

        while (currentTick > -3600) {
            (int24 next, bool ini) = tickBitmap
                .nextInitializedTickWithinOneWord(currentTick, true);
            console.log('currentTick');
            logInt(currentTick);
            console.log('nextTick', ' initialized: ', ini);
            logInt(next);

            if (currentTick == next) break;
            // In zeroForOne case we decrement currentTick by one
            currentTick = next - 1;
        }

        console.log('----------- to the right -----------');

        currentTick = -1201;

        while (currentTick < 3600) {
            (int24 next, bool ini) = tickBitmap
                .nextInitializedTickWithinOneWord(currentTick, false);
            console.log('currentTick');
            logInt(currentTick);
            console.log('nextTick', ' initialized: ', ini);
            logInt(next);

            if (currentTick == next) break;

            currentTick = next;
        }
    }

    function testInitializedTickBitmap() public {
        tickBitmap.flipTick(-1200);
        tickBitmap.flipTick(1200);

        int24 startTick = 1201;
        // logInt(startTick);

        int24 currentTick = startTick;

        console.log('----------- to the left ------------');

        while (currentTick > -3600) {
            int24 next = tickBitmap.nextInitializedTick(currentTick, true);
            console.log('currentTick');
            logInt(currentTick);
            console.log('nextTick');
            logInt(next);

            if (currentTick == next) break;
            // In zeroForOne case we decrement currentTick by one
            currentTick = next;
        }

        console.log('----------- to the right -----------');

        currentTick = -1201;

        while (currentTick < 3600) {
            int24 next = tickBitmap.nextInitializedTick(currentTick, false);
            console.log('currentTick');
            logInt(currentTick);
            console.log('nextTick');
            logInt(next);

            if (currentTick == next) break;

            currentTick = next;
        }
    }
}
