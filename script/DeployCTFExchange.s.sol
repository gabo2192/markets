// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {CTFExchange} from "../src/CTFExchange.sol";

contract DeployCTFExchange is Script {
    function run() external {
        address collateral = vm.envAddress("COLLATERAL");
        address ctf = vm.envAddress("CTF");
        address proxyFactory = vm.envAddress("PROXY_FACTORY");
        address safeFactory = vm.envAddress("SAFE_FACTORY");

        vm.startBroadcast();

        // Deploy the contract
        CTFExchange exchange = new CTFExchange(collateral, ctf, proxyFactory, safeFactory);
        console.log("CTFExchange deployed at:", address(exchange));

        vm.stopBroadcast();
    }
}
