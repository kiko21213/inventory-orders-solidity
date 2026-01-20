// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

contract Inventory {
    struct Item {
        string name;
        uint128 quantity; // total
        uint128 reserved; // locked
        uint64 createdAt;
        bool exists;
    }

    enum State {
        Active,
        Frozen,
        Closed
    }
    State public state;

    mapping(uint256 => Item) private items;

    uint256 public totalItems;
    uint256 public nextItemId = 1;
    uint256 public constant MAX_ITEMS = 10000;

    address public operator;
    address public immutable admin;

    /* ========== ERRORS ========== */
    error NotAdmin();
    error NotActive();
    error NotFrozen();
    error ClosedForever();

    // error ItemAlreadyExist();
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
    error QuantityBelowReserved();

    /* ========== EVENTS ========== */
    event ItemAdded(uint256 indexed itemId, uint256 quantity);
    event Reserved(uint256 indexed itemId, uint256 amount);
    event ReservationReleased(uint256 indexed itemId, uint256 amount);
    event ReservationFinalized(uint256 indexed itemId, uint256 amount);
    event ItemRemoved(uint256 indexed itemId);
    event StateChanged(State oldState, State newState);
    event OperatorChanged(address indexed oldOperator, address indexed newOperator);
    event QuantityChanged(uint256 indexed itemId, uint128 oldQuantity, uint256 newQuantity);

    /* ========== MODIFIERS ========== */
    modifier onlyAdminOrOperator() {
        if (msg.sender != operator && msg.sender != admin) revert NotAuthorized();
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
    function setOperator(address _newOperator) external onlyAdmin onlyActive {
        if (_newOperator == address(0)) revert ZeroAddressOperator();
        if (_newOperator == admin) revert AdminCantBeOperator();
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
    function addItem(string memory name, uint128 quantity)
        external
        onlyAdminOrOperator
        onlyActive
        returns (uint256 itemId)
    {
        if (totalItems >= MAX_ITEMS) revert MaxItemsReached();
        if (quantity == 0) revert QuantityCantBeZero();
        itemId = nextItemId++;

        items[itemId] =
            Item({name: name, quantity: quantity, reserved: 0, createdAt: uint64(block.timestamp), exists: true});

        totalItems++;
        emit ItemAdded(itemId, quantity);
    }

    function reserveQuantity(uint256 itemId, uint128 amount) external onlyAdminOrOperator onlyActive {
        Item storage it = items[itemId];
        if (!it.exists) revert ItemDoesNotExist();
        if (amount == 0) revert AmountCantBeZero();
        uint128 available = it.quantity - it.reserved;
        if (amount > available) revert NotEnoughAvailable();

        it.reserved += amount;
        emit Reserved(itemId, amount);
    }

    function releaseReservation(uint256 itemId, uint128 amount) external onlyAdminOrOperator onlyActiveOrFrozen {
        Item storage it = items[itemId];
        if (!it.exists) revert ItemDoesNotExist();
        if (amount == 0) revert AmountCantBeZero();
        if (amount > it.reserved) revert NotEnoughReserved();

        it.reserved -= amount;
        emit ReservationReleased(itemId, amount);
    }

    function finalizeReservation(uint256 itemId, uint128 amount) external onlyAdminOrOperator onlyActiveOrFrozen {
        Item storage it = items[itemId];
        if (!it.exists) revert ItemDoesNotExist();
        if (amount == 0) revert AmountCantBeZero();
        if (amount > it.reserved) revert NotEnoughReserved();

        it.reserved -= amount;
        it.quantity -= amount;
        emit ReservationFinalized(itemId, amount);
    }

    function removeItem(uint256 itemId) external onlyAdmin onlyActive {
        Item storage it = items[itemId];
        if (!it.exists) revert ItemDoesNotExist();
        if (it.reserved > 0) revert ExistReservedItem();

        delete items[itemId];
        totalItems--;

        emit ItemRemoved(itemId);
    }

    function setQuantityItem(uint256 listingItemId, uint128 newQuantity)
        external
        onlyAdminOrOperator
        onlyActiveOrFrozen
    {
        Item storage it = items[listingItemId];
        if (!it.exists) revert ItemDoesNotExist();
        if (newQuantity == 0) revert QuantityCantBeZero();
        if (it.reserved > newQuantity) revert QuantityBelowReserved();
        uint128 oldQuantity = it.quantity;
        it.quantity = newQuantity;

        emit QuantityChanged(listingItemId, oldQuantity, newQuantity);
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
