// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../src/Inventory.sol";

contract InventoryTest is Test {
    Inventory inv;

    address admin = address(this);
    address operator = address(0xBEEF);
    address user = address(0xCAFE);

    uint256 constant ITEM_ID = 1;

    function setUp() public {
        inv = new Inventory();
        // admin = address(this) because we deployed it from the test contract
    }

    /* ========= helpers ========= */
    function _addDefaultItem(uint128 quantity) internal {
        inv.addItem(ITEM_ID, quantity);
    }

    function testAddItem_Success() public {
        uint128 qty = 100;

        inv.addItem(ITEM_ID, qty);

        Inventory.Item memory it = inv.getItem(ITEM_ID);

        assertTrue(it.exists);
        assertEq(it.quantity, qty);
        assertEq(it.reserved, 0);
        assertEq(inv.totalItems(), 1);
    }

    function testAddItem_RevertIfQuantityZero() public {
        vm.expectRevert(Inventory.QuantityCantBeZero.selector);
        inv.addItem(ITEM_ID, 0);
    }

    function testAddItem_RevertIfItemAlreadyExists() public {
        inv.addItem(ITEM_ID, 10);

        vm.expectRevert(Inventory.ItemAlreadyExist.selector);
        inv.addItem(ITEM_ID, 10);
    }

    function testReserveQuantity_SuccessByOperator() public {
        _addDefaultItem(100);

        inv.setOperator(operator);

        vm.prank(operator);
        inv.reserveQuantity(ITEM_ID, 30);

        Inventory.Item memory it = inv.getItem(ITEM_ID);

        assertTrue(it.exists);
        assertEq(it.quantity, 100);
        assertEq(it.reserved, 30);

        uint128 available = inv.getAvailableQuantity(ITEM_ID);
        assertEq(available, 70);
    }

    function testReserveQuantity_RevertIfNotEnoughAvailable() public {
        _addDefaultItem(50);
        inv.setOperator(operator);

        vm.prank(operator);
        inv.reserveQuantity(ITEM_ID, 40);

        vm.prank(operator);
        vm.expectRevert(Inventory.NotEnoughAvailable.selector);
        inv.reserveQuantity(ITEM_ID, 20); // only 10 available
    }

    function testReserveQuantity_RevertIfNotAuthorized() public {
        _addDefaultItem(100);

        vm.prank(user);
        vm.expectRevert(Inventory.NotAuthorized.selector);
        inv.reserveQuantity(ITEM_ID, 10);
    }

    function testFreeze_SetsStateFrozen() public {
        inv.freeze();
        assertEq(uint256(inv.state()), uint256(Inventory.State.Frozen));
    }

    function testReserveQuantity_RevertIfFrozen() public {
        _addDefaultItem(100);
        inv.setOperator(operator);

        inv.freeze();

        vm.prank(operator);
        vm.expectRevert(Inventory.NotActive.selector);
        inv.reserveQuantity(ITEM_ID, 10);
    }

    function testReleaseReservation_SuccessInFrozen() public {
        _addDefaultItem(100);
        inv.setOperator(operator);

        vm.prank(operator);
        inv.reserveQuantity(ITEM_ID, 40);

        inv.freeze();

        vm.prank(operator);
        inv.releaseReservation(ITEM_ID, 10);

        Inventory.Item memory it = inv.getItem(ITEM_ID);
        assertEq(it.reserved, 30);
    }

    function testFinalizeReservation_SuccessInFrozen() public {
        _addDefaultItem(100);
        inv.setOperator(operator);

        vm.prank(operator);
        inv.reserveQuantity(ITEM_ID, 40);

        inv.freeze();

        vm.prank(operator);
        inv.finalizeReservation(ITEM_ID, 15);

        Inventory.Item memory it = inv.getItem(ITEM_ID);
        assertEq(it.quantity, 85);
        assertEq(it.reserved, 25);
    }

    function testUnfreeze_ReturnsToActive() public {
        inv.freeze();
        inv.unfreeze();

        assertEq(uint256(inv.state()), uint256(Inventory.State.Active));
    }

    function testSetOperator_RevertIfFrozen() public {
        inv.freeze();

        vm.expectRevert(Inventory.NotActive.selector);
        inv.setOperator(operator);
    }

    function testAddItem_RevertIfFrozen() public {
        inv.freeze();

        vm.expectRevert(Inventory.NotActive.selector);
        inv.addItem(ITEM_ID, 100);
    }

    function testFuzz_ReserveDoesNotExceedAvailable(uint128 qty, uint128 amount) public {
        qty = uint128(bound(qty, 1, 1_000_000));
        amount = uint128(bound(amount, 1, 2_000_000));

        _addDefaultItem(qty);
        inv.setOperator(operator);

        vm.prank(operator);
        if (amount > qty) {
            vm.expectRevert(Inventory.NotEnoughAvailable.selector);
            inv.reserveQuantity(ITEM_ID, amount);
        } else {
            inv.reserveQuantity(ITEM_ID, amount);
            Inventory.Item memory it = inv.getItem(ITEM_ID);
            assertLe(it.reserved, it.quantity);
        }
    }

    function testFruzz_ReleaseDoesNotUnderFlow(uint128 qty, uint128 reserveAmt, uint128 releaseAmt) public {
        qty = uint128(bound(qty, 1, 1_000_000));
        reserveAmt = uint128(bound(reserveAmt, 1, qty));
        releaseAmt = uint128(bound(releaseAmt, 1, reserveAmt));

        _addDefaultItem(qty);
        inv.setOperator(operator);

        vm.prank(operator);
        inv.reserveQuantity(ITEM_ID, reserveAmt);

        vm.prank(operator);
        inv.releaseReservation(ITEM_ID, releaseAmt);

        Inventory.Item memory it = inv.getItem(ITEM_ID);
        assertLe(it.reserved, it.quantity);
    }

    function testReleaseReservation_RevertIfNotEnoughReserved() public {
        _addDefaultItem(100);
        inv.setOperator(operator);

        vm.startPrank(operator);
        inv.reserveQuantity(ITEM_ID, 40);

        vm.expectRevert(Inventory.NotEnoughReserved.selector);
        inv.releaseReservation(ITEM_ID, 50);
        vm.stopPrank();
    }

    function testFrozen_PreventsReserveButAllowsRelease() public {
        _addDefaultItem(100);
        inv.setOperator(operator);

        vm.prank(operator);
        inv.reserveQuantity(ITEM_ID, 20);

        inv.freeze();

        vm.prank(operator);
        vm.expectRevert(Inventory.NotActive.selector);
        inv.reserveQuantity(ITEM_ID, 1);

        vm.prank(operator);
        inv.releaseReservation(ITEM_ID, 5);

        Inventory.Item memory it = inv.getItem(ITEM_ID);
        assertEq(it.reserved, 15);
    }
}
