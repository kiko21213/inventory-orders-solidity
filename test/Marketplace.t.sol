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
    function test_buyWithmsgValue() public {
        uint128 amount = 2;
        (,,, uint256 priceWei, bool exist) = mrkt.items(listingId);
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

        (,,, uint256 priceWei, bool exist) = mrkt.items(listingId);
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
        (,,, uint256 priceWei, bool exist) = mrkt.items(listingId);
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

        (,,, uint256 priceWei, bool exist) = mrkt.items(listingId);
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
        (,,, uint256 priceWei, bool exist) = mrkt.items(listingId);
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
        (,,, uint256 priceWei, bool exist) = mrkt.items(listingId);
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
        (,,, uint256 priceWei, bool exist) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        vm.prank(buyer);
        vm.expectRevert(MarketPlace.WrongPayment.selector);
        mrkt.buy{value: total - 1}(listingId, amount);
    }

    function test_withdrawForUser() public {
        uint128 amount = 2;
        (,,, uint256 priceWei, bool exist) = mrkt.items(listingId);
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
        (,,, uint256 priceWei, bool exist) = mrkt.items(listingId);
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

    function test_buyRevertWhenInventoryFrozen() public {
        uint128 amount = 1;
        (,,, uint256 priceWei, bool exist) = mrkt.items(listingId);
        assertTrue(exist);

        uint256 total = priceWei * uint256(amount);

        inv.freeze();

        vm.prank(buyer);
        vm.expectRevert();
        mrkt.buy{value: total}(listingId, amount);
    }
}
