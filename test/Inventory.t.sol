// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../src/Inventory.sol";

contract InventoryTest is Test {
    Inventory inv;

    address admin = address(this);
    address operator = address(0xBEEF);
    address user = address(0xCAFE);

    function setUp() public {
        inv = new Inventory();
        // admin = address(this) because we deployed it from the test contract
    }

    /* ========= helpers ========= */

    function _addItem(string memory name, uint128 quantity) internal returns (uint256 itemId) {
        itemId = inv.addItem(name, quantity);
    }

    function _addDefaultItem(uint128 quantity) internal returns (uint256 itemId) {
        itemId = inv.addItem("Defauld", quantity);
    }

    function testAddItem_Success() public {
        uint128 qty = 100;
        uint256 itemId = inv.addItem("test", qty);

        Inventory.Item memory it = inv.getItem(itemId);

        assertTrue(it.exists);
        assertEq(it.quantity, qty);
        assertEq(it.reserved, 0);
        assertEq(it.name, "test");
        assertGt(it.createdAt, 0);
        assertEq(inv.totalItems(), 1);
    }

    function testAddItem_RevertIfQuantityZero() public {
        vm.expectRevert(Inventory.QuantityCantBeZero.selector);
        inv.addItem("test", 0);
    }

    function testReserveQuantity_SuccessByOperator() public {
        uint256 itemId = _addDefaultItem(100);

        inv.setOperator(operator, true);

        vm.prank(operator);
        inv.reserveQuantity(itemId, 30);

        Inventory.Item memory it = inv.getItem(itemId);

        assertTrue(it.exists);
        assertEq(it.quantity, 100);
        assertEq(it.reserved, 30);

        uint128 available = inv.getAvailableQuantity(itemId);
        assertEq(available, 70);
    }

    function testReserveQuantity_RevertIfNotEnoughAvailable() public {
        uint256 itemId = _addDefaultItem(50);
        inv.setOperator(operator, true);

        vm.prank(operator);
        inv.reserveQuantity(itemId, 40);

        vm.prank(operator);
        vm.expectRevert(Inventory.NotEnoughAvailable.selector);
        inv.reserveQuantity(itemId, 20); // only 10 available
    }

    function testReserveQuantity_RevertIfNotAuthorized() public {
        uint256 itemId = _addDefaultItem(100);

        vm.prank(user);
        vm.expectRevert(Inventory.NotAuthorized.selector);
        inv.reserveQuantity(itemId, 10);
    }

    function testFreeze_SetsStateFrozen() public {
        inv.freeze();
        assertEq(uint256(inv.state()), uint256(Inventory.State.Frozen));
    }

    function testReserveQuantity_RevertIfFrozen() public {
        uint256 itemId = _addDefaultItem(100);
        inv.setOperator(operator, true);

        inv.freeze();

        vm.prank(operator);
        vm.expectRevert(Inventory.NotActive.selector);
        inv.reserveQuantity(itemId, 10);
    }

    function testReleaseReservation_SuccessInFrozen() public {
        uint256 itemId = _addDefaultItem(100);
        inv.setOperator(operator, true);

        vm.prank(operator);
        inv.reserveQuantity(itemId, 40);

        inv.freeze();

        vm.prank(operator);
        inv.releaseReservation(itemId, 10);

        Inventory.Item memory it = inv.getItem(itemId);
        assertEq(it.reserved, 30);
    }

    function testFinalizeReservation_SuccessInFrozen() public {
        uint256 itemId = _addDefaultItem(100);
        inv.setOperator(operator, true);

        vm.prank(operator);
        inv.reserveQuantity(itemId, 40);

        inv.freeze();

        vm.prank(operator);
        inv.finalizeReservation(itemId, 15);

        Inventory.Item memory it = inv.getItem(itemId);
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
        inv.setOperator(operator, true);
    }

    function testAddItem_RevertIfFrozen() public {
        inv.freeze();

        vm.expectRevert(Inventory.NotActive.selector);
        inv.addItem("Frozen", 100);
    }

    function testFuzz_ReserveDoesNotExceedAvailable(uint128 qty, uint128 amount) public {
        qty = uint128(bound(qty, 1, 1_000_000));
        amount = uint128(bound(amount, 1, 2_000_000));

        uint256 itemId = _addDefaultItem(qty);
        inv.setOperator(operator, true);

        vm.prank(operator);
        if (amount > qty) {
            vm.expectRevert(Inventory.NotEnoughAvailable.selector);
            inv.reserveQuantity(itemId, amount);
        } else {
            inv.reserveQuantity(itemId, amount);
            Inventory.Item memory it = inv.getItem(itemId);
            assertLe(it.reserved, it.quantity);
        }
    }

    function testFruzz_ReleaseDoesNotUnderFlow(uint128 qty, uint128 reserveAmt, uint128 releaseAmt) public {
        qty = uint128(bound(qty, 1, 1_000_000));
        reserveAmt = uint128(bound(reserveAmt, 1, qty));
        releaseAmt = uint128(bound(releaseAmt, 1, reserveAmt));

        uint256 itemId = _addDefaultItem(qty);
        inv.setOperator(operator, true);

        vm.prank(operator);
        inv.reserveQuantity(itemId, reserveAmt);

        vm.prank(operator);
        inv.releaseReservation(itemId, releaseAmt);

        Inventory.Item memory it = inv.getItem(itemId);
        assertLe(it.reserved, it.quantity);
    }

    function testReleaseReservation_RevertIfNotEnoughReserved() public {
        uint256 itemId = _addDefaultItem(100);
        inv.setOperator(operator, true);

        vm.startPrank(operator);
        inv.reserveQuantity(itemId, 40);

        vm.expectRevert(Inventory.NotEnoughReserved.selector);
        inv.releaseReservation(itemId, 50);
        vm.stopPrank();
    }

    function testFrozen_PreventsReserveButAllowsRelease() public {
        uint256 itemId = _addDefaultItem(100);
        inv.setOperator(operator, true);

        vm.prank(operator);
        inv.reserveQuantity(itemId, 20);

        inv.freeze();

        vm.prank(operator);
        vm.expectRevert(Inventory.NotActive.selector);
        inv.reserveQuantity(itemId, 1);

        vm.prank(operator);
        inv.releaseReservation(itemId, 5);

        Inventory.Item memory it = inv.getItem(itemId);
        assertEq(it.reserved, 15);
    }
}
