// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CTFExchange} from "../src/CTFExchange.sol";
import {MarketCreator} from "../src/MarketCreator.sol";
import {OracleResolver} from "../src/OracleResolver.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";

contract DeployProduction is Script {
    // Configure these addresses for your target network
    address usdc = vm.envAddress("USDC_ADDRESS");
    address operatorAddress = vm.envAddress("OPERATOR_ADDRESS");

    function run() external {
        vm.startBroadcast();

        // 1) Deploy ConditionalTokens framework
        ConditionalTokens ctf = new ConditionalTokens();
        console.log("ConditionalTokens deployed at:", address(ctf));

        // 2) Deploy CTFExchange with actual USDC
        CTFExchange exchange = new CTFExchange(usdc, address(ctf));
        console.log("CTFExchange deployed at:", address(exchange));

        // 3) Setup secure permissions
        // The msg.sender (your account) is already set as admin in the CTFExchange constructor
        console.log("Default admin (deployer):", msg.sender);

        // Add operator role
        exchange.addOperator(operatorAddress);
        console.log("Added operator:", operatorAddress);

        // 4) Deploy MarketCreator
        MarketCreator marketCreator = new MarketCreator(address(ctf), address(exchange), usdc);
        console.log("MarketCreator deployed at:", address(marketCreator));

        // MarketCreator NEEDS admin privileges on Exchange to register tokens
        // This is because registerToken() is called from MarketCreator.createMarket()
        exchange.addAdmin(address(marketCreator));
        console.log("Added MarketCreator as admin on Exchange");

        // 5) Deploy OracleResolver and keep deployer as owner
        OracleResolver resolver = new OracleResolver(address(ctf));
        console.log("OracleResolver deployed at:", address(resolver));
        // Ownership remains with deployer (msg.sender)

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
    }
}
