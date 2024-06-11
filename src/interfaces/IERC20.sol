// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import './erc20/IERC20Events.sol';
import './erc20/IERC20Minimal.sol';

interface IERC20 is IERC20Minimal, IERC20Events {
    /// @notice Returns the name of the token
    /// @return The name of the token
    function name() external view returns (string memory);

    /// @notice Returns the symbol of the token
    /// @return The symbol of the token
    function symbol() external view returns (string memory);

    /// @notice Returns the number of decimals used by the token
    /// @return The number of decimals used by the token
    function decimals() external view returns (uint8);
}
