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
}
