pragma solidity ^0.8.6;

import '../../src/Synth.sol';

import '../../test/mock/MockOracle.sol';

import 'forge-std/Test.sol';

abstract contract Base is Test {
    using Pack for int24;

    MockOracle mockOracle = new MockOracle();
    Synth public synth = new Synth();

    address[] public enterees;
    bytes32[] public mintees;
    address[] public exitees;
    bytes32[] public burnees;

    uint64[] public entries;
    uint64[] public exits;

    address public periphery = vm.addr(9);

    function getSlot0() public view returns (ISynthState.Slot0 memory) {
        (uint128 pnl, uint96 totalLiquidities) = synth.slot0();
        return ISynthState.Slot0(pnl, totalLiquidities);
    }

    function getSlot1() public view returns (ISynthState.Slot1 memory) {
        (
            uint128 liquidityPerTickX24,
            int24 tick,
            int24 leftMostInitializedTick,
            int24 rightMostInitializedTick
        ) = synth.slot1();
        return
            ISynthState.Slot1(
                liquidityPerTickX24,
                tick,
                leftMostInitializedTick,
                rightMostInitializedTick
            );
    }

    function getSlot2() public view returns (ISynthState.Slot2 memory) {
        (uint128 totalShares, uint64 lastUpdate, uint64 lastPrice) = synth
            .slot2();
        return ISynthState.Slot2(totalShares, lastUpdate, lastPrice);
    }

    function positionPnL(
        int24 positionTick,
        address owner
    ) public view returns (int256) {
        Position.Info memory p = synth.position(positionTick, owner);
        return
            int(synth.positionValue(positionTick, owner)) -
            FixedPointMathLib.iMulDivDown(int128(p.shares), p.sharesRatio, RAY);
    }

    function swapFees(uint amount) public view returns (uint96) {
        return uint96(amount * synth.FEE()) / 1e4;
    }

    function oracleFees(uint amount) public view returns (uint96) {
        return uint96(swapFees(amount) * synth.ORACLE_FEE()) / 1e4;
    }

    function mintFees(uint amount) public view returns (uint96) {
        return uint96(swapFees(amount) * (1e4 - synth.ORACLE_FEE())) / 1e4;
    }

    /// @notice Given an amount of swap fees, how much is going to the Oracle
    function oraclePart(uint swapFees_) public view returns (uint96) {
        return uint96(swapFees_ * synth.ORACLE_FEE()) / 1e4;
    }

    /// @notice Given an amount of swap fees, how much is going to LPs
    function mintPart(uint swapFees_) public view returns (uint96) {
        return uint96(swapFees_ * (1e4 - synth.ORACLE_FEE())) / 1e4;
    }

    function enterAndClaim(uint amount, address from) public {
        delete enterees;
        delete exitees;
        uint64 r = mockOracle.getCurrentRound();
        vm.startPrank(from);
        synth.enter{value: amount}(periphery);
        mockOracle.incrementRound();

        enterees.push(from);

        vm.startPrank(periphery);
        synth.claimAllSwap(enterees, exitees, r - 1, 0);

        vm.stopPrank();
    }

    function exitAndClaim(uint amount, address from) public {
        delete enterees;
        delete exitees;
        vm.startPrank(from);
        uint64 r = mockOracle.getCurrentRound();
        synth.exit(amount, periphery);

        mockOracle.incrementRound();

        exitees.push(from);

        vm.startPrank(periphery);
        synth.claimAllSwap(enterees, exitees, r - 1, 0);

        vm.stopPrank();
    }

    function mintAndClaim(uint amount, int24 tick, address from) public {
        delete mintees;
        delete burnees;
        vm.startPrank(from);
        uint64 r = mockOracle.getCurrentRound();
        synth.mint{value: amount}(tick, periphery);
        mockOracle.incrementRound();

        mintees.push(tick.pack(from));

        vm.startPrank(periphery);
        synth.claimAllPosition(mintees, burnees, r - 1, 0);

        vm.stopPrank();
    }

    function burnAndClaim(uint128 shares, int24 tick, address from) public {
        delete mintees;
        delete burnees;
        vm.startPrank(from);

        uint64 r = mockOracle.getCurrentRound();

        synth.burn(tick, shares, periphery);

        mockOracle.incrementRound();

        burnees.push(tick.pack(from));

        vm.startPrank(periphery);

        synth.claimAllPosition(mintees, burnees, r - 1, 0);

        vm.stopPrank();
    }
}
