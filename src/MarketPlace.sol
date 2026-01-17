// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
interface IOrderRegistry{
    function createOrder(uint256 itemId, uint128 amount) external returns(uint256 orderId);
}
contract MarketPlace{

/* ========== STORAGE ========== */
address public admin;
IOrderRegistry public orderRegistry;
/* ========== IVENTS ========== */
event Withdraw(address indexed who, uint256 amount); 
/* ========== MODIFIERS ========== */
modifier onlyAdmin() {
    if(msg.sender != admin) revert NotAnAdmin();
    _;
}
/* ========== ERRORS ========== */
error ZeroAddress();
error notAContract(address adr);
error NotAnAdmin();
/* ========== CONSTRUCTOR ========== */
constructor(address orderRegistryAddress) {
    if(orderRegistryAddress == address(0)) revert ZeroAddress();
    if(orderRegistryAddress.code.length == 0) revert notAContract(orderRegistryAddress);
    admin = msg.sender;
    orderRegistry = IOrderRegistry(orderRegistryAddress);
}
/* ========== USER ACTION ========== */
function buy(uint256 itemId, uint128 amount) external returns(uint256 orderId){

}






}