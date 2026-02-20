// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {BoringVault} from "@boring-vault/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/base/Roles/TellerWithMultiAssetSupport.sol";
import {AccountantWithRateProviders} from "@boring-vault/base/Roles/AccountantWithRateProviders.sol";

contract WithdrawQueue is Auth {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error WithdrawQueue__ZeroAddress();
    error WithdrawQueue__ZeroShares();
    error WithdrawQueue__BelowMinimumShares();
    error WithdrawQueue__RequestNotFound();
    error WithdrawQueue__NotRequestOwner();
    error WithdrawQueue__AlreadyCompleted();
    error WithdrawQueue__NotMatured();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event WithdrawRequested(uint96 indexed requestId, address indexed user, uint96 amountOfShares);
    event WithdrawCancelled(uint96 indexed requestId, address indexed user, uint96 amountOfShares);
    event WithdrawSolved(uint96 indexed requestId, address indexed user, uint96 amountOfShares, uint256 assetsOut);

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct WithdrawRequest {
        address user;           // 20 bytes ─┐ slot 0
        uint96  amountOfShares; // 12 bytes ─┘
        uint40  creationTime;   //  5 bytes ─┐ slot 1
        bool    completed;      //  1 byte  ─┘
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    BoringVault public immutable VAULT;
    TellerWithMultiAssetSupport public immutable TELLER;
    AccountantWithRateProviders public immutable ACCOUNTANT;
    ERC20 public immutable ASSET;
    uint256 internal immutable ONE_SHARE;

    uint24 public constant MATURITY_PERIOD = 259_200; // 3 days
    uint96 public constant MINIMUM_SHARES = 1e6;

    uint96 public nextRequestId = 1;
    mapping(uint256 => WithdrawRequest) public withdrawRequests;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _owner,
        address _auth,
        address payable _vault,
        address _teller,
        address _accountant,
        address _asset
    ) Auth(_owner, Authority(_auth)) {
        if (_vault == address(0) || _teller == address(0) || _accountant == address(0) || _asset == address(0)) {
            revert WithdrawQueue__ZeroAddress();
        }
        VAULT = BoringVault(_vault);
        TELLER = TellerWithMultiAssetSupport(_teller);
        ACCOUNTANT = AccountantWithRateProviders(_accountant);
        ASSET = ERC20(_asset);
        ONE_SHARE = 10 ** BoringVault(_vault).decimals();
    }

    /*//////////////////////////////////////////////////////////////
                           PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Request a withdrawal by locking vault shares in this contract.
    function requestWithdraw(uint96 amountOfShares) external returns (uint96 requestId) {
        if (amountOfShares == 0) revert WithdrawQueue__ZeroShares();
        if (amountOfShares < MINIMUM_SHARES) revert WithdrawQueue__BelowMinimumShares();

        requestId = nextRequestId++;

        withdrawRequests[requestId] = WithdrawRequest({
            user: msg.sender,
            amountOfShares: amountOfShares,
            creationTime: uint40(block.timestamp),
            completed: false
        });

        ERC20(address(VAULT)).safeTransferFrom(msg.sender, address(this), amountOfShares);

        emit WithdrawRequested(requestId, msg.sender, amountOfShares);
    }

    // Cancel a pending withdrawal and reclaim vault shares.
    function cancelWithdraw(uint256 requestId) external {
        WithdrawRequest storage req = withdrawRequests[requestId];
        if (req.user == address(0)) revert WithdrawQueue__RequestNotFound();
        if (req.user != msg.sender) revert WithdrawQueue__NotRequestOwner();
        if (req.completed) revert WithdrawQueue__AlreadyCompleted();

        req.completed = true;

        ERC20(address(VAULT)).safeTransfer(msg.sender, req.amountOfShares);

        emit WithdrawCancelled(uint96(requestId), msg.sender, req.amountOfShares);
    }

    // Solve matured withdrawal requests. Redeems shares via the Teller
    // and distributes the underlying asset pro-rata.
    function solveWithdraw(uint256[] calldata requestIds) external requiresAuth {
        uint256 totalShares;

        // Validate all requests and accumulate total shares.
        for (uint256 i; i < requestIds.length; ++i) {
            WithdrawRequest storage req = withdrawRequests[requestIds[i]];
            if (req.user == address(0)) revert WithdrawQueue__RequestNotFound();
            if (req.completed) revert WithdrawQueue__AlreadyCompleted();
            if (block.timestamp < req.creationTime + MATURITY_PERIOD) revert WithdrawQueue__NotMatured();

            totalShares += req.amountOfShares;
        }

        // Approve shares to the vault (Teller calls vault.exit which burns from msg.sender).
        ERC20(address(VAULT)).safeApprove(address(VAULT), totalShares);

        // Redeem all shares in one call.
        uint256 totalAssets = TELLER.bulkWithdraw(ASSET, totalShares, 0, address(this));

        // Distribute pro-rata to each user.
        for (uint256 i; i < requestIds.length; ++i) {
            WithdrawRequest storage req = withdrawRequests[requestIds[i]];
            req.completed = true;

            uint256 userAssets = totalAssets.mulDivDown(req.amountOfShares, totalShares);
            ASSET.safeTransfer(req.user, userAssets);

            emit WithdrawSolved(uint96(requestIds[i]), req.user, req.amountOfShares, userAssets);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getRequest(uint256 requestId) external view returns (WithdrawRequest memory) {
        return withdrawRequests[requestId];
    }

    function isMatured(uint256 requestId) external view returns (bool) {
        WithdrawRequest storage req = withdrawRequests[requestId];
        return req.user != address(0) && block.timestamp >= req.creationTime + MATURITY_PERIOD;
    }
}
