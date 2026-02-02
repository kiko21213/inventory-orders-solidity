// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";

import "../src/Inventory.sol";
import "../src/OrderRegistry.sol";
import "../src/MarketPlace.sol";

contract Marketplace is Test {
    Inventory inv;
    OrderRegistry reg;
    MarketPlace mrkt;

    address admin = address(this);
    address seller = makeAddr("seller");
    address buyer = makeAddr("buyer");

    uint256 listingId;

    event Purchase(uint256 indexed itemId, address indexed who, uint128 amount, uint256 orderId);
    event RefundMoney(address indexed who, uint256 amount);
    event CashbackPaid(address indexed buyer, uint256 amount);
    event PriceUpdated(uint256 indexed itemId, uint256 oldPriceWei, uint256 newPriceWei);

    receive() external payable {}

    function setUp() public {
        inv = new Inventory();
        reg = new OrderRegistry(address(inv));
        mrkt = new MarketPlace(address(inv), address(reg));

        inv.setOperator(address(reg), true);
        inv.setOperator(address(mrkt), true);

        reg.setOperator(address(mrkt));

        mrkt.setSeller(seller, true);

        mrkt.setFees(1000);
        mrkt.setVipFees(500);
        mrkt.setCashback(100);

        vm.deal(buyer, 100 ether);

        vm.prank(seller);
        mrkt.createItem("Apple", 1_000, 1 ether);
        listingId = 1;
    }

    /* ========= helpers ========= */
    function _total(uint256 priceWei, uint128 amount) internal pure returns (uint256) {
        return priceWei * uint256(amount);
    }

    function _fee(uint256 total, uint256 feeBps) internal pure returns (uint256) {
        return total * feeBps / 10_000;
    }

    function _assertAccountingInvariant() internal view {
        (uint256 marketBalance, uint256 totalUsers, uint256 totalPlatform) = mrkt.getAccounting();
        assertEq(marketBalance, totalUsers + totalPlatform, "invariant broken");
    }

    /* ========= tests ========= */

    /* ========= BUY TESTS ========= */
    function test_buyWithmsgValue() public {
        uint128 amount = 2;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);
        uint256 fee = total * mrkt.feesBps() / 10_000;
        uint256 sellerPayout = total - fee;

        vm.prank(buyer);

        vm.expectEmit(true, true, false, true);
        emit Purchase(listingId, buyer, amount, 0);

        uint256 orderId = mrkt.buy{value: total}(listingId, amount);
        assertEq(orderId, 0);

        assertEq(mrkt.userBalances(seller), sellerPayout);

        assertEq(mrkt.totalPlatformBalance(), fee);

        Inventory.Item memory it = inv.getItem(1);
        assertEq(uint256(it.quantity), uint256(1_000 - amount));
        assertEq(uint256(it.reserved), 0);

        (uint256 marketBalance, uint256 totalUsers, uint256 totalPlatform) = mrkt.getAccounting();
        assertEq(marketBalance, totalUsers + totalPlatform);
    }

    function test_buyWithDeposit() public {
        uint128 amount = 3;

        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        vm.prank(buyer);
        mrkt.deposit{value: total}();
        assertEq(mrkt.userBalances(buyer), total);

        vm.prank(buyer);
        uint256 orderId = mrkt.buy(listingId, amount);
        assertEq(orderId, 0);

        assertEq(mrkt.userBalances(buyer), 0);

        uint256 fee = total * mrkt.feesBps() / 10_000;
        uint256 sellerPayout = total - fee;

        assertEq(mrkt.userBalances(seller), sellerPayout);
        assertEq(mrkt.totalPlatformBalance(), fee);

        Inventory.Item memory it = inv.getItem(1);
        assertEq(uint256(it.quantity), uint256(1_000 - amount));
        assertEq(uint256(it.reserved), 0);
        (uint256 marketBalance, uint256 totalUsers, uint256 totalPlatform) = mrkt.getAccounting();
        assertEq(marketBalance, totalUsers + totalPlatform);
    }

    function test_buyWithMixedPayment() public {
        uint128 amount = 4;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        uint256 depositPart = total / 2;
        uint256 msgValuePart = total - depositPart;

        vm.prank(buyer);
        mrkt.deposit{value: depositPart}();
        assertEq(mrkt.userBalances(buyer), depositPart);

        vm.prank(buyer);
        uint256 orderId = mrkt.buy{value: msgValuePart}(listingId, amount);
        assertEq(orderId, 0);

        assertEq(mrkt.userBalances(buyer), 0);
        uint256 fee = total * mrkt.feesBps() / 10_000;
        uint256 sellerPayout = total - fee;
        assertEq(mrkt.userBalances(seller), sellerPayout);
        assertEq(mrkt.totalPlatformBalance(), fee);

        Inventory.Item memory it = inv.getItem(1);
        assertEq(it.quantity, uint256(1_000 - amount));
        assertEq(it.reserved, 0);

        (uint256 marketBalance, uint256 totalUsers, uint256 totalPlatform) = mrkt.getAccounting();
        assertEq(marketBalance, totalUsers + totalPlatform);
    }

    function test_buyVipSellerUseVipFee() public {
        uint128 amount = 2;

        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        mrkt.setVip(seller, true);

        uint256 vipFee = total * mrkt.vipFeesBps() / 10_000;
        uint256 sellerPayout = total - vipFee;

        vm.prank(buyer);
        uint256 orderId = mrkt.buy{value: total}(listingId, amount);
        assertEq(orderId, 0);

        assertEq(mrkt.userBalances(seller), sellerPayout);
        assertEq(mrkt.totalPlatformBalance(), vipFee);

        Inventory.Item memory it = inv.getItem(1);
        assertEq(it.quantity, uint256(1_000 - amount));
        assertEq(it.reserved, 0);

        (uint256 marketBalance, uint256 totalUsers, uint256 totalPlatform) = mrkt.getAccounting();
        assertEq(marketBalance, totalUsers + totalPlatform);
    }

    function test_buyVipBuyerCashback() public {
        uint128 amount = 2;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        mrkt.setVip(buyer, true);

        uint256 fee = total * mrkt.feesBps() / 10_000;
        uint256 cashback = total * mrkt.cashbackBps() / 10_000;
        uint256 sellerPayout = total - fee;
        uint256 platform = fee - cashback;

        vm.prank(buyer);
        vm.expectEmit(true, false, false, true);
        emit CashbackPaid(buyer, cashback);

        uint256 orderId = mrkt.buy{value: total}(listingId, amount);
        assertEq(orderId, 0);
        assertEq(mrkt.userBalances(seller), sellerPayout);
        assertEq(mrkt.userBalances(buyer), cashback);

        assertEq(mrkt.totalPlatformBalance(), platform);
        Inventory.Item memory it = inv.getItem(1);
        assertEq(it.quantity, uint256(1_000 - amount));
        assertEq(it.reserved, 0);

        (uint256 marketBalance, uint256 totalUsers, uint256 totalPlatform) = mrkt.getAccounting();
        assertEq(marketBalance, totalUsers + totalPlatform);
    }

    function test_buyOverPaymentGoesToDeposit() public {
        uint128 amount = 1;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        uint256 change = 0.25 ether;
        uint256 sent = total + change;
        uint256 fee = total * mrkt.feesBps() / 10_000;
        uint256 sellerPayout = total - fee;

        vm.prank(buyer);
        vm.expectEmit(true, false, false, true);
        emit RefundMoney(buyer, change);

        uint256 orderId = mrkt.buy{value: sent}(listingId, amount);
        assertEq(orderId, 0);
        assertEq(mrkt.userBalances(buyer), change);
        assertEq(mrkt.userBalances(seller), sellerPayout);
        assertEq(mrkt.totalPlatformBalance(), fee);

        Inventory.Item memory it = inv.getItem(1);
        assertEq(it.quantity, uint256(1_000 - amount));
        assertEq(it.reserved, 0);

        (uint256 marketBalance, uint256 totalUsers, uint256 totalPlatform) = mrkt.getAccounting();
        assertEq(marketBalance, totalUsers + totalPlatform);
    }

    function test_revertWhenWrongPayment() public {
        uint128 amount = 1;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        vm.prank(buyer);
        vm.expectRevert(MarketPlace.WrongPayment.selector);
        mrkt.buy{value: total - 1}(listingId, amount);
    }

    function test_buyRevertWhenInventoryFrozen() public {
        uint128 amount = 1;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        inv.freeze();

        vm.prank(buyer);
        vm.expectRevert(Inventory.NotActive.selector);
        mrkt.buy{value: total}(listingId, amount);
    }

    function test_buyRevertWhenItemInactive() public {
        uint128 amount = 1;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        vm.prank(seller);
        mrkt.setItemActive(listingId, false);

        vm.prank(buyer);
        vm.expectRevert(MarketPlace.ItemInactive.selector);
        mrkt.buy{value: total}(listingId, amount);
    }

    function test_buyWorksAfterItemReactivated() public {
        uint128 amount = 1;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        vm.startPrank(seller);
        mrkt.setItemActive(listingId, false);
        mrkt.setItemActive(listingId, true);
        vm.stopPrank();

        vm.prank(buyer);
        uint256 orderId = mrkt.buy{value: total}(listingId, amount);
        assertEq(orderId, 0);
    }

    function test_ItemAutoInactive() public {
        vm.prank(seller);
        mrkt.createItem("Orange", 1, 1 ether);
        uint256 soldOutItemId = 2;

        (,,, uint256 priceWei, bool exist, bool isActive,) = mrkt.items(soldOutItemId);
        assertTrue(exist);
        assertTrue(isActive);

        uint128 amount = 1;
        uint256 total = priceWei * uint256(amount);

        vm.prank(buyer);
        mrkt.buy{value: total}(soldOutItemId, amount);
        (,,,,, bool isActiveAfter,) = mrkt.items(soldOutItemId);
        assertFalse(isActiveAfter);

        vm.prank(buyer);
        vm.expectRevert(MarketPlace.ItemInactive.selector);
        mrkt.buy{value: total}(soldOutItemId, amount);
    }

    function test_buyRevertAmountCantBeZero() public {
        vm.prank(buyer);
        vm.expectRevert(MarketPlace.AmountCantBeZero.selector);
        mrkt.buy{value: 0}(listingId, 0);
    }

    function test_buyRevertItemNotFound() public {
        uint256 fakeId = 111;

        vm.prank(buyer);
        vm.expectRevert(MarketPlace.ItemNotFound.selector);
        mrkt.buy{value: 1}(fakeId, 1);
    }

    function test_buyVipCashbackCappedToFee() public {
        mrkt.setFees(50);
        mrkt.setCashback(700);
        mrkt.setVip(buyer, true);

        uint128 amount = 2;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);
        uint256 fee = total * mrkt.feesBps() / 10_000;

        vm.prank(buyer);
        vm.expectEmit(true, false, false, true);
        emit CashbackPaid(buyer, fee);
        mrkt.buy{value: total}(listingId, amount);
        assertEq(mrkt.userBalances(buyer), fee);
        assertEq(mrkt.totalPlatformBalance(), 0);
        _assertAccountingInvariant();
    }

    function test_buyRevertWhenAmountExceedsInventory() public {
        uint128 tooMuchAmount = type(uint128).max;

        vm.prank(buyer);
        vm.expectRevert();
        mrkt.buy{value: 1 ether}(listingId, tooMuchAmount);
    }
    /* ========= WITHDRAW TESTS ========= */

    function test_withdrawForUser() public {
        uint128 amount = 2;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);
        uint256 fee = total * mrkt.feesBps() / 10_000;
        uint256 sellerPayout = total - fee;

        vm.prank(buyer);
        mrkt.buy{value: total}(listingId, amount);
        assertEq(mrkt.userBalances(seller), sellerPayout);

        uint256 sellerEthBefore = seller.balance;

        vm.prank(seller);
        mrkt.withdrawForUser(sellerPayout);
        assertEq(mrkt.userBalances(seller), 0);
        assertEq(seller.balance, sellerEthBefore + sellerPayout);

        (uint256 marketBalance, uint256 totalUsers, uint256 totalPlatform) = mrkt.getAccounting();
        assertEq(marketBalance, totalUsers + totalPlatform);
    }

    function test_withdrawForPlatform() public {
        uint128 amount = 2;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);
        uint256 fee = total * mrkt.feesBps() / 10_000;

        vm.prank(buyer);
        mrkt.buy{value: total}(listingId, amount);
        assertEq(mrkt.totalPlatformBalance(), fee);

        uint256 adminEthBefore = address(this).balance;
        mrkt.withdrawForPlatform(fee);

        assertEq(mrkt.totalPlatformBalance(), 0);
        assertEq(address(this).balance, adminEthBefore + fee);

        (uint256 marketBalance, uint256 totalUsers, uint256 totalPlatform) = mrkt.getAccounting();
        assertEq(marketBalance, totalUsers + totalPlatform);
    }

    function test_withdrawForUser_revertNothingToWithdraw() public {
        vm.prank(seller);
        vm.expectRevert(MarketPlace.NothingToWithdraw.selector);
        mrkt.withdrawForUser(1);
    }

    function test_withdrawForUserRevertAmountCantBeZero() public {
        vm.prank(buyer);
        vm.expectRevert(MarketPlace.AmountCantBeZero.selector);
        mrkt.withdrawForUser(0);
    }

    function test_withdrawForUserREvertMoreThanBalance() public {
        uint128 amount = 2;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        vm.prank(buyer);
        mrkt.buy{value: total}(listingId, amount);

        uint256 sellerBal = mrkt.userBalances(seller);
        assertGt(sellerBal, 0);

        vm.prank(seller);
        vm.expectRevert(MarketPlace.InsufficientBalance.selector);
        mrkt.withdrawForUser(sellerBal + 1);
    }

    function test_withdrawForPlatformRevertAmountCantBeZero() public {
        vm.expectRevert(MarketPlace.AmountCantBeZero.selector);
        mrkt.withdrawForPlatform(0);
    }

    function test_withdrawForPlatformRevertMoreThanBalance() public {
        uint128 amount = 2;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        vm.prank(buyer);
        mrkt.buy{value: total}(listingId, amount);

        uint256 platformBal = mrkt.totalPlatformBalance();
        assertGt(mrkt.totalPlatformBalance(), 0);

        vm.expectRevert(MarketPlace.InsufficientPlatformBalance.selector);
        mrkt.withdrawForPlatform(platformBal + 1);
    }

    function test_withdrawForPlatformOnlyAdmin() public {
        uint128 amount = 2;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        vm.prank(buyer);
        mrkt.buy{value: total}(listingId, amount);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(MarketPlace.NotAnAdmin.selector);
        mrkt.withdrawForPlatform(1);
    }

    function test_setItemPrice_UpdatePriceAndAffectsBuyTotal() public {
        uint128 amount = 2;
        (,,, uint256 oldPrice, bool exist, bool isActive,) = mrkt.items(listingId);
        assertTrue(exist);
        assertTrue(isActive);

        uint256 newPriceWei = oldPrice * 2;

        vm.prank(seller);
        vm.expectEmit(true, false, false, true);
        emit PriceUpdated(listingId, oldPrice, newPriceWei);
        mrkt.setItemPrice(listingId, newPriceWei);

        (,,, uint256 updatePrice,,,) = mrkt.items(listingId);
        assertEq(updatePrice, newPriceWei);

        uint256 total = newPriceWei * uint256(amount);

        vm.prank(buyer);
        mrkt.buy{value: total}(listingId, amount);

        uint256 fee = total * mrkt.feesBps() / 10_000;
        uint256 sellerPayout = total - fee;
        assertEq(mrkt.userBalances(seller), sellerPayout);
        assertEq(mrkt.totalPlatformBalance(), fee);
    }

    function test_setItemPrice_revertOnlyAdminOrSeller() public {
        address attacker = makeAddr("attaker");

        vm.prank(attacker);
        vm.expectRevert();
        mrkt.setItemPrice(listingId, 5 ether);
    }

    function test_buyRevertSelfPurchase() public {
        uint128 amount = 1;
        (,,, uint256 priceWei, bool exist,,) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);
        vm.deal(seller, total);

        vm.prank(seller);
        vm.expectRevert(MarketPlace.SelfPurchase.selector);
        mrkt.buy{value: total}(listingId, amount);
    }
}
