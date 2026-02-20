// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {Script, console} from "@forge-std/Script.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {BoringVault} from "@boring-vault/base/BoringVault.sol";
import {AccountantWithRateProviders} from "@boring-vault/base/Roles/AccountantWithRateProviders.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/base/Roles/TellerWithMultiAssetSupport.sol";
import {UnrestrictedManager} from "@src/UnrestrictedManager.sol";
import {WithdrawQueue} from "@src/WithdrawQueue.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

/// @title DeployVault
/// @notice Deploys and wires the USDe BoringVault system.
contract DeployVault is Script {
    /*//////////////////////////////////////////////////////////////
                               ROLE IDS
    //////////////////////////////////////////////////////////////*/

    uint8 internal constant MANAGER_ROLE = 1;
    uint8 internal constant MINTER_ROLE = 2;
    uint8 internal constant BURNER_ROLE = 3;
    uint8 internal constant MANAGER_INTERNAL_ROLE = 4;
    uint8 internal constant UPDATE_EXCHANGE_RATE_ROLE = 5;
    uint8 internal constant SOLVER_ROLE = 6;
    uint8 internal constant TELLER_ROLE = 7;

    /*//////////////////////////////////////////////////////////////
                           DEPLOY PARAMETERS
    //////////////////////////////////////////////////////////////*/

    // Override these via environment variables or a config before broadcasting.
    address internal admin = vm.envAddress("ADMIN");
    address internal usde = vm.envAddress("USDE");
    address internal weth = vm.envAddress("WETH");
    address internal exchangeRateUpdater = vm.envAddress("EXCHANGE_RATE_UPDATER");
    address internal solverOperator = vm.envAddress("SOLVER_OPERATOR");

    function _managerEOAs() internal view returns (address[] memory managers) {
        managers = vm.envOr("MANAGERS", ",", new address[](0));
    }

    function run() external {
        address deployer = msg.sender;
        address[] memory managers = _managerEOAs();

        vm.startBroadcast();

        // -----------------------------------------------------------------
        // 1. Deploy RolesAuthority
        // -----------------------------------------------------------------
        RolesAuthority rolesAuthority = new RolesAuthority(deployer, Authority(address(0)));
        console.log("RolesAuthority:", address(rolesAuthority));

        // -----------------------------------------------------------------
        // 2. Deploy BoringVault
        // -----------------------------------------------------------------
        BoringVault vault = new BoringVault(deployer, "USDe Vault", "cUSDe", 18);
        console.log("BoringVault:", address(vault));

        // -----------------------------------------------------------------
        // 3. Deploy AccountantWithRateProviders
        // -----------------------------------------------------------------
        AccountantWithRateProviders accountant = new AccountantWithRateProviders(
            deployer,
            address(vault),
            admin,       // payout address
            1e18,        // starting exchange rate (1:1)
            usde,        // base asset
            10003,       // allowed exchange rate change upper (1.0003)
            9997,        // allowed exchange rate change lower (0.9997)
            86400,       // minimum update delay (1 day)
            0,           // platform fee
            0            // performance fee
        );
        console.log("Accountant:", address(accountant));

        // -----------------------------------------------------------------
        // 4. Deploy TellerWithMultiAssetSupport
        // -----------------------------------------------------------------
        TellerWithMultiAssetSupport teller =
            new TellerWithMultiAssetSupport(deployer, address(vault), address(accountant), weth);
        console.log("Teller:", address(teller));

        // -----------------------------------------------------------------
        // 5. Deploy UnrestrictedManager
        // -----------------------------------------------------------------
        UnrestrictedManager manager =
            new UnrestrictedManager(deployer, address(rolesAuthority), payable(address(vault)));
        console.log("Manager:", address(manager));

        // -----------------------------------------------------------------
        // 6. Deploy WithdrawQueue
        // -----------------------------------------------------------------
        WithdrawQueue queue = new WithdrawQueue(
            deployer,
            address(rolesAuthority),
            payable(address(vault)),
            address(teller),
            address(accountant),
            usde
        );
        console.log("Queue:", address(queue));

        // -----------------------------------------------------------------
        // Wire Authorities
        // -----------------------------------------------------------------
        vault.setAuthority(Authority(address(rolesAuthority)));
        accountant.setAuthority(Authority(address(rolesAuthority)));
        teller.setAuthority(Authority(address(rolesAuthority)));

        // -----------------------------------------------------------------
        // Role Capabilities — BoringVault
        // -----------------------------------------------------------------
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, address(vault), bytes4(keccak256("manage(address,bytes,uint256)")), true
        );
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, address(vault), bytes4(keccak256("manage(address[],bytes[],uint256[])")), true
        );
        rolesAuthority.setRoleCapability(MINTER_ROLE, address(vault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(vault), BoringVault.exit.selector, true);

        // -----------------------------------------------------------------
        // Role Capabilities — UnrestrictedManager
        // -----------------------------------------------------------------
        rolesAuthority.setRoleCapability(
            MANAGER_INTERNAL_ROLE,
            address(manager),
            bytes4(keccak256("manageVault(address,bytes,uint256)")),
            true
        );
        rolesAuthority.setRoleCapability(
            MANAGER_INTERNAL_ROLE,
            address(manager),
            bytes4(keccak256("manageVault(address[],bytes[],uint256[])")),
            true
        );

        // -----------------------------------------------------------------
        // Role Capabilities — Accountant
        // -----------------------------------------------------------------
        rolesAuthority.setRoleCapability(
            UPDATE_EXCHANGE_RATE_ROLE,
            address(accountant),
            AccountantWithRateProviders.updateExchangeRate.selector,
            true
        );

        // -----------------------------------------------------------------
        // Role Capabilities — Teller
        // -----------------------------------------------------------------
        rolesAuthority.setRoleCapability(
            TELLER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );

        // -----------------------------------------------------------------
        // Role Capabilities — WithdrawQueue
        // -----------------------------------------------------------------
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(queue), WithdrawQueue.solveWithdraw.selector, true
        );

        // -----------------------------------------------------------------
        // Public Capabilities (any user)
        // -----------------------------------------------------------------
        rolesAuthority.setPublicCapability(
            address(teller), TellerWithMultiAssetSupport.deposit.selector, true
        );
        rolesAuthority.setPublicCapability(
            address(queue), WithdrawQueue.requestWithdraw.selector, true
        );
        rolesAuthority.setPublicCapability(
            address(queue), WithdrawQueue.cancelWithdraw.selector, true
        );

        // -----------------------------------------------------------------
        // Role Assignments
        // -----------------------------------------------------------------
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(queue), TELLER_ROLE, true);
        rolesAuthority.setUserRole(exchangeRateUpdater, UPDATE_EXCHANGE_RATE_ROLE, true);
        rolesAuthority.setUserRole(solverOperator, SOLVER_ROLE, true);

        for (uint256 i; i < managers.length; ++i) {
            rolesAuthority.setUserRole(managers[i], MANAGER_INTERNAL_ROLE, true);
        }

        // -----------------------------------------------------------------
        // Asset Configuration
        // -----------------------------------------------------------------
        teller.updateAssetData(ERC20(usde), true, true, 0);
        vault.setBeforeTransferHook(address(teller));

        // -----------------------------------------------------------------
        // Transfer Ownership to admin
        // -----------------------------------------------------------------
        vault.transferOwnership(admin);
        accountant.transferOwnership(admin);
        teller.transferOwnership(admin);
        manager.transferOwnership(admin);
        queue.transferOwnership(admin);
        rolesAuthority.transferOwnership(admin);

        vm.stopBroadcast();

        console.log("Deployment complete. Admin:", admin);
    }
}
