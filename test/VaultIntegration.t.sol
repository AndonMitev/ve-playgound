// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Test} from "@forge-std/Test.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {BoringVault} from "@boring-vault/base/BoringVault.sol";
import {AccountantWithRateProviders} from "@boring-vault/base/Roles/AccountantWithRateProviders.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/base/Roles/TellerWithMultiAssetSupport.sol";
import {UnrestrictedManager} from "@src/UnrestrictedManager.sol";
import {WithdrawQueue} from "@src/WithdrawQueue.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract VaultIntegrationTest is Test {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint8 internal constant MANAGER_ROLE = 1;
    uint8 internal constant MINTER_ROLE = 2;
    uint8 internal constant BURNER_ROLE = 3;
    uint8 internal constant MANAGER_INTERNAL_ROLE = 4;
    uint8 internal constant UPDATE_EXCHANGE_RATE_ROLE = 5;
    uint8 internal constant SOLVER_ROLE = 6;
    uint8 internal constant TELLER_ROLE = 7;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    address internal deployer = makeAddr("deployer");
    address internal admin = makeAddr("admin");
    address internal user = makeAddr("user");
    address internal managerEOA = makeAddr("managerEOA");
    address internal solverOperator = makeAddr("solverOperator");
    address internal exchangeRateUpdater = makeAddr("exchangeRateUpdater");

    MockERC20 internal usde;
    MockERC20 internal weth;

    RolesAuthority internal rolesAuthority;
    BoringVault internal vault;
    AccountantWithRateProviders internal accountant;
    TellerWithMultiAssetSupport internal teller;
    WithdrawQueue internal queue;
    UnrestrictedManager internal manager;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        usde = new MockERC20("USDe", "USDe", 18);
        weth = new MockERC20("WETH", "WETH", 18);

        vm.startPrank(deployer);

        // Deploy core contracts
        rolesAuthority = new RolesAuthority(deployer, Authority(address(0)));
        vault = new BoringVault(deployer, "USDe Vault", "cUSDe", 18);
        accountant = new AccountantWithRateProviders(
            deployer,
            address(vault),
            admin,
            1e18,           // 1:1 starting rate
            address(usde),
            10003,          // upper bound
            9997,           // lower bound
            86400,          // 1 day min update delay
            0,              // no platform fee
            0               // no performance fee
        );
        teller = new TellerWithMultiAssetSupport(deployer, address(vault), address(accountant), address(weth));
        manager = new UnrestrictedManager(deployer, address(rolesAuthority), payable(address(vault)));
        queue = new WithdrawQueue(
            deployer,
            address(rolesAuthority),
            payable(address(vault)),
            address(teller),
            address(accountant),
            address(usde)
        );

        // Wire authorities
        vault.setAuthority(Authority(address(rolesAuthority)));
        accountant.setAuthority(Authority(address(rolesAuthority)));
        teller.setAuthority(Authority(address(rolesAuthority)));

        // Role capabilities — BoringVault
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, address(vault), bytes4(keccak256("manage(address,bytes,uint256)")), true
        );
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, address(vault), bytes4(keccak256("manage(address[],bytes[],uint256[])")), true
        );
        rolesAuthority.setRoleCapability(MINTER_ROLE, address(vault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(vault), BoringVault.exit.selector, true);

        // Role capabilities — UnrestrictedManager
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

        // Role capabilities — Accountant
        rolesAuthority.setRoleCapability(
            UPDATE_EXCHANGE_RATE_ROLE,
            address(accountant),
            AccountantWithRateProviders.updateExchangeRate.selector,
            true
        );

        // Role capabilities — Teller
        rolesAuthority.setRoleCapability(
            TELLER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );

        // Role capabilities — Queue
        rolesAuthority.setRoleCapability(SOLVER_ROLE, address(queue), WithdrawQueue.solveWithdraw.selector, true);

        // Public capabilities
        rolesAuthority.setPublicCapability(address(teller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(address(queue), WithdrawQueue.requestWithdraw.selector, true);
        rolesAuthority.setPublicCapability(address(queue), WithdrawQueue.cancelWithdraw.selector, true);

        // Role assignments
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(queue), TELLER_ROLE, true);
        rolesAuthority.setUserRole(exchangeRateUpdater, UPDATE_EXCHANGE_RATE_ROLE, true);
        rolesAuthority.setUserRole(solverOperator, SOLVER_ROLE, true);
        rolesAuthority.setUserRole(managerEOA, MANAGER_INTERNAL_ROLE, true);

        // Asset config
        teller.updateAssetData(ERC20(address(usde)), true, true, 0);
        vault.setBeforeTransferHook(address(teller));

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address depositor, uint256 amount) internal returns (uint256 shares) {
        usde.mint(depositor, amount);
        vm.startPrank(depositor);
        usde.approve(address(vault), amount);
        shares = teller.deposit(ERC20(address(usde)), amount, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_userReceivesShares() public {
        uint256 depositAmount = 100e18;
        uint256 shares = _deposit(user, depositAmount);

        // 1:1 exchange rate
        assertEq(shares, depositAmount);
        assertEq(vault.balanceOf(user), depositAmount);
        assertEq(usde.balanceOf(address(vault)), depositAmount);
    }

    function testFuzz_deposit_variableAmounts(uint256 amount) public {
        amount = bound(amount, 1, 1e30);
        uint256 shares = _deposit(user, amount);

        assertEq(shares, amount);
        assertEq(vault.balanceOf(user), amount);
        assertEq(usde.balanceOf(address(vault)), amount);
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAWAL QUEUE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_withdraw_requestTransfersShares() public {
        uint256 depositAmount = 100e18;
        _deposit(user, depositAmount);

        vm.startPrank(user);
        ERC20(address(vault)).approve(address(queue), depositAmount);
        queue.requestWithdraw(uint96(depositAmount));
        vm.stopPrank();

        // Shares transferred from user to queue
        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.balanceOf(address(queue)), depositAmount);
    }

    function test_withdraw_solveAfterMaturity() public {
        uint256 depositAmount = 100e18;
        _deposit(user, depositAmount);

        vm.startPrank(user);
        ERC20(address(vault)).approve(address(queue), depositAmount);
        queue.requestWithdraw(uint96(depositAmount));
        vm.stopPrank();

        // Warp past 3-day maturity
        vm.warp(block.timestamp + 259_200 + 1);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        vm.prank(solverOperator);
        queue.solveWithdraw(ids);

        // User receives USDe
        assertEq(usde.balanceOf(user), depositAmount);
        assertEq(vault.balanceOf(address(queue)), 0);
    }

    function test_withdraw_solveBeforeMaturityReverts() public {
        uint256 depositAmount = 100e18;
        _deposit(user, depositAmount);

        vm.startPrank(user);
        ERC20(address(vault)).approve(address(queue), depositAmount);
        queue.requestWithdraw(uint96(depositAmount));
        vm.stopPrank();

        // Try to solve before maturity (only 1 day, need 3)
        vm.warp(block.timestamp + 86400);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        vm.prank(solverOperator);
        vm.expectRevert(WithdrawQueue.WithdrawQueue__NotMatured.selector);
        queue.solveWithdraw(ids);
    }

    function test_withdraw_cancelReturnsShares() public {
        uint256 depositAmount = 100e18;
        _deposit(user, depositAmount);

        vm.startPrank(user);
        ERC20(address(vault)).approve(address(queue), depositAmount);
        queue.requestWithdraw(uint96(depositAmount));

        // Cancel
        queue.cancelWithdraw(1);
        vm.stopPrank();

        // Shares returned to user
        assertEq(vault.balanceOf(user), depositAmount);
        assertEq(vault.balanceOf(address(queue)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    TELLER DIRECT WITHDRAW DISABLED
    //////////////////////////////////////////////////////////////*/

    function test_tellerDirectWithdraw_reverts() public {
        uint256 depositAmount = 100e18;
        _deposit(user, depositAmount);

        // Direct bulkWithdraw should revert (unauthorized for regular user)
        vm.prank(user);
        vm.expectRevert("UNAUTHORIZED");
        teller.bulkWithdraw(ERC20(address(usde)), depositAmount, 0, user);
    }
}
