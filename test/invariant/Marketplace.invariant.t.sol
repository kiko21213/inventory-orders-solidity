// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../../src/Inventory.sol";
import "../../src/OrderRegistry.sol";
import "../../src/MarketPlace.sol";

contract MarketPlaceHandler is Test {
    MarketPlace public mrkt;
    Inventory public inv;

    address public seller = makeAddr("seller");
    address public buyer = makeAddr("buyer");
    address public admin;

    uint256 public listingId;

    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;

    constructor(MarketPlace _mrkt, Inventory _inv) {
        mrkt = _mrkt;
        inv = _inv;
        admin = address(this);

        vm.deal(buyer, 1000 ether);
        vm.deal(seller, 100 ether);

        vm.prank(seller);
        mrkt.createItem("Apple", 10_000, 1 ether);
        listingId = 1;
    }

    function buy(uint128 amount) external {
        amount = uint128(bound(uint256(amount), 1, 10));
        (,,, uint256 priceWei, bool exist, bool isActive, bool isDelisting) = mrkt.items(listingId);
        if (!exist || !isActive || isDelisting) return;

        uint256 total = priceWei * uint256(amount);
        if (buyer.balance < total) return;

        vm.prank(buyer);
        try mrkt.buy{value: total}(listingId, amount, "") {} catch {}
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, 1, 10 ether);
        if (buyer.balance < amount) return;

        vm.prank(buyer);
        try mrkt.deposit{value: amount}() {
            ghost_totalDeposited += amount;
        } catch {}
    }

    function withdrawUser(uint256 amount) external {
        uint256 bal = mrkt.userBalances(buyer);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);

        vm.prank(buyer);
        try mrkt.withdrawForUser(amount) {
            ghost_totalWithdrawn += amount;
        } catch {}
    }

    function withdrawPlatform(uint256 amount) external {
        uint256 bal = mrkt.totalPlatformBalance();
        if (bal == 0) return;
        amount = bound(amount, 1, bal);

        try mrkt.withdrawForPlatform(amount) {} catch {}
    }

    function setItemActive(bool active) external {
        try mrkt.setItemActive(listingId, active) {} catch {}
    }
}

contract MarketPlaceInvariantTest is Test {
    Inventory inv;
    OrderRegistry reg;
    MarketPlace mrkt;
    MarketPlaceHandler handler;

    address seller = makeAddr("seller");

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

        handler = new MarketPlaceHandler(mrkt, inv);
        targetContract(address(handler));
    }

    function invariant_accountingBalanceAlwaysHolds() public view {
        (uint256 market, uint256 users, uint256 platform) = mrkt.getAccounting();
        assertEq(market, users + platform, "INVARIANT BROKEN: balance != totalUserBalances + totalPlatformBalance");
    }

    function invariant_platformBalanceNeverNegative() public view {
        (,, uint256 platform) = mrkt.getAccounting();
        assertGe(platform, 0, "INVARIANT BROKEN: platform balance negative");
    }

    function invariant_userBalancesNeverExceedContractBalance() public view {
        (uint256 market, uint256 users,) = mrkt.getAccounting();
        assertLe(users, market, "INVARIANT BROKEN: totalUserBalances > contract balance");
    }
}

