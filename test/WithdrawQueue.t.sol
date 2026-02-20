// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Test} from "@forge-std/Test.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {BoringVault} from "@boring-vault/base/BoringVault.sol";
import {AccountantWithRateProviders} from "@boring-vault/base/Roles/AccountantWithRateProviders.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/base/Roles/TellerWithMultiAssetSupport.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {WithdrawQueue} from "@src/WithdrawQueue.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract WithdrawQueueTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event WithdrawRequested(uint96 indexed requestId, address indexed user, uint96 amountOfShares);
    event WithdrawCancelled(uint96 indexed requestId, address indexed user, uint96 amountOfShares);
    event WithdrawSolved(uint96 indexed requestId, address indexed user, uint96 amountOfShares, uint256 assetsOut);

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint8 internal constant MINTER_ROLE = 2;
    uint8 internal constant BURNER_ROLE = 3;
    uint8 internal constant SOLVER_ROLE = 6;
    uint8 internal constant TELLER_ROLE = 7;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    address internal deployer = makeAddr("deployer");
    address internal user = makeAddr("user");
    address internal user2 = makeAddr("user2");
    address internal solver = makeAddr("solver");

    MockERC20 internal usde;
    MockERC20 internal weth;

    RolesAuthority internal rolesAuthority;
    BoringVault internal vault;
    AccountantWithRateProviders internal accountant;
    TellerWithMultiAssetSupport internal teller;
    WithdrawQueue internal queue;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        usde = new MockERC20("USDe", "USDe", 18);
        weth = new MockERC20("WETH", "WETH", 18);

        vm.startPrank(deployer);

        rolesAuthority = new RolesAuthority(deployer, Authority(address(0)));
        vault = new BoringVault(deployer, "USDe Vault", "cUSDe", 18);
        accountant = new AccountantWithRateProviders(
            deployer,
            address(vault),
            deployer,
            1e18,
            address(usde),
            10003,
            9997,
            86400,
            0,
            0
        );
        teller = new TellerWithMultiAssetSupport(deployer, address(vault), address(accountant), address(weth));
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

        // Vault roles
        rolesAuthority.setRoleCapability(MINTER_ROLE, address(vault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(vault), BoringVault.exit.selector, true);

        // Teller bulkWithdraw
        rolesAuthority.setRoleCapability(
            TELLER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );

        // Queue solveWithdraw
        rolesAuthority.setRoleCapability(SOLVER_ROLE, address(queue), WithdrawQueue.solveWithdraw.selector, true);

        // Public capabilities
        rolesAuthority.setPublicCapability(address(teller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(address(queue), WithdrawQueue.requestWithdraw.selector, true);
        rolesAuthority.setPublicCapability(address(queue), WithdrawQueue.cancelWithdraw.selector, true);

        // Role assignments
        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(queue), TELLER_ROLE, true);
        rolesAuthority.setUserRole(solver, SOLVER_ROLE, true);

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

    function _requestWithdraw(address depositor, uint96 shares) internal returns (uint96 requestId) {
        vm.startPrank(depositor);
        ERC20(address(vault)).approve(address(queue), shares);
        requestId = queue.requestWithdraw(shares);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_revertsZeroAddress() public {
        vm.startPrank(deployer);

        vm.expectRevert(WithdrawQueue.WithdrawQueue__ZeroAddress.selector);
        new WithdrawQueue(deployer, address(rolesAuthority), payable(address(0)), address(teller), address(accountant), address(usde));

        vm.expectRevert(WithdrawQueue.WithdrawQueue__ZeroAddress.selector);
        new WithdrawQueue(deployer, address(rolesAuthority), payable(address(vault)), address(0), address(accountant), address(usde));

        vm.expectRevert(WithdrawQueue.WithdrawQueue__ZeroAddress.selector);
        new WithdrawQueue(deployer, address(rolesAuthority), payable(address(vault)), address(teller), address(0), address(usde));

        vm.expectRevert(WithdrawQueue.WithdrawQueue__ZeroAddress.selector);
        new WithdrawQueue(deployer, address(rolesAuthority), payable(address(vault)), address(teller), address(accountant), address(0));

        vm.stopPrank();
    }

    function test_constructor_setsImmutables() public view {
        assertEq(address(queue.VAULT()), address(vault));
        assertEq(address(queue.TELLER()), address(teller));
        assertEq(address(queue.ACCOUNTANT()), address(accountant));
        assertEq(address(queue.ASSET()), address(usde));
        assertEq(queue.MATURITY_PERIOD(), 259_200);
        assertEq(queue.MINIMUM_SHARES(), 1e6);
        assertEq(queue.nextRequestId(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                       REQUEST WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_requestWithdraw_revertsZeroShares() public {
        _deposit(user, 100e18);
        vm.prank(user);
        vm.expectRevert(WithdrawQueue.WithdrawQueue__ZeroShares.selector);
        queue.requestWithdraw(0);
    }

    function test_requestWithdraw_revertsBelowMinimum() public {
        _deposit(user, 100e18);
        vm.prank(user);
        vm.expectRevert(WithdrawQueue.WithdrawQueue__BelowMinimumShares.selector);
        queue.requestWithdraw(uint96(1e6 - 1)); // MINIMUM_SHARES - 1
    }

    function test_requestWithdraw_valid() public {
        uint96 amount = 100e18;
        _deposit(user, amount);

        vm.startPrank(user);
        ERC20(address(vault)).approve(address(queue), amount);

        vm.expectEmit(true, true, false, true);
        emit WithdrawRequested(1, user, amount);
        uint96 requestId = queue.requestWithdraw(amount);
        vm.stopPrank();

        assertEq(requestId, 1);
        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.balanceOf(address(queue)), amount);
        assertEq(queue.nextRequestId(), 2);

        WithdrawQueue.WithdrawRequest memory req = queue.getRequest(1);
        assertEq(req.user, user);
        assertEq(req.amountOfShares, amount);
        assertEq(req.creationTime, uint40(block.timestamp));
        assertFalse(req.completed);
    }

    /*//////////////////////////////////////////////////////////////
                       CANCEL WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_cancelWithdraw_revertsNotFound() public {
        vm.prank(user);
        vm.expectRevert(WithdrawQueue.WithdrawQueue__RequestNotFound.selector);
        queue.cancelWithdraw(999);
    }

    function test_cancelWithdraw_revertsNotOwner() public {
        uint96 amount = 100e18;
        _deposit(user, amount);
        _requestWithdraw(user, amount);

        vm.prank(user2);
        vm.expectRevert(WithdrawQueue.WithdrawQueue__NotRequestOwner.selector);
        queue.cancelWithdraw(1);
    }

    function test_cancelWithdraw_revertsAlreadyCompleted() public {
        uint96 amount = 100e18;
        _deposit(user, amount);
        _requestWithdraw(user, amount);

        vm.prank(user);
        queue.cancelWithdraw(1);

        vm.prank(user);
        vm.expectRevert(WithdrawQueue.WithdrawQueue__AlreadyCompleted.selector);
        queue.cancelWithdraw(1);
    }

    function test_cancelWithdraw_valid() public {
        uint96 amount = 100e18;
        _deposit(user, amount);
        _requestWithdraw(user, amount);

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit WithdrawCancelled(1, user, amount);
        queue.cancelWithdraw(1);

        assertEq(vault.balanceOf(user), amount);
        assertEq(vault.balanceOf(address(queue)), 0);
        assertTrue(queue.getRequest(1).completed);
    }

    /*//////////////////////////////////////////////////////////////
                       SOLVE WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_solveWithdraw_revertsUnauthorized() public {
        uint96 amount = 100e18;
        _deposit(user, amount);
        _requestWithdraw(user, amount);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        vm.prank(user);
        vm.expectRevert("UNAUTHORIZED");
        queue.solveWithdraw(ids);
    }

    function test_solveWithdraw_revertsNotMatured() public {
        uint96 amount = 100e18;
        _deposit(user, amount);
        _requestWithdraw(user, amount);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        // Only 1 day, need 3
        vm.warp(block.timestamp + 86400);

        vm.prank(solver);
        vm.expectRevert(WithdrawQueue.WithdrawQueue__NotMatured.selector);
        queue.solveWithdraw(ids);
    }

    function test_solveWithdraw_revertsAlreadyCompleted() public {
        uint96 amount = 100e18;
        _deposit(user, amount);
        _requestWithdraw(user, amount);

        // Cancel first
        vm.prank(user);
        queue.cancelWithdraw(1);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        vm.warp(block.timestamp + 259_200 + 1);

        vm.prank(solver);
        vm.expectRevert(WithdrawQueue.WithdrawQueue__AlreadyCompleted.selector);
        queue.solveWithdraw(ids);
    }

    function test_solveWithdraw_singleRequest() public {
        uint96 amount = 100e18;
        _deposit(user, amount);
        _requestWithdraw(user, amount);

        vm.warp(block.timestamp + 259_200 + 1);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        vm.prank(solver);
        queue.solveWithdraw(ids);

        assertEq(usde.balanceOf(user), amount);
        assertEq(vault.balanceOf(address(queue)), 0);
        assertTrue(queue.getRequest(1).completed);
    }

    function test_solveWithdraw_batchRequests() public {
        uint96 amount1 = 60e18;
        uint96 amount2 = 40e18;
        _deposit(user, amount1);
        _deposit(user2, amount2);
        _requestWithdraw(user, amount1);
        _requestWithdraw(user2, amount2);

        vm.warp(block.timestamp + 259_200 + 1);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        vm.prank(solver);
        queue.solveWithdraw(ids);

        assertEq(usde.balanceOf(user), amount1);
        assertEq(usde.balanceOf(user2), amount2);
        assertEq(vault.balanceOf(address(queue)), 0);
        assertTrue(queue.getRequest(1).completed);
        assertTrue(queue.getRequest(2).completed);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getRequest_returnsStruct() public {
        uint96 amount = 50e18;
        _deposit(user, amount);
        _requestWithdraw(user, amount);

        WithdrawQueue.WithdrawRequest memory req = queue.getRequest(1);
        assertEq(req.user, user);
        assertEq(req.amountOfShares, amount);
        assertFalse(req.completed);
    }

    function test_isMatured() public {
        uint96 amount = 50e18;
        _deposit(user, amount);
        _requestWithdraw(user, amount);

        assertFalse(queue.isMatured(1));
        assertFalse(queue.isMatured(999)); // nonexistent

        vm.warp(block.timestamp + 259_200);
        assertTrue(queue.isMatured(1));
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_requestAndCancel_returnsExactShares(uint96 amount) public {
        amount = uint96(bound(amount, queue.MINIMUM_SHARES(), 1e30));

        _deposit(user, amount);
        _requestWithdraw(user, amount);

        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.balanceOf(address(queue)), amount);

        vm.prank(user);
        queue.cancelWithdraw(1);

        assertEq(vault.balanceOf(user), amount);
        assertEq(vault.balanceOf(address(queue)), 0);
    }

    function testFuzz_solveOnlyAfterMaturity(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 259_200 * 3);

        uint96 amount = 100e18;
        _deposit(user, amount);
        uint256 requestTime = block.timestamp;
        _requestWithdraw(user, amount);

        vm.warp(requestTime + elapsed);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        if (elapsed < 259_200) {
            vm.prank(solver);
            vm.expectRevert(WithdrawQueue.WithdrawQueue__NotMatured.selector);
            queue.solveWithdraw(ids);
        } else {
            vm.prank(solver);
            queue.solveWithdraw(ids);
            assertEq(usde.balanceOf(user), amount);
        }
    }
}
