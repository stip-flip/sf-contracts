// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './base/Base.sol';

/// @notice Synth contract used to test basic synth functionality and security checks
contract SynthBasicTest is Base {
    using Pack for int24;
    // total amount minted in the synth for testing
    uint96 public constant minted = 100 ether;
    function fillMarket(address minter) public {
        // fill the market
        mintAndClaim(minted, -1200, minter);
    }
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

        for (uint i = 1; i < 10; i++) {
            vm.deal(vm.addr(i), 1000 ether);
        }
    }

    function testMintPositionAndBurnTooMuchShares() public {
        mintAndClaim(minted, 1200, vm.addr(1));

        Position.Info memory p = synth.position(1200, vm.addr(1));

        console.log(p.shares);

        // burn more shares than the user has
        vm.prank(vm.addr(1));
        vm.expectRevert(abi.encodePacked('NES'));
        synth.burn(1200, p.shares + 1, vm.addr(1));
    }

    function testEntryAndExitTooMuchDerivatives() public {
        // mint and claim 1200 shares
        mintAndClaim(minted, 1200, vm.addr(1));

        enterAndClaim(1 ether, vm.addr(1));

        uint balance = synth.balanceOf(vm.addr(1));

        vm.prank(vm.addr(1));
        vm.expectRevert(abi.encodePacked('NES'));
        synth.exit(balance + 1, vm.addr(1));
    }

    function testEnterWithDifferentRecipient() public {
        // mint and claim 1200 shares
        mintAndClaim(minted, 1200, vm.addr(1));

        uint balance = vm.addr(1).balance;

        vm.prank(vm.addr(1));
        synth.enter{value: 1 ether}(vm.addr(1));

        uint64 round = mockOracle.getLastRound(true);

        mockOracle.incrementRound();

        vm.prank(vm.addr(1));
        synth.claimEnter(round, vm.addr(2));

        assertEq(synth.shares(vm.addr(1)), 0, 'shares = 0');

        assertEq(
            synth.shares(vm.addr(2)),
            1 ether - swapFees(1 ether),
            'shares = balance'
        );
    }

    function testExitWithDifferentRecipient() public {
        // mint and claim 1200 shares
        mintAndClaim(minted, 1200, vm.addr(1));

        enterAndClaim(1 ether, vm.addr(1));

        uint balance = synth.balanceOf(vm.addr(1));

        vm.prank(vm.addr(1));
        synth.exit(balance, vm.addr(1));

        uint64 round = mockOracle.getLastRound(true);

        mockOracle.incrementRound();

        uint balance1Before = vm.addr(1).balance;
        uint balance2Before = vm.addr(2).balance;

        vm.prank(vm.addr(1));
        synth.claimExit(round, vm.addr(2));

        assertEq(vm.addr(1).balance - balance1Before, 0, 'balance1 = 0');

        assertEq(
            vm.addr(2).balance - balance2Before,
            1 ether - swapFees(1 ether) - swapFees(1 ether - swapFees(1 ether)),
            'balance2 = balance'
        );
    }

    function testMintWithDifferentRecipient() public {
        vm.prank(vm.addr(1));
        synth.mint{value: 1 ether}(1200, vm.addr(1));

        // if I mint twice the same tick, the value is added to the mint, the claimer is updated to the last one
        vm.prank(vm.addr(1));
        synth.mint{value: 1 ether}(1200, vm.addr(2));

        uint64 round = mockOracle.getLastRound(true);

        mockOracle.incrementRound();

        // claim it with the approved claimer above
        vm.prank(vm.addr(2));
        synth.claimMint(round, int24(1200).pack(vm.addr(1)), vm.addr(2));

        // I cannot claim that mint twice
        vm.expectRevert(abi.encodePacked('NES'));
        synth.claimMint(round, int24(1200).pack(vm.addr(1)), vm.addr(2));

        assertEq(
            synth.position(1200, vm.addr(2)).shares,
            1 ether + 1 ether,
            'shares = balance'
        );

        assertEq(synth.position(1200, vm.addr(1)).shares, 0, 'shares = 0');
    }

    function testBurnWithDifferentRecipient() public {
        // mint and claim 1200 shares
        mintAndClaim(minted, 1200, vm.addr(1));

        uint balance = synth.balanceOf(vm.addr(1));

        vm.prank(vm.addr(1));
        synth.burn(1200, 1 ether, vm.addr(1));

        uint64 round = mockOracle.getLastRound(true);

        mockOracle.incrementRound();

        uint balance1Before = vm.addr(1).balance;
        uint balance2Before = vm.addr(2).balance;

        vm.prank(vm.addr(1));
        synth.claimBurn(round, int24(1200).pack(vm.addr(1)), vm.addr(2));

        assertEq(vm.addr(1).balance - balance1Before, 0, 'balance1 = 0');

        assertEq(
            vm.addr(2).balance - balance2Before,
            1 ether,
            'balance2 = balance'
        );
    }

    function testMintOutsideTickBoundary() public {
        vm.prank(vm.addr(1));

        // try to submit a tick outside the boundary
        vm.expectRevert(abi.encodePacked('T'));
        synth.mint{value: 1 ether}(type(int24).max, vm.addr(1));

        // try to submit a position at a tick that is not a multiple of 10
        vm.expectRevert();
        synth.mint(1201, vm.addr(1));
    }
}
