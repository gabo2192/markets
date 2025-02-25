// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {MarketCreator} from "../src/MarketCreator.sol";

contract DeployMarketCreator is Script {
    function run() external {
        address ctf = vm.envAddress("CTF");
        address exchange = vm.envAddress("EXCHANGE");
        address collateral = vm.envAddress("COLLATERAL");

        vm.startBroadcast();
        MarketCreator marketCreator = new MarketCreator(ctf, exchange, collateral);
        vm.stopBroadcast();

        console.log("MarketCreator deployed at:", address(marketCreator));
    }
}
