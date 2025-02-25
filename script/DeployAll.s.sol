// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";

// Mocks
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockConditionalTokens} from "../test/mocks/MockConditionalTokens.sol";

// Main contracts
import {CTFExchange} from "../src/CTFExchange.sol";
import {MarketCreator} from "../src/MarketCreator.sol";
import {OracleResolver} from "../src/OracleResolver.sol";

contract DeployAll is Script {
    function run() external {
        vm.startBroadcast();

        // 1) Deploy mock USDC
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        console.log("Mock USDC deployed at:", address(usdc));

        // 2) Deploy mock ConditionalTokens
        MockConditionalTokens ctf = new MockConditionalTokens();
        console.log("MockConditionalTokens deployed at:", address(ctf));

        // 3) Deploy CTFExchange
        // Suppose you have environment variables for proxyFactory & safeFactory
        address proxyFactory = vm.envAddress("PROXY_FACTORY");
        address safeFactory = vm.envAddress("SAFE_FACTORY");
        CTFExchange exchange = new CTFExchange(address(usdc), address(ctf), proxyFactory, safeFactory);
        console.log("CTFExchange deployed at:", address(exchange));

        // 4) Deploy MarketCreator
        MarketCreator marketCreator = new MarketCreator(address(ctf), address(exchange), address(usdc));
        console.log("MarketCreator deployed at:", address(marketCreator));

        // 5) Deploy OracleResolver
        OracleResolver resolver = new OracleResolver(address(ctf));
        console.log("OracleResolver deployed at:", address(resolver));

        vm.stopBroadcast();
    }
}
