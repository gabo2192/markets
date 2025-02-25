// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {OracleResolver} from "../src/OracleResolver.sol";

contract DeployOracleResolver is Script {
    function run() external {
        address ctf = vm.envAddress("CTF");

        vm.startBroadcast();
        OracleResolver resolver = new OracleResolver(ctf);
        vm.stopBroadcast();

        console.log("OracleResolver deployed at:", address(resolver));
    }
}
