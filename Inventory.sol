// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

contract Inventory {
    struct Item {
        uint128 quantity;   // total
        uint128 reserved;   // locked
        bool exists;
    }

    enum State { Active, Frozen, Closed }
    State public state;

    mapping(uint256 => Item) private items;

    uint256 public totalItems;
    uint256 public constant MAX_ITEMS = 10000;

    address public operator;
    address public immutable admin;

    /* ========== ERRORS ========== */
    error NotAdmin();
    error NotActive();
    error NotFrozen();
    error ClosedForever();

    error ItemAlreadyExist();
    error ItemDoesNotExist();
    error QuantityCantBeZero();
    error AmountCantBeZero();
    error NotEnoughAvailable();
    error NotEnoughReserved();
    error ExistReservedItem();
    error MaxItemsReached();
    error AlreadyClosed();
    error NotAuthorized();
    error ZeroAddressOperator();
    error AdminCantBeOperator();

    /* ========== EVENTS ========== */
    event ItemAdded(uint256 indexed itemId, uint256 quantity);
    event Reserved(uint256 indexed itemId, uint256 amount);
    event ReservationReleased(uint256 indexed itemId, uint256 amount);
    event ReservationFinalized(uint256 indexed itemId, uint256 amount);
    event ItemRemoved(uint256 indexed itemId);
    event StateChanged(State oldState, State newState);
    event OperatorChanged(address indexed oldOperator, address indexed newOperator);

    /* ========== MODIFIERS ========== */
    modifier onlyAdminOrOperator() {
        if(msg.sender != operator && msg.sender != admin) revert NotAuthorized();
        _;
    }
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyActive() {
        if (state != State.Active) revert NotActive();
        _;
    }

    modifier onlyFrozen() {
        if (state != State.Frozen) revert NotFrozen();
        _;
    }

    modifier onlyActiveOrFrozen() {
        if (state == State.Closed) revert ClosedForever();
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    constructor() {
        admin = msg.sender;
        state = State.Active;
    }
    /* ========== OPERATOR LOGIC ========== */
    function setOperator(address _newOperator) external onlyAdmin onlyActive{
        if(_newOperator == address(0)) revert ZeroAddressOperator();
        if(_newOperator == admin) revert AdminCantBeOperator();
        address old = operator;
        operator = _newOperator;

        emit OperatorChanged(old, _newOperator);
    }
    /* ========== STATE CONTROL ========== */
    function freeze() external onlyAdmin onlyActive {
        State old = state;
        state = State.Frozen;
        emit StateChanged(old, state);
    }

    function unfreeze() external onlyAdmin onlyFrozen {
        State old = state;
        state = State.Active;
        emit StateChanged(old, state);
    }

    function close() external onlyAdmin {
        if (state == State.Closed) revert AlreadyClosed();
        State old = state;
        state = State.Closed;
        emit StateChanged(old, state);
    }

    /* ========== INVENTORY LOGIC ========== */
    function addItem(uint256 itemId, uint128 quantity)
        external
        onlyAdmin
        onlyActive
    {
        if (totalItems >= MAX_ITEMS) revert MaxItemsReached();
        if (items[itemId].exists) revert ItemAlreadyExist();
        if (quantity == 0) revert QuantityCantBeZero();

        items[itemId] = Item({
            quantity: quantity,
            reserved: 0,
            exists: true
        });

        totalItems++;
        emit ItemAdded(itemId, quantity);
    }

    function reserveQuantity(uint256 itemId, uint128 amount)
        external
        onlyAdminOrOperator
        onlyActive
    {
        Item storage it = items[itemId];
        if (!it.exists) revert ItemDoesNotExist();
        if (amount == 0) revert AmountCantBeZero();
        uint128 available = it.quantity - it.reserved;
        if (amount > available) revert NotEnoughAvailable();

        it.reserved += amount;
        emit Reserved(itemId, amount);
    }

    function releaseReservation(uint256 itemId, uint128 amount)
        external
        onlyAdminOrOperator
        onlyActiveOrFrozen
    {
        Item storage it = items[itemId];
        if (!it.exists) revert ItemDoesNotExist();
        if (amount == 0) revert AmountCantBeZero();
        if (amount > it.reserved) revert NotEnoughReserved();

        it.reserved -= amount;
        emit ReservationReleased(itemId, amount);
    }

    function finalizeReservation(uint256 itemId, uint128 amount)
        external
        onlyAdminOrOperator
        onlyActiveOrFrozen
    {
        Item storage it = items[itemId];
        if (!it.exists) revert ItemDoesNotExist();
        if (amount == 0) revert AmountCantBeZero();
        if (amount > it.reserved) revert NotEnoughReserved();

        it.reserved -= amount;
        it.quantity -= amount;
        emit ReservationFinalized(itemId, amount);
    }

    function removeItem(uint256 itemId)
        external
        onlyAdmin
        onlyActive
    {
        Item storage it = items[itemId];
        if (!it.exists) revert ItemDoesNotExist();
        if (it.reserved > 0) revert ExistReservedItem();

        it.quantity = 0;
        it.reserved = 0;
        it.exists = false;
        totalItems--;

        emit ItemRemoved(itemId);
    }

    /* ========== GETTERS ========== */
    function getItem(uint256 itemId) external view returns (Item memory) {
        return items[itemId];
    }

    function getAvailableQuantity(uint256 itemId) external view returns (uint128) {
        Item memory it = items[itemId];
        if (!it.exists) revert ItemDoesNotExist();
        return it.quantity - it.reserved;
    }
}


