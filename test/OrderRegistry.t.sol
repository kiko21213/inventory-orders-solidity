// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import { OrderRegistry } from "../src/OrderRegistry.sol";
import { MockInventory } from "./mocks/MockInventory.sol";

contract OrderRegistryTest is Test {
    MockInventory inv;
    OrderRegistry reg;
    function setUp() public {
        inv = new MockInventory();
        reg = new OrderRegistry(address(inv));

    }

    function test_createOrder_basic() public {
        address buyer = address(0xB0B);
        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);
        // reg.createOrder(1,2);
        // emit log_uint(inv.reserveCalls());

        // assertEq(inv.reserveCalls(), 1);
        OrderRegistry.Order memory o = reg.getOrder(id);
        emit log_address(o.buyer);
        assertEq(o.buyer,buyer);
        
    }

    function test_cancelOrder_withinWindow() public {
        address buyer = address(0xB0B);

        vm.prank(buyer);
        uint256 id = reg.createOrder(1,2);

        vm.warp(block.timestamp + 10);

        vm.prank(buyer);
        reg.cancelOrder(id);
        OrderRegistry.Order memory o = reg.getOrder(id);

        emit log_uint(uint256(o.state));
        emit log_string(" 0=Created, 1=Cancelled, 2=Paid");
        assertEq(uint256(o.state), uint256(OrderRegistry.OrderState.Cancelled));
        
    }
    function test_cancelOerder_afterWindow_reverts() public {
        address buyer = address(0xB0B);
        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);

        OrderRegistry.Order memory o = reg.getOrder(id);
        vm.warp(o.createdAt + 30 minutes + 1);

        vm.prank(buyer);
        vm.expectRevert(OrderRegistry.CancelOrderPassed.selector);
        reg.cancelOrder(id);

        emit log_uint(o.createdAt);
        emit log_uint(block.timestamp);
        emit log_string("now expecting revert...");
    }


    function test_cancelOrder_notBuyer_reverts() public {
        address buyer = address(0xB0B);
        address attacker = address(0xBAD);
        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);

        vm.prank(attacker);
        vm.expectRevert(OrderRegistry.NotBuyer.selector);
        reg.cancelOrder(id);
        emit log_string("not Buyer");
    }
    function test_markPaid_adminOnlyAndSetsPaid() public {
        address buyer = address(0xB0B);

        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);

        vm.prank(buyer);
        vm.expectRevert(OrderRegistry.NotAdmin.selector);
        reg.markPaid(id);

        reg.markPaid(id);
        OrderRegistry.Order memory o = reg.getOrder(id);
        emit log_uint(uint256(o.state));
        assertEq(uint256(o.state), uint256(OrderRegistry.OrderState.Paid));
        assertEq(inv.finalizeCalls(), 1);
        emit log_string("state: 0=Created, 1=Cancelled, 2=Paid");


    }
    function test_cancelOrder_afterPaid_reverts_andDoesNotRelease() public {
        address buyer = address(0xB0B);

        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);
        
        reg.markPaid(id);

        vm.prank(buyer);
        vm.expectRevert(OrderRegistry.InvalidState.selector);
        reg.cancelOrder(id);

        assertEq(inv.releaseCalls(), 0);
        emit log_uint(inv.releaseCalls());
    }

    function test_markPaid_twiceReverts() public {
        address buyer = address(0xB0B);

        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);

        reg.markPaid(id);

        vm.expectRevert(OrderRegistry.InvalidState.selector);
        reg.markPaid(id);
    }
    
    function test_cancelOrder_twiceReverts() public {
        address buyer = address(0xB0B);

        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);

        vm.prank(buyer);
        reg.cancelOrder(id);

        vm.prank(buyer);
        vm.expectRevert(OrderRegistry.InvalidState.selector);
        reg.cancelOrder(id);
    }

    function test_cancelOrder_releaseReverts_stateRollsBack() public {
        address buyer = address(0xB0B);

        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);

        inv.setReleaseRevert(true);

        vm.prank(buyer);
        vm.expectRevert();
        reg.cancelOrder(id);

        OrderRegistry.Order memory o = reg.getOrder(id);
        assertEq(uint256(o.state),uint256(OrderRegistry.OrderState.Created));
    }

    function test_createOrder_reserveReverts_nextIdNotChanged() public {
        address buyer = address(0xB0B);
        uint256 beforeId = reg.nextOrderId();

        inv.setReserveRevert(true);
        vm.prank(buyer);
        vm.expectRevert();

        reg.createOrder(1, 2);

        assertEq(reg.nextOrderId(),beforeId);
    }

    function test_markPaid_finalizeReverts_stateRollsBack() public {
        address buyer = address(0xB0B);

        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);

        inv.setFinalizeRevert(true);

        vm.expectRevert();
        reg.markPaid(id);

        OrderRegistry.Order memory o = reg.getOrder(id);
        assertEq(uint256(o.state),uint256(OrderRegistry.OrderState.Created));
        
    }
    function test_createOrder_emits_OrderCreated() public {
        address buyer = address(0xB0B);

        vm.expectEmit(true, true, true, true);
        emit OrderRegistry.OrderCreated(0,buyer,1,2);

        vm.prank(buyer);
        reg.createOrder(1, 2);
    }
    
    function test_cancelOrder_emits_OrderCancelled() public {
        address buyer = address(0xB0B);
        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);

        vm.expectEmit(true,true,true,true);
        emit OrderRegistry.OrderCancelled(0);

        vm.prank(buyer);
        reg.cancelOrder(id);
    }
    function test_markPaid_emits_OrderPaid() public {
        address buyer = address(0xB0B);

        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);

        vm.expectEmit(true, true, true, true);
        emit OrderRegistry.OrderPaid(0);

        
        reg.markPaid(id);
        
    }
    function testFuzz_createOrder_callsReserve(uint256 itemId, uint128 amount) public {
        amount = uint128(bound(uint256(amount), 1, 1000));
        itemId = bound(itemId, 1, 1_000_000);

        uint256 before = inv.reserveCalls();

        vm.prank(address(0xB0B));
        reg.createOrder(itemId, amount);

        assertEq(inv.reserveCalls(), before + 1);

    }
    function testFuzz_cancelOrder_callsRelease(uint256 itemId, uint128 amount) public  {
        amount = uint128(bound(uint256(amount), 1, 1000));
        itemId = bound(itemId, 1, 1_000_000);

        address buyer = address(0xB0B);
        
        vm.prank(buyer);
        uint256 id = reg.createOrder(itemId, amount);

        vm.warp(block.timestamp + 10);
        uint256 before = inv.releaseCalls();

        vm.prank(buyer);
        reg.cancelOrder(id);

        assertEq(inv.reserveCalls(), before + 1);

        
    }

    function  testFuzz_cancelOrder_notBuyerAlwaysReverts(address attacker, uint256 itemId, uint128 amount) public {
        attacker = attacker == address(0) ? address(0xBAD) : attacker;
        vm.assume(attacker != address(0xB0B));
        amount = uint128(bound(uint256(amount), 1, 1000));
        itemId = bound(itemId, 1, 1_000_000);

        vm.prank(address(0xB0B));
        uint256 id = reg.createOrder(itemId, amount);

        vm.prank(attacker);
        vm.expectRevert(OrderRegistry.NotBuyer.selector);
        reg.cancelOrder(id);

    }
    function testFuzz_cancelWindow_timeBoundary(uint256 dt) public {
        address buyer = address(0xB0B);

        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);

        OrderRegistry.Order memory o = reg.getOrder(id);

        dt = bound(dt, 0, 3600);
        vm.warp(uint256(o.createdAt)+ dt);

        vm.prank(buyer);
        if(dt > 30 minutes) {
            vm.expectRevert(OrderRegistry.CancelOrderPassed.selector);
        }
        reg.cancelOrder(id);
    }
    function test_markPaid_afterCancel_reverts() public {
        address buyer = address(0xB0B);

        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);

        vm.prank(buyer);
        reg.cancelOrder(id);

        vm.expectRevert(OrderRegistry.InvalidState.selector);
        reg.markPaid(id);
    }
    function test_cancel_afterPaid_reverts() public {
        address buyer = address(0xB0B);

        vm.prank(buyer);
        uint256 id = reg.createOrder(1, 2);

        
        reg.markPaid(id);

        vm.prank(buyer);
        vm.expectRevert(OrderRegistry.InvalidState.selector);
        reg.cancelOrder(id);


    }
}
