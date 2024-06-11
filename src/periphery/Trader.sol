// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.6;

import '../interfaces/synth/ISynthActions.sol';
import '../libraries/TransferHelper.sol';

import '@openzeppelin/contracts/access/Ownable.sol';

///@notice Periphery contract used to automate trader claims
contract TraderPeriphery is Ownable {
    constructor() Ownable(msg.sender) {}

    /// @notice Aggregate all the swap claim (exit and entry) in one call
    /// these claims previously gave this contract allowance to claim on their behalf
    /// a fee is taken relative to the gasPrice and the gasLimit of the transaction
    /// @param enterees the addresses for which to claim enter trades
    /// @param exitees the addresses for which to claim exit trades
    /// @param round the round for which to claim
    /// @param synth the address of the synth
    function claimAllSwap(
        address[] calldata enterees,
        address[] calldata exitees,
        uint64 round,
        address synth
    ) public onlyOwner {
        // compute the claim fee per user depending on the gasPrice and the gasLimit
        uint96 claimFee = uint96(
            (tx.gasprice * gasleft()) / (enterees.length + exitees.length)
        );

        ISynthActions(synth).claimAllSwap(enterees, exitees, round, claimFee);
    }

    /// @notice Aggregate all the position claim (exit and entry) in one call
    /// these claims previously gave this contract allowance to claim on their behalf
    /// a fee is taken relative to the gasPrice and the gasLimit of the transaction
    /// @param mintees the addresses for which to claim the position minted
    /// @param burnees the addresses for which to claim the position burned
    /// @param round the round for which to claim
    /// @param synth the address of the synth
    function claimAllPosition(
        bytes32[] calldata mintees,
        bytes32[] calldata burnees,
        uint64 round,
        address synth
    ) public onlyOwner {
        // compute the claim fee per user depending on the gasPrice and the gasLimit
        uint96 claimFee = uint96(
            (tx.gasprice * gasleft()) / (mintees.length + burnees.length)
        );

        ISynthActions(synth).claimAllPosition(
            mintees,
            burnees,
            round,
            claimFee
        );
    }

    function harvest(address recipient) public onlyOwner {
        TransferHelper.safeTransferETH(recipient, address(this).balance);
    }

    receive() external payable {}
}
