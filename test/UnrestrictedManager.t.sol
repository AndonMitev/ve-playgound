// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Test} from "@forge-std/Test.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {BoringVault} from "@boring-vault/base/BoringVault.sol";
import {UnrestrictedManager} from "@src/UnrestrictedManager.sol";

/// @dev Simple mock that records calls made via BoringVault.manage.
contract MockTarget {
    uint256 public lastValue;
    bytes public lastData;

    function doSomething(uint256 x) external payable returns (uint256) {
        lastValue = x;
        lastData = msg.data;
        return x * 2;
    }
}

contract UnrestrictedManagerTest is Test {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint8 internal constant MANAGER_ROLE = 1;
    uint8 internal constant MANAGER_INTERNAL_ROLE = 4;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    address internal owner = makeAddr("owner");
    address internal managerEOA = makeAddr("managerEOA");
    address internal unauthorized = makeAddr("unauthorized");

    RolesAuthority internal rolesAuthority;
    BoringVault internal vault;
    UnrestrictedManager internal manager;
    MockTarget internal target;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Deploy core
        rolesAuthority = new RolesAuthority(owner, Authority(address(0)));
        vault = new BoringVault(owner, "Test Vault", "tVLT", 18);
        manager = new UnrestrictedManager(owner, address(rolesAuthority), payable(address(vault)));
        target = new MockTarget();

        // Wire authority
        vm.prank(owner);
        vault.setAuthority(Authority(address(rolesAuthority)));

        // Grant MANAGER_ROLE to manager contract on vault
        vm.startPrank(owner);
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, address(vault), bytes4(keccak256("manage(address,bytes,uint256)")), true
        );
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, address(vault), bytes4(keccak256("manage(address[],bytes[],uint256[])")), true
        );
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);

        // Grant MANAGER_INTERNAL_ROLE to managerEOA on manager contract
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
        rolesAuthority.setUserRole(managerEOA, MANAGER_INTERNAL_ROLE, true);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_constructor_revertsZeroVault() public {
        vm.expectRevert(UnrestrictedManager.UnrestrictedManager__ZeroAddress.selector);
        new UnrestrictedManager(owner, address(rolesAuthority), payable(address(0)));
    }

    function test_constructor_setsVaultAndAuthority() public view {
        assertEq(address(manager.vault()), address(vault));
        assertEq(address(manager.authority()), address(rolesAuthority));
        assertEq(manager.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                       MANAGE VAULT — SINGLE
    //////////////////////////////////////////////////////////////*/

    function test_manageVault_single_authorizedForwards() public {
        bytes memory data = abi.encodeCall(MockTarget.doSomething, (42));

        vm.prank(managerEOA);
        bytes memory result = manager.manageVault(address(target), data, 0);

        uint256 decoded = abi.decode(result, (uint256));
        assertEq(decoded, 84);
        assertEq(target.lastValue(), 42);
    }

    function test_manageVault_single_unauthorizedReverts() public {
        bytes memory data = abi.encodeCall(MockTarget.doSomething, (1));

        vm.prank(unauthorized);
        vm.expectRevert("UNAUTHORIZED");
        manager.manageVault(address(target), data, 0);
    }

    /*//////////////////////////////////////////////////////////////
                       MANAGE VAULT — BATCH
    //////////////////////////////////////////////////////////////*/

    function test_manageVault_batch_authorizedForwards() public {
        address[] memory targets = new address[](2);
        targets[0] = address(target);
        targets[1] = address(target);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(MockTarget.doSomething, (10));
        data[1] = abi.encodeCall(MockTarget.doSomething, (20));

        uint256[] memory values = new uint256[](2);

        vm.prank(managerEOA);
        bytes[] memory results = manager.manageVault(targets, data, values);

        assertEq(abi.decode(results[0], (uint256)), 20);
        assertEq(abi.decode(results[1], (uint256)), 40);
        // Last call wins for lastValue
        assertEq(target.lastValue(), 20);
    }

    function test_manageVault_batch_unauthorizedReverts() public {
        address[] memory targets = new address[](1);
        targets[0] = address(target);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(MockTarget.doSomething, (1));

        uint256[] memory values = new uint256[](1);

        vm.prank(unauthorized);
        vm.expectRevert("UNAUTHORIZED");
        manager.manageVault(targets, data, values);
    }

    /*//////////////////////////////////////////////////////////////
                         ROLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function test_roleManagement_addManager() public {
        address newManager = makeAddr("newManager");

        vm.prank(owner);
        rolesAuthority.setUserRole(newManager, MANAGER_INTERNAL_ROLE, true);

        bytes memory data = abi.encodeCall(MockTarget.doSomething, (99));

        vm.prank(newManager);
        bytes memory result = manager.manageVault(address(target), data, 0);

        assertEq(abi.decode(result, (uint256)), 198);
    }

    function test_roleManagement_removeManager() public {
        vm.prank(owner);
        rolesAuthority.setUserRole(managerEOA, MANAGER_INTERNAL_ROLE, false);

        bytes memory data = abi.encodeCall(MockTarget.doSomething, (1));

        vm.prank(managerEOA);
        vm.expectRevert("UNAUTHORIZED");
        manager.manageVault(address(target), data, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_manageVault_forwardsArbitraryCalldata(uint256 x) public {
        x = bound(x, 0, type(uint256).max / 2);
        bytes memory data = abi.encodeCall(MockTarget.doSomething, (x));

        vm.prank(managerEOA);
        bytes memory result = manager.manageVault(address(target), data, 0);

        assertEq(abi.decode(result, (uint256)), x * 2);
        assertEq(target.lastValue(), x);
    }
}
