// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

interface IInventory {
    function reserveQuantity(uint256 itemId, uint256 amount) external;
    function releaseReservation(uint256 itemId, uint256 amount) external;
    function finalizeReservation(uint256 itemId, uint256 amount) external;
}

contract OrderRegistry {
    enum OrderState { Created, Cancelled, Paid, Shipped }

    struct Order {
        address buyer;
        uint256 itemId;
        uint256 amount;
        uint64 createdAt;
        bool exists;
        OrderState state;
    }

    address public immutable admin;
    IInventory public inventory;

    uint256 public nextOrderId;
    uint256 public constant CANCEL_ORDER = 30 minutes;
    mapping(uint256 => Order) private orders;

    /* ========== ERRORS ========== */
    error NotAdmin();
    error AmountZero();
    error OrderDoesNotExist();
    error NotBuyer();
    error InvalidState();
    error NotContract();
    error CancelOrderPassed();

    /* ========== EVENTS ========== */
    event OrderCreated(
        uint256 indexed orderId,
        address indexed buyer,
        uint256 indexed itemId,
        uint256 amount
    );
    event OrderCancelled(uint256 indexed orderId);
    event OrderPaid(uint256 indexed orderId);
    event OrderShipped(uint256 indexed orderId);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor(address inventoryAddress) {
        if(inventoryAddress.code.length == 0) revert NotContract();
        admin = msg.sender;
        inventory = IInventory(inventoryAddress);
    }

    /* ========== ORDER LOGIC ========== */
    function createOrder(uint256 itemId, uint256 amount)
        external
        returns (uint256 orderId)
    {
        if (amount == 0) revert AmountZero();

        // reserve FIRST
        inventory.reserveQuantity(itemId, amount);

        orderId = nextOrderId++;
        orders[orderId] = Order({
            buyer: msg.sender,
            itemId: itemId,
            amount: amount,
            createdAt : uint64(block.timestamp),
            exists: true,
            state: OrderState.Created
        });

        emit OrderCreated(orderId, msg.sender, itemId, amount);
    }

    function cancelOrder(uint256 orderId) external {
        Order storage o = orders[orderId];
        if (!o.exists) revert OrderDoesNotExist();
        if(block.timestamp > o.createdAt + CANCEL_ORDER) revert CancelOrderPassed();
        if (o.buyer != msg.sender) revert NotBuyer();
        if (o.state != OrderState.Created) revert InvalidState();

        o.state = OrderState.Cancelled;
        inventory.releaseReservation(o.itemId, o.amount);

        emit OrderCancelled(orderId);
    }

    function markPaid(uint256 orderId) external onlyAdmin {
        Order storage o = orders[orderId];
        if (!o.exists) revert OrderDoesNotExist();
        if (o.state != OrderState.Created) revert InvalidState();

        o.state = OrderState.Paid;
        inventory.finalizeReservation(o.itemId, o.amount);

        emit OrderPaid(orderId);
    }

    function markShipped(uint256 orderId) external onlyAdmin {
        Order storage o = orders[orderId];
        if (!o.exists) revert OrderDoesNotExist();
        if (o.state != OrderState.Paid) revert InvalidState();

        o.state = OrderState.Shipped;
        emit OrderShipped(orderId);
    }

    /* ========== GETTERS ========== */
    function getOrder(uint256 orderId) external view returns (Order memory) {
        Order memory o = orders[orderId];
        if (!o.exists) revert OrderDoesNotExist();
        return o;
    }
}


