// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import {OrderRegistry} from "../src/OrderRegistry.sol";
import {MockInventory} from "./mocks/MockInventory.sol";

contract OrderRegistryTest is Test {
    MockInventory inv;
    OrderRegistry reg;

    address buyer = address(0xB0B);
    address attacker = address(0xBAD);

    uint64 constant WINDOW_VIP = 10 minutes;
    uint64 constant WINDOW_NON_VIP = 30 minutes;

    function setUp() public {
        inv = new MockInventory();
        reg = new OrderRegistry(address(inv));
    }

    function _createNonVip() internal returns (uint256 id){
        vm.prank(buyer);

        id = reg.createOrder(1,2, WINDOW_NON_VIP);
    }

    function _createVip() internal returns(uint256 id){
        vm.prank(buyer);

        id = reg.createOrder(1, 2, WINDOW_VIP);
    }

    function test_createOrder_basic() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();
        OrderRegistry.Order memory o = reg.getOrder(id);
        emit log_address(o.buyer);
        assertEq(o.buyer, buyer);
    }

    function test_cancelOrder_withinWindow() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        vm.warp(block.timestamp + 29);

        vm.prank(buyer);
        reg.cancelOrder(id);
        OrderRegistry.Order memory o = reg.getOrder(id);

        emit log_uint(uint256(o.state));
        emit log_string(" 0=Created, 1=Cancelled, 2=Paid");
        assertEq(uint256(o.state), uint256(OrderRegistry.OrderState.Cancelled));
    }
    function test_cancelOrder_vip_withinWindow() public {
        uint256 id = _createVip();
        vm.warp(block.timestamp + 9 minutes);
        vm.prank(buyer);
        reg.cancelOrder(id);
        assertEq(uint256(reg.getOrder(id).state), uint256(OrderRegistry.OrderState.Cancelled));
    }

    function test_cancelOrder_afterWindow_reverts() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        OrderRegistry.Order memory o = reg.getOrder(id);
        vm.warp(o.createdAt + WINDOW_NON_VIP + 1);

        vm.prank(buyer);
        vm.expectRevert(OrderRegistry.CancelOrderPassed.selector);
        reg.cancelOrder(id);

        emit log_uint(o.createdAt);
        emit log_uint(block.timestamp);
        emit log_string("now expecting revert...");
    }
    function test_cancelOrder_vip_aftherWindow_reverts() public {
        vm.prank(buyer);
        uint256 id = _createVip();
        OrderRegistry.Order memory o = reg.getOrder(id);
        vm.warp(o.createdAt + WINDOW_VIP + 1);
        vm.prank(buyer);
        vm.expectRevert(OrderRegistry.CancelOrderPassed.selector);
        reg.cancelOrder(id);
    }

    function test_cancelOrder_notBuyer_reverts() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        vm.prank(attacker);
        vm.expectRevert(OrderRegistry.NotBuyer.selector);
        reg.cancelOrder(id);
        emit log_string("not Buyer");
    }

    function test_markPaid_adminOnlyAndSetsPaid() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        vm.prank(buyer);
        vm.expectRevert(OrderRegistry.NotAuthorized.selector);
        reg.markPaid(id);

        reg.markPaid(id);
        OrderRegistry.Order memory o = reg.getOrder(id);
        emit log_uint(uint256(o.state));
        assertEq(uint256(o.state), uint256(OrderRegistry.OrderState.Paid));
        assertEq(inv.finalizeCalls(), 1);
        emit log_string("state: 0=Created, 1=Cancelled, 2=Paid");
    }

    function test_cancelOrder_afterPaid_reverts_andDoesNotRelease() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        reg.markPaid(id);

        vm.prank(buyer);
        vm.expectRevert(OrderRegistry.InvalidState.selector);
        reg.cancelOrder(id);

        assertEq(inv.releaseCalls(), 0);
        emit log_uint(inv.releaseCalls());
    }

    function test_markPaid_twiceReverts() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        reg.markPaid(id);

        vm.expectRevert(OrderRegistry.InvalidState.selector);
        reg.markPaid(id);
    }

    function test_cancelOrder_twiceReverts() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        vm.prank(buyer);
        reg.cancelOrder(id);

        vm.prank(buyer);
        vm.expectRevert(OrderRegistry.InvalidState.selector);
        reg.cancelOrder(id);
    }

    function test_cancelOrder_releaseReverts_stateRollsBack() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();
        inv.setReleaseRevert(true);
        vm.prank(buyer);
        vm.expectRevert();
        reg.cancelOrder(id);

        OrderRegistry.Order memory o = reg.getOrder(id);
        assertEq(uint256(o.state), uint256(OrderRegistry.OrderState.Created));
    }

    function test_createOrder_reserveReverts_nextIdNotChanged() public {
        uint256 beforeId = reg.nextOrderId();

        inv.setReserveRevert(true);
        vm.prank(buyer);
        vm.expectRevert();

        reg.createOrder(1, 2, WINDOW_NON_VIP);

        assertEq(reg.nextOrderId(), beforeId);
    }

    function test_markPaid_finalizeReverts_stateRollsBack() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        inv.setFinalizeRevert(true);

        vm.expectRevert();
        reg.markPaid(id);

        OrderRegistry.Order memory o = reg.getOrder(id);
        assertEq(uint256(o.state), uint256(OrderRegistry.OrderState.Created));
    }

    function test_createOrder_emits_OrderCreated() public {
        vm.expectEmit(true, true, true, true);
        emit OrderRegistry.OrderCreated(0, buyer, 1, 2);

        vm.prank(buyer);
        reg.createOrder(1, 2, WINDOW_NON_VIP);
    }

    function test_cancelOrder_emits_OrderCancelled() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        vm.expectEmit(true, true, true, true);
        emit OrderRegistry.OrderCancelled(0);

        vm.prank(buyer);
        reg.cancelOrder(id);
    }

    function test_markPaid_emits_OrderPaid() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        vm.expectEmit(true, true, true, true);
        emit OrderRegistry.OrderPaid(0);

        reg.markPaid(id);
    }

    function testFuzz_createOrder_callsReserve(uint256 itemId, uint128 amount) public {
        amount = uint128(bound(uint256(amount), 1, 1000));
        itemId = bound(itemId, 1, 1_000_000);

        uint256 before = inv.reserveCalls();

        vm.prank(buyer);
        reg.createOrder(itemId, amount, WINDOW_NON_VIP);

        assertEq(inv.reserveCalls(), before + 1);
    }

    function testFuzz_cancelOrder_callsRelease(uint256 itemId, uint128 amount) public {
        amount = uint128(bound(uint256(amount), 1, 1000));
        itemId = bound(itemId, 1, 1_000_000);
        vm.prank(buyer);
        uint256 id = reg.createOrder(itemId, amount, WINDOW_NON_VIP);

        vm.warp(block.timestamp + 10);
        uint256 before = inv.releaseCalls();

        vm.prank(buyer);
        reg.cancelOrder(id);

        assertEq(inv.reserveCalls(), before + 1);
    }

    function testFuzz_cancelOrder_notBuyerAlwaysReverts(address _attacker, uint256 itemId, uint128 amount) public {
        attacker = attacker == address(0) ? address(0xBAD) : _attacker;
        vm.assume(attacker != address(0xB0B));
        amount = uint128(bound(uint256(amount), 1, 1000));
        itemId = bound(itemId, 1, 1_000_000);

        vm.prank(address(0xB0B));
        uint256 id = reg.createOrder(itemId, amount, WINDOW_NON_VIP);

        vm.prank(attacker);
        vm.expectRevert(OrderRegistry.NotBuyer.selector);
        reg.cancelOrder(id);
    }

    function testFuzz_cancelWindow_nonVip_timeBoundary(uint256 dt) public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        OrderRegistry.Order memory o = reg.getOrder(id);

        dt = bound(dt, 0, 3600);
        vm.warp(uint256(o.createdAt) + dt);

        vm.prank(buyer);
        if (dt > 30 minutes) {
            vm.expectRevert(OrderRegistry.CancelOrderPassed.selector);
        }
        reg.cancelOrder(id);
    }
    function testFuzz_cancelOrder_vip_timeBoundary(uint256 dt) public {
        vm.prank(buyer);
        uint256 id = _createVip();
        OrderRegistry.Order memory o = reg.getOrder(id);
        dt = bound(dt,0,3600);
        vm.warp(uint256(o.createdAt) + dt);
        vm.prank(buyer);
        if(dt > WINDOW_VIP){
            vm.expectRevert(OrderRegistry.CancelOrderPassed.selector);
        }
        reg.cancelOrder(id);
    }

    function test_markPaid_afterCancel_reverts() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        vm.prank(buyer);
        reg.cancelOrder(id);

        vm.expectRevert(OrderRegistry.InvalidState.selector);
        reg.markPaid(id);
    }

    function test_cancel_afterPaid_reverts() public {
        vm.prank(buyer);
        uint256 id = _createNonVip();

        reg.markPaid(id);

        vm.prank(buyer);
        vm.expectRevert(OrderRegistry.InvalidState.selector);
        reg.cancelOrder(id);
    }

    function test_cancelOrder_nonVip_exactBoundary_passes() public {
        uint256 id = _createNonVip();

        OrderRegistry.Order memory o = reg.getOrder(id);
        vm.warp(o.createdAt + WINDOW_NON_VIP);
        vm.prank(buyer);
        reg.cancelOrder(id);
    }
    function test_cancelOrder_vip_exactBoundary_passes() public {
        uint256 id = _createVip();
        OrderRegistry.Order memory o = reg.getOrder(id);
        vm.warp(o.createdAt+ WINDOW_VIP);
        vm.prank(buyer);
        reg.cancelOrder(id);
    }

    function test_cancelOrder_vip_failsAt11min_nonVipWouldPass() public {
        uint256 id =  _createVip();
        OrderRegistry.Order memory o = reg.getOrder(id);
        vm.warp(o.createdAt + 11 minutes);
        vm.prank(buyer);
        vm.expectRevert(OrderRegistry.CancelOrderPassed.selector);
        reg.cancelOrder(id);

    }


}
