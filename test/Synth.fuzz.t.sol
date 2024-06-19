pragma solidity ^0.8.0;

import './base/Base.sol';

contract FuzzTest is Base {
    function setUp() public {
        mockOracle.setPrice(1e6);

        synth.initialize(
            address(mockOracle),
            1,
            'TST',
            'TST',
            'Testing',
            true,
            IOracleView.Leverage.NONE
        );
    }

    function testFuzzMint(uint96 amount) public {
        vm.assume(amount != 0);
        deal(vm.addr(1), amount);

        mintAndClaim(amount, 0, vm.addr(1));
    }

    function testFuzzBurn(uint96 amount) public {
        vm.assume(amount != 0);
        deal(vm.addr(1), amount);

        mintAndClaim(amount, 0, vm.addr(1));

        assertLt(synth.shares(vm.addr(1)), type(uint128).max);

        burnAndClaim(amount, 0, vm.addr(1));
    }

    function testFuzzEnter(uint96 amount) public {
        // uint96 amount = 100_001 ether;
        vm.assume(amount != 0);
        // vm.assume(amount <= 1_000_000 ether);
        deal(vm.addr(1), amount);
        deal(vm.addr(2), amount);

        mintAndClaim(amount, 0, vm.addr(1));

        enterAndClaim(amount, vm.addr(2));
    }

    function testFuzzExit(uint96 amount) public {
        vm.assume(amount != 0);
        // total supply of ETC will not exceed 210,700,000 ether
        vm.assume(amount < 2 ** 95);

        deal(vm.addr(1), amount);
        deal(vm.addr(2), amount);

        mintAndClaim(amount, 0, vm.addr(1));

        enterAndClaim(amount, vm.addr(2));

        exitAndClaim(synth.balanceOf(vm.addr(2)), vm.addr(2));

        assertEq(synth.balanceOf(vm.addr(2)), 0);
    }

    function testFuzzWithDebtEnter(uint96 amount) public {
        vm.assume(amount != 0);
        deal(vm.addr(1), amount);

        enterAndClaim(amount, vm.addr(1));
    }

    function testFuzzWithDebtExit(uint96 amount) public {
        // uint96 amount = 100_000_000_000 ether;
        vm.assume(amount != 0);
        // safe to assume, there is not enough ETC in circulation to break this premise
        vm.assume(amount < 2 ** 95);

        deal(vm.addr(1), amount);

        enterAndClaim(amount, vm.addr(1));

        exitAndClaim(synth.balanceOf(vm.addr(1)), vm.addr(1));

        assertEq(synth.balanceOf(vm.addr(1)), 0);
    }
}
