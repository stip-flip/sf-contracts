// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import '../../src/oracles/Oracle.sol';
import '../../script/lib/Date.sol';

import 'forge-std/Test.sol';

contract OracleRewardTest is Test {
    Oracle public oracle;
    uint8[] public drops;

    uint24 offset;
    function setUp() public {
        console.log('setup');
        uint goerliFork = vm.createFork(vm.envString('RPC_MORDOR'));
        vm.selectFork(goerliFork);

        uint8 weekDay = uint8(Date.getWeekday(block.timestamp));

        // if the price is expected at a particular time, pass an offset
        uint8 hour = uint8(Date.getHour(block.timestamp));

        console.log(hour);

        uint24 secondsSinceLastHour = uint24(block.timestamp % 3600);

        // the round should start at 00:00 UTC, offset the initializing by the appropriate time
        // since the round 0 last 24 hour, make sure round 1 start at 00:00 UTC
        offset = hour * 3600;

        console.log('offset', offset / 3600);

        offset += secondsSinceLastHour;

        uint24 frequency = 24 hours;

        uint64 initialized = uint64(block.timestamp) - offset;

        console.log('initialized', initialized, uint64(block.timestamp));

        oracle = new Oracle(
            [6, 3, 3, 8, 4, 4, 4, 8],
            drops,
            0, // ignore modulo if there is no drops
            initialized,
            24 hours, // 1 day frequency
            1 hours, // 1 hour round duration
            5 minutes, // 5 minutes delay for LP versus trader
            0.1 ether,
            'usd, bitcoin, ethereum, dogecoin, monero, solana, binancecoin, cardano, price comming from coingecko.com/, price expressed in ETC, except for ETC'
        );

        for (uint i = 1; i < 11; i++) {
            deal(vm.addr(i), 100 ether);
            deposit(vm.addr(i), 1 ether);
        }

        vm.warp(block.timestamp + ((24 * 3600) - offset));
    }

    function deposit(address from, uint amount) internal {
        vm.prank(from);
        oracle.deposit{value: amount}();
    }

    function setWrongPrice(address from) internal {
        uint64 round = oracle.getCurrentRound();

        uint256 priceData = oracle.setSlots(
            [
                uint256(1000 * 1e6), // slot0 is the wrong price, with 50% deviation
                uint256(25 * 1e6),
                uint256(8277.35 * 1e6),
                uint256(2211.65 * 1e6),
                uint256(82.23 * 1e6),
                uint256(1.6793 * 1e6),
                uint256(6.5172 * 1e6),
                uint256(4.52 * 1e6)
            ]
        );
        vm.prank(from);
        oracle.setPrices(priceData, round);
    }

    function setPrice(address from) internal {
        uint64 round = oracle.getCurrentRound();

        uint256 priceData = oracle.setSlots(
            [
                uint256(2000 * 1e6),
                uint256(25 * 1e6),
                uint256(8277.35 * 1e6),
                uint256(2211.65 * 1e6),
                uint256(82.23 * 1e6),
                uint256(1.6793 * 1e6),
                uint256(6.5172 * 1e6),
                uint256(4.52 * 1e6)
            ]
        );
        vm.prank(from);
        oracle.setPrices(priceData, round);
    }

    function goToNextRound() internal {
        vm.warp(block.timestamp + 24 hours);
    }

    function getRewards(address from) internal returns (uint rewards) {
        rewards = oracle.getAccumulatedRewards(from);
    }

    function testRewards() public {
        console.log(address(oracle), vm.addr(1).balance);
        // send some rewards to the oracle contract
        // vm.prank(vm.addr(1));
        // TransferHelper.safeTransferETH(address(oracle), 1 ether);

        // set the price
        setPrice(vm.addr(1));
        // there is 10 depositors, with equal stakes, one mana is distributed/round, the mana minted here should be equal to 0.1 ether
        assertEq(oracle.mana(vm.addr(1)), 0.1 ether, 'manas = 0.1 ether');
        // the debt however should be null
        assertEq(oracle.debt(vm.addr(1)), 0, 'debt = 0');

        // now that some mana is present, let's distribute the rewards
        TransferHelper.safeTransferETH(address(oracle), 1 ether);

        // being the only price reporter, vm.addr(1) should have accumulated all the rewards
        uint rewards = oracle.getAccumulatedRewards(vm.addr(1));

        assertEq(rewards, 1 ether, 'rewards = 1 ether');
    }

    /// @notice a stacker missing a few price rounds should not be penalized
    function testRetainingRewards() public {
        setPrice(vm.addr(1));

        // now that some mana is present, let's distribute the rewards
        TransferHelper.safeTransferETH(address(oracle), 1 ether);

        // being the only depositors vm.addr(1) should have accumulated all the rewards
        assertEq(getRewards(vm.addr(1)), 1 ether, 'rewards = 1 ether | 1');

        goToNextRound();

        setPrice(vm.addr(2));

        assertEq(getRewards(vm.addr(1)), 1 ether, 'rewards = 1 ether | 2');

        // some new rewards are coming
        TransferHelper.safeTransferETH(address(oracle), 1 ether);

        // addr(1) should have shared half these new rewards with addr(2)
        assertEq(getRewards(vm.addr(1)), 1.5 ether, 'rewards = 1.5 ether');

        // addr(2) should have received half of the rewards
        assertEq(getRewards(vm.addr(2)), 0.5 ether, 'rewards = 0.5 ether');
    }

    function testLiquidate() public {
        setPrice(vm.addr(1));

        // now that some mana is present, let's distribute the rewards
        TransferHelper.safeTransferETH(address(oracle), 1 ether);

        goToNextRound();

        setPrice(vm.addr(2));
        setPrice(vm.addr(3));

        assertEq(getRewards(vm.addr(1)), 1 ether, 'addr(1) rewards = 1 ether');
        assertEq(getRewards(vm.addr(2)), 0, 'addr(2) rewards = 0 ether');
        assertEq(getRewards(vm.addr(3)), 0, 'addr(3) rewards = 0 ether');

        goToNextRound();

        uint64 currentRound = oracle.getCurrentRound();
        // vm.addr(1) is submitting a wrong price at slot0
        setWrongPrice(vm.addr(1));
        setPrice(vm.addr(2));
        setPrice(vm.addr(3));

        // you need to wait for this round to be settled to liquidate
        vm.expectRevert(abi.encodePacked('OBC'));
        oracle.liquidate(vm.addr(2), currentRound, 0);

        goToNextRound();

        // addr(2) is not liquidatable
        vm.expectRevert(abi.encodePacked('P0'));
        oracle.liquidate(vm.addr(2), currentRound, 0);

        vm.expectRevert(abi.encodePacked('P0'));
        oracle.liquidate(vm.addr(3), currentRound, 0);

        vm.expectRevert(abi.encodePacked('OBU'));
        vm.prank(vm.addr(1));
        oracle.liquidate(vm.addr(1), currentRound, 0);

        // anyone can liquidate a deposit
        uint balanceBefore = vm.addr(4).balance;

        vm.prank(vm.addr(4));
        oracle.liquidate(vm.addr(1), currentRound, 0);

        // liquidating twice the same user will revert
        vm.expectRevert(abi.encodePacked('OIN'));
        oracle.liquidate(vm.addr(1), currentRound, 0);

        // we expect the deviation to be 5000 bps, so the amount slashed should be 0.5 ether for a 1 ether deposit
        assertEq(
            vm.addr(4).balance - balanceBefore,
            0.5 ether,
            'balance = 0.5 ether'
        );

        // addr(1) should have been liquidated and have no mana whatsoever nor any reward to claim
        assertEq(oracle.mana(vm.addr(1)), 0, 'manas = 0');
        assertEq(oracle.debt(vm.addr(1)), 0, 'debt = 0');
        assertEq(getRewards(vm.addr(1)), 0, 'rewards = 0');

        // the rewards should have been distributed to the other depositors
        assertEq(
            getRewards(vm.addr(2)) + getRewards(vm.addr(3)),
            1 ether,
            'all rewards = 1 ether'
        );
    }

    function testClaim() public {
        setPrice(vm.addr(1));

        // now that some mana is present, let's distribute the rewards
        TransferHelper.safeTransferETH(address(oracle), 1 ether);

        uint balanceBefore = vm.addr(1).balance;
        // try to claim
        vm.prank(vm.addr(1));
        oracle.claim(vm.addr(1));

        assertEq(
            vm.addr(1).balance - balanceBefore,
            1 ether,
            'balance = 1 ether'
        );

        // claim again, addr(1) balance should not change
        vm.prank(vm.addr(1));
        oracle.claim(vm.addr(1));

        assertEq(
            vm.addr(1).balance - balanceBefore,
            1 ether,
            'balance = 1 ether'
        );
    }

    function testWithdraw() public {
        console.log('sp lastRound', oracle.getLastRound(false));
        setPrice(vm.addr(1));

        // now that some mana is present, let's distribute the rewards
        TransferHelper.safeTransferETH(address(oracle), 1 ether);

        uint balanceBefore = vm.addr(1).balance;

        // try to withdraw, revert expected as no valid round has been settled
        vm.prank(vm.addr(1));
        vm.expectRevert();
        oracle.withdraw(1 ether, vm.addr(1));

        goToNextRound();

        // try to withdraw, revert expected as we need to valid round to pass before being able to withdraw the stake
        vm.prank(vm.addr(1));
        vm.expectRevert();
        oracle.withdraw(1 ether, vm.addr(1));

        goToNextRound();
        goToNextRound();
        goToNextRound(); // this is round 4, price was submitted at round 1, we can withdraw

        // try to withdraw, this time it should work
        vm.prank(vm.addr(1));
        oracle.withdraw(1 ether, vm.addr(1));

        assertEq(
            vm.addr(1).balance - balanceBefore,
            1 ether,
            'balance = 1 ether'
        );

        // addr(1) should have no more mana
        assertEq(oracle.mana(vm.addr(1)), 0, 'manas = 0');
        // addr(1) should have no more stakes
        assertEq(oracle.stakes(vm.addr(1)), 0, 'debt = 0');

        // there should still be some rewards left
        assertEq(
            oracle.getAccumulatedRewards(vm.addr(1)),
            1 ether,
            'rewards = 1 ether'
        );

        balanceBefore = vm.addr(1).balance;
        // claim
        vm.prank(vm.addr(1));
        oracle.claim(vm.addr(1));

        assertEq(
            vm.addr(1).balance - balanceBefore,
            1 ether,
            'balance = 1 ether'
        );
    }

    function testDepositAndWithdrawImmediately() public {
        vm.warp(block.timestamp + 48 hours);
        vm.startPrank(vm.addr(1));
        oracle.withdraw(1 ether, vm.addr(1));
    }
}
