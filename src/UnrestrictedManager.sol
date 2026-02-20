// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {BoringVault} from "@boring-vault/base/BoringVault.sol";

/// @title UnrestrictedManager
/// @notice Forwards arbitrary manage calls to a BoringVault with no calldata
/// restrictions. Access controlled entirely by RolesAuthority.
contract UnrestrictedManager is Auth {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error UnrestrictedManager__ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    BoringVault public immutable vault;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _auth, address payable _vault)
        Auth(_owner, Authority(_auth))
    {
        if (_vault == address(0)) revert UnrestrictedManager__ZeroAddress();
        vault = BoringVault(_vault);
    }

    /*//////////////////////////////////////////////////////////////
                            MANAGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Forward a single manage call to the vault.
    /// @param target The address to call.
    /// @param data The calldata to forward.
    /// @param value The ETH value to send.
    /// @return result The return data from the call.
    function manageVault(address target, bytes calldata data, uint256 value)
        external
        requiresAuth
        returns (bytes memory result)
    {
        result = vault.manage(target, data, value);
    }

    /// @notice Forward a batch of manage calls to the vault.
    /// @param targets The addresses to call.
    /// @param data The calldata to forward for each call.
    /// @param values The ETH values to send for each call.
    /// @return results The return data from each call.
    function manageVault(address[] calldata targets, bytes[] calldata data, uint256[] calldata values)
        external
        requiresAuth
        returns (bytes[] memory results)
    {
        results = vault.manage(targets, data, values);
    }
}
