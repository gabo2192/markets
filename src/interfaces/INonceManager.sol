// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

abstract contract INonceManager {
    function incrementNonce() external virtual;

    function isValidNonce(address user, uint256 userNonce) public view virtual returns (bool);
}
