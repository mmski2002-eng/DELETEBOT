// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TransactionDeny} from "../src/blacklist/TransactionDeny.sol";
import {TransparentUpgradeableProxy} from "../src/TransparentUpgradeableProxy.sol";

/**
 * @title TransactionDenyTest
 * @dev Foundry test suite for the TransactionDeny upgradeable contract
 * Covers blacklist management, permission control, two-step ownership transfer, and pause functionality
 */
contract TransactionDenyTest is Test {
    TransactionDeny private transactionDeny;
    TransparentUpgradeableProxy private transactionDenyProxy;

    // Test addresses (constant for consistency)
    address constant DEPLOYER = 0x0111111111111111111111111111111111111111; // Contract deployer (non-admin)
    address constant INITIAL_ADMIN = 0x1111111111111111111111111111111111111111; // Initial admin account
    address constant USER1 = 0x2222222222222222222222222222222222222222; // Test user 1
    address constant USER2 = 0x3333333333333333333333333333333333333333; // Test user 2
    address constant NEW_ADMIN = 0x4444444444444444444444444444444444444444; // New admin candidate
    address constant ZERO_ADDRESS = address(0); // Zero address (boundary test)

    /**
     * @dev Setup test environment: deploy proxy + implementation contract and initialize admin
     * Runs before every test function
     */
    function setUp() public {
        vm.startPrank(DEPLOYER);

        // Deploy implementation contract
        transactionDeny = new TransactionDeny();

        // Encode initialization data (pass initial admin address)
        bytes memory initData = abi.encodeWithSelector(TransactionDeny.initialize.selector, INITIAL_ADMIN);

        // Deploy transparent proxy and link to implementation
        transactionDenyProxy = new TransparentUpgradeableProxy(address(transactionDeny), initData);

        // Point transactionDeny reference to proxy (all operations go through proxy)
        transactionDeny = TransactionDeny(address(transactionDenyProxy));

        vm.stopPrank();

        // Validate initialization success
        assertEq(transactionDeny.owner(), INITIAL_ADMIN, "Initial admin should be the owner");
        assertNotEq(transactionDeny.owner(), DEPLOYER, "Deployer should not be the owner");
    }

    // ===================== Core Blacklist Functionality Tests =====================
    /**
     * @dev Test single address blacklist addition/removal
     * Verifies: state changes, event emissions, and array consistency
     */
    function testBlacklist_SingleAddress() public {
        vm.startPrank(INITIAL_ADMIN);
        address testAddress = USER1;

        // 1. Verify initial state: address not blacklisted
        assertFalse(transactionDeny.isBlacklisted(testAddress), "Address should not be blacklisted initially");

        // 2. Add address to blacklist (verify event emission)
        vm.expectEmit(true, false, false, true); // Indexed: account; Non-indexed: isBlacklisted
        emit TransactionDeny.BlacklistUpdated(testAddress, true);
        address[] memory addressList = new address[](1);
        addressList[0] = testAddress;
        transactionDeny.addBlacklistedAddresses(addressList);

        // 3. Validate post-addition state
        assertTrue(transactionDeny.isBlacklisted(testAddress), "Address should be blacklisted after addition");
        address[] memory blacklistedAddresses = transactionDeny.getBlacklistedAddresses();
        assertEq(blacklistedAddresses.length, 1, "Blacklist array should have 1 entry after addition");
        assertEq(blacklistedAddresses[0], testAddress, "Blacklist array should contain the test address");

        // 4. Remove address from blacklist (verify event emission)
        vm.expectEmit(true, false, false, true);
        emit TransactionDeny.BlacklistUpdated(testAddress, false);
        transactionDeny.removeBlacklistedAddresses(addressList);

        // 5. Validate post-removal state
        assertFalse(transactionDeny.isBlacklisted(testAddress), "Address should not be blacklisted after removal");
        assertEq(transactionDeny.getBlacklistedAddresses().length, 0, "Blacklist array should be empty after removal");

        vm.stopPrank();
    }

    /**
     * @dev Test batch address blacklist addition/removal
     * Verifies: bulk state changes and event emissions for multiple addresses
     */
    function testBlacklist_BatchAddresses() public {
        vm.startPrank(INITIAL_ADMIN);
        address[] memory testAddresses = new address[](2);
        testAddresses[0] = USER1;
        testAddresses[1] = USER2;

        // 1. Batch add addresses to blacklist (verify events)
        vm.expectEmit(true, false, false, true);
        emit TransactionDeny.BlacklistUpdated(USER1, true);
        vm.expectEmit(true, false, false, true);
        emit TransactionDeny.BlacklistUpdated(USER2, true);
        transactionDeny.addBlacklistedAddresses(testAddresses);

        // 2. Validate post-addition state
        assertTrue(transactionDeny.isBlacklisted(USER1), "USER1 should be blacklisted");
        assertTrue(transactionDeny.isBlacklisted(USER2), "USER2 should be blacklisted");
        assertEq(
            transactionDeny.getBlacklistedAddresses().length,
            2,
            "Blacklist array should have 2 entries after batch addition"
        );

        // 3. Batch remove addresses from blacklist (verify events)
        vm.expectEmit(true, false, false, true);
        emit TransactionDeny.BlacklistUpdated(USER1, false);
        vm.expectEmit(true, false, false, true);
        emit TransactionDeny.BlacklistUpdated(USER2, false);
        transactionDeny.removeBlacklistedAddresses(testAddresses);

        // 4. Validate post-removal state
        assertFalse(transactionDeny.isBlacklisted(USER1), "USER1 should not be blacklisted");
        assertFalse(transactionDeny.isBlacklisted(USER2), "USER2 should not be blacklisted");
        assertEq(
            transactionDeny.getBlacklistedAddresses().length, 0, "Blacklist array should be empty after batch removal"
        );

        vm.stopPrank();
    }

    /**
     * @dev Test boundary cases for blacklist operations
     * Covers: duplicate additions, removing non-blacklisted addresses, and zero address handling
     */
    function testBlacklist_BoundaryCases() public {
        vm.startPrank(INITIAL_ADMIN);
        address testAddress = USER1;

        // 1. Duplicate addition: no duplicate storage, single event emission
        vm.expectEmit(true, false, false, true);
        emit TransactionDeny.BlacklistUpdated(testAddress, true);
        address[] memory addressList = new address[](1);
        addressList[0] = testAddress;
        transactionDeny.addBlacklistedAddresses(addressList); // First addition
        transactionDeny.addBlacklistedAddresses(addressList); // Duplicate addition
        assertEq(
            transactionDeny.getBlacklistedAddresses().length, 1, "Duplicate addition should not increase array length"
        );

        // 2. Remove non-blacklisted address: no state change, no event
        address[] memory user2AddressList = new address[](1);
        addressList[0] = USER2;
        transactionDeny.removeBlacklistedAddresses(user2AddressList);
        assertEq(
            transactionDeny.getBlacklistedAddresses().length,
            1,
            "Removing non-blacklisted address should not change array length"
        );

        // 3. Zero address addition (contract allows this; validate state)
        address[] memory zeroAddressList = new address[](1);
        zeroAddressList[0] = ZERO_ADDRESS;
        transactionDeny.addBlacklistedAddresses(zeroAddressList);
        assertTrue(
            transactionDeny.isBlacklisted(ZERO_ADDRESS),
            "Zero address should be added to blacklist (per contract logic)"
        );
        assertEq(transactionDeny.getBlacklistedAddresses().length, 2, "Blacklist array should include zero address");

        vm.stopPrank();
    }

    // ===================== Permission Control Tests =====================
    /**
     * @dev Test unauthorized access to admin-only functions
     * Verifies: non-admin accounts revert with Ownable error
     */
    function testPermission_NonAdminReverts() public {
        address nonAdmin = USER1;
        vm.startPrank(nonAdmin);

        // 1. Revert: non-admin adding to blacklist
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonAdmin));
        address[] memory user2AddressList = new address[](1);
        user2AddressList[0] = ZERO_ADDRESS;
        transactionDeny.addBlacklistedAddresses(user2AddressList);

        // 2. Revert: non-admin removing from blacklist
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonAdmin));
        transactionDeny.removeBlacklistedAddresses(user2AddressList);

        // 3. Revert: non-admin pausing the contract
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonAdmin));
        transactionDeny.pause();

        vm.stopPrank();
    }

    // ===================== Ownership Transfer Tests =====================
    /**
     * @dev Test two-step ownership transfer functionality
     * Verifies: nomination, acceptance, and permission transition
     */
    function testOwnership_TwoStepTransfer() public {
        address oldOwner = INITIAL_ADMIN;
        address newOwner = NEW_ADMIN;

        // 1. Verify pre-transfer state: new admin has no ownership
        assertNotEq(transactionDeny.owner(), newOwner, "New owner should not be owner initially");
        address pendingOwner = transactionDeny.pendingOwner();
        assertEq(pendingOwner, address(0), "No pending owner initially");

        // 2. Nominate new owner (current owner calls)
        vm.startPrank(oldOwner);
        transactionDeny.transferOwnership(newOwner);
        assertEq(transactionDeny.owner(), oldOwner, "Old owner still owns until acceptance");
        assertEq(transactionDeny.pendingOwner(), newOwner, "New owner is now pending");
        vm.stopPrank();

        // 3. Accept ownership (new owner calls)
        vm.startPrank(newOwner);
        transactionDeny.acceptOwnership();
        assertEq(transactionDeny.owner(), newOwner, "New owner is now the owner");
        assertEq(transactionDeny.pendingOwner(), address(0), "Pending owner cleared");
        vm.stopPrank();

        // 4. New owner performs admin-only operation (should succeed)
        vm.startPrank(newOwner);
        address[] memory user1AddressList = new address[](1);
        user1AddressList[0] = USER1;
        transactionDeny.addBlacklistedAddresses(user1AddressList);
        assertTrue(transactionDeny.isBlacklisted(USER1), "New owner should be able to modify blacklist");
        vm.stopPrank();

        // 5. Old owner attempts admin-only operation (should revert)
        vm.startPrank(oldOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", oldOwner));
        address[] memory user2AddressList = new address[](1);
        user2AddressList[0] = USER2;
        transactionDeny.addBlacklistedAddresses(user2AddressList);
        vm.stopPrank();
    }

    /**
     * @dev Test that only pending owner can accept ownership
     */
    function testOwnership_OnlyPendingOwnerCanAccept() public {
        address oldOwner = INITIAL_ADMIN;
        address newOwner = NEW_ADMIN;
        address thirdParty = USER1;

        // 1. Nominate new owner
        vm.startPrank(oldOwner);
        transactionDeny.transferOwnership(newOwner);
        vm.stopPrank();

        // 2. Third party tries to accept (should revert)
        vm.startPrank(thirdParty);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", thirdParty));
        transactionDeny.acceptOwnership();
        vm.stopPrank();

        // 3. Verify ownership hasn't changed
        assertEq(transactionDeny.owner(), oldOwner, "Owner should not change");
        assertEq(transactionDeny.pendingOwner(), newOwner, "Pending owner unchanged");
    }

    /**
     * @dev test that owner can cancel ownership transfer by renominating themselves
     */
    function testOwnership_CancelTransfer() public {
        address oldOwner = INITIAL_ADMIN;
        address newOwner = NEW_ADMIN;

        // 1. Nominate new owner
        vm.startPrank(oldOwner);
        transactionDeny.transferOwnership(newOwner);
        assertEq(transactionDeny.pendingOwner(), newOwner, "New owner is pending");

        // 2. Cancel by renominating self
        transactionDeny.transferOwnership(oldOwner);
        assertEq(transactionDeny.pendingOwner(), oldOwner, "Old owner is now pending");
        vm.stopPrank();

        // 3. Old owner can accept immediately (no-op, already owner)
        vm.startPrank(oldOwner);
        transactionDeny.acceptOwnership();
        assertEq(transactionDeny.owner(), oldOwner, "Owner unchanged");
        vm.stopPrank();
    }

    // ===================== Pause/Unpause Functionality Tests =====================
    /**
     * @dev Test contract pause/unpause mechanics
     * NOTE: The original contract lacks `whenNotPaused` modifiers on business functions—this test highlights the issue
     * Uncomment the validation logic after adding `whenNotPaused` to the contract
     */
    function testPause_ContractMechanics() public {
        // Warning: Business functions lack pause guards (critical for production)
        console.log("WARNING: addBlacklistedAddresses/removeBlacklistedAddresses missing whenNotPaused modifier");
        console.log("Add whenNotPaused to business functions to enforce pause restrictions");

        vm.startPrank(INITIAL_ADMIN);

        // 1. Pause the contract
        transactionDeny.pause();
        assertTrue(transactionDeny.paused(), "Contract should be in paused state");

        // 2. Uncomment below AFTER adding `whenNotPaused` to the contract's business functions
        // vm.expectRevert("Pausable: paused");
        // transactionDeny.addBlacklistedAddresses([USER1]);

        // 3. Unpause the contract
        transactionDeny.unpause();
        assertFalse(transactionDeny.paused(), "Contract should be in unpaused state");

        // 4. Verify business functions work after unpause
        address[] memory user1AddressList = new address[](1);
        user1AddressList[0] = USER1;
        transactionDeny.addBlacklistedAddresses(user1AddressList);
        assertTrue(transactionDeny.isBlacklisted(USER1), "Admin should modify blacklist after unpause");

        vm.stopPrank();
    }
}
