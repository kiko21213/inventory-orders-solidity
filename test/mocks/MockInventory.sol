// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IInventoryReg} from "../../src/OrderRegistry.sol";

contract MockInventory is IInventoryReg {
    uint256 public reserveCalls;
    uint256 public finalizeCalls;
    uint256 public releaseCalls;
    bool public releaseShouldRevert;
    bool public reserveShouldRevert;
    bool public finalizeShouldRevert;

    function reserveQuantity(uint256, uint128) external override {
        if (reserveShouldRevert) revert();
        reserveCalls++;
    }

    function setReserveRevert(bool s) external {
        reserveShouldRevert = s;
    }

    function releaseReservation(uint256, uint128) external override {
        if (releaseShouldRevert) revert();
        releaseCalls++;
    }

    function setReleaseRevert(bool s) external {
        releaseShouldRevert = s;
    }

    function finalizeReservation(uint256, uint128) external override {
        if (finalizeShouldRevert) revert();
        finalizeCalls++;
    }

    function setFinalizeRevert(bool s) external {
        finalizeShouldRevert = s;
    }
}
