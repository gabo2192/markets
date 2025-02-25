// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

abstract contract BaseExchange is ERC1155Holder, ReentrancyGuard {}
