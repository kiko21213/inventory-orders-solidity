// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IInventory {
    function addItem(string memory name, uint128 quantity) external returns (uint256 itemId);
    function reserveQuantity(uint256 itemId, uint128 amount) external;
    function releaseReservation(uint256 itemId, uint128 amount) external;
    function finalizeReservation(uint256 itemId, uint128 amount) external;
}

interface IOrderRegistry {
    function createOrder(uint256 itemId, uint128 amount) external returns (uint256 orderId);
}

contract MarketPlace {
    /* ========== STORAGE ========== */

    struct ListingItem {
        string displayName;
        uint256 inventoryItemId;
        address seller;
        uint256 priceWei;
        bool exist;
    }
    address public admin;
    IOrderRegistry public orderRegistry;
    IInventory public inventory;
    mapping(uint256 => ListingItem) public items;
    mapping(address => bool) isVip;
    mapping(address => bool) isSeller;
    uint256 nextItemListingId = 1;
    /* ========== EVENTS ========== */
    event Withdraw(address indexed who, uint256 amount);
    event CreateListingItem(uint256 indexed itemId, address indexed who, uint128 quantity, uint256 price);
    event PriceUpdated(uint256 indexed itemId, uint256 oldPrice, uint256 newPrice);
    event QuantityUpdated(uint256 indexed itemId, uint256 oldQty, uint256 newQty);
    event VipSet(address indexed vip, bool isVip);
    event SellerSet(address indexed seller, bool isSeller);
    event Purchase(uint256 indexed itemId, address indexed who, uint128 amount, uint256 orderId);
    /* ========== MODIFIERS ========== */
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAnAdmin();
        _;
    }
    modifier OnlyAdminOrSeller(uint256 listingId) {
        if (items[listingId].seller == address(0)) revert ItemNotFound();
        if (msg.sender != items[listingId].seller && msg.sender != admin) revert NotSeller();
        _;
    }
    /* ========== ERRORS ========== */
    error ZeroAddress();
    error notAContract(address adr);
    error NotAnAdmin();
    error ItemNotFound();
    error AmountCantBeZero();
    error PriceCantBeZero();
    error QuantityCantBeZero();
    error NotSeller();
    error SellerNotApproved();
    error InsufficientQuantity();

    /* ========== CONSTRUCTOR ========== */
    constructor(address inventoryAddress, address orderRegistryAddress) {
        if (inventoryAddress == address(0)) revert ZeroAddress();
        if (inventoryAddress.code.length == 0) revert notAContract(inventoryAddress);

        if (orderRegistryAddress == address(0)) revert ZeroAddress();
        if (orderRegistryAddress.code.length == 0) revert notAContract(orderRegistryAddress);

        admin = msg.sender;
        inventory = IInventory(inventoryAddress);
        orderRegistry = IOrderRegistry(orderRegistryAddress);
    }

    /* ========== ADMIN ACTION ========== */
    function setVip(address buyerVip, bool status) external onlyAdmin {
        if (buyerVip == address(0)) revert ZeroAddress();
        isVip[buyerVip] = status;

        emit VipSet(buyerVip, status);
    }

    function setSeller(address seller, bool status) external onlyAdmin {
        if (seller == address(0)) revert ZeroAddress();
        isSeller[seller] = status;

        emit SellerSet(seller, status);
    }

    /* ========== SELLER ACTION ========== */
    function createItem(string memory _name, uint128 _quantity, uint256 _price) public {
        if (!isSeller[msg.sender]) revert SellerNotApproved();
        if (_price == 0) revert PriceCantBeZero();
        if (_quantity == 0) revert QuantityCantBeZero();

        uint256 inventoryId = inventory.addItem(_name, _quantity);
        uint256 listingId = nextItemListingId++;

        items[listingId] = ListingItem({
            displayName: _name, inventoryItemId: inventoryId, seller: msg.sender, priceWei: _price, exist: true
        });

        emit CreateListingItem(listingId, msg.sender, _quantity, _price);
    }

    function setItemPrice(uint256 _itemId, uint256 _newPrice) external OnlyAdminOrSeller(_itemId) {
        ListingItem storage it = items[_itemId];
        if (_newPrice == 0) revert PriceCantBeZero();
        uint256 oldPrice = it.priceWei;
        it.priceWei = _newPrice;

        emit PriceUpdated(_itemId, oldPrice, _newPrice);
    }

    // function setQuantity(uint256 _itemId, uint128 _newQuantity) external OnlyAdminOrSeller(_itemId) {
    //     ListingItem storage it = items[_itemId];
    //     if (_newQuantity == 0) revert QuantityCantBeZero();
    //     uint256 oldQuantity = it.quantity;
    //     it.quantity = _newQuantity;

    //     emit QuantityUpdated(_itemId, oldQuantity, _newQuantity);
    // }
    /* ========== USER ACTION ========== */
    // function buy(uint256 _itemId, uint128 _amount) external returns (uint256 orderId) {
    //     ListingItem memory it = items[_itemId];
    //     if(it.seller == address(0)) revert ItemNotFound();
    //     if(_amount == 0) revert AmountCantBeZero();
    //     if(_amount > it.quantity) revert InsufficientQuantity();

    //     emit Purchase(_itemId, msg.sender, _amount, orderId);

    // }
}
