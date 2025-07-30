// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {BaseExchangeTest} from "./BaseExchangeTest.sol";
import {CTFExchange} from "../src/CTFExchange.sol";
import {MarketCreator} from "../src/MarketCreator.sol";
import {OracleResolver} from "../src/OracleResolver.sol";
import {USDC} from "./mocks/USDC.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";

contract AdminPermissionsTest is Test {
    USDC public usdc;
    ConditionalTokens public ctf;
    CTFExchange public exchange;
    MarketCreator public marketCreator;
    OracleResolver public resolver;

    // Test accounts
    address public deployer = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    address public operator = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
    address public randomUser = address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC);

    event NewAdmin(address indexed newAdminAddress, address indexed admin);
    event TokenRegistered(uint256 indexed token0, uint256 indexed token1, bytes32 indexed conditionId);

    function setUp() public {
        // Label accounts for better trace output
        vm.label(deployer, "deployer");
        vm.label(operator, "operator");
        vm.label(randomUser, "randomUser");

        // Setup initial state
        vm.startPrank(deployer);

        // Deploy contracts
        usdc = new USDC();
        ctf = new ConditionalTokens();
        exchange = new CTFExchange(address(usdc), address(ctf));

        // Add operator role
        exchange.addOperator(operator);

        // Deploy MarketCreator
        marketCreator = new MarketCreator(address(ctf), address(exchange), address(usdc));

        // IMPORTANT: Explicitly add MarketCreator as admin
        exchange.addAdmin(address(marketCreator));

        // Deploy OracleResolver
        resolver = new OracleResolver(address(ctf));

        vm.stopPrank();
    }

    function testDeployerIsAdmin() public {
        // Check that deployer is admin
        bool isAdmin = exchange.isAdmin(deployer);
        assertTrue(isAdmin, "Deployer should be an admin");
    }

    function testMarketCreatorIsAdmin() public {
        // Check that MarketCreator contract is admin
        bool isAdmin = exchange.isAdmin(address(marketCreator));
        assertTrue(isAdmin, "MarketCreator should be an admin");
    }

    function testOperatorIsNotAdmin() public {
        // Verify operator is not an admin
        bool isAdmin = exchange.isAdmin(operator);
        assertFalse(isAdmin, "Operator should not be an admin");

        // But is an operator
        bool isOperator = exchange.isOperator(operator);
        assertTrue(isOperator, "Operator should have operator role");
    }

    function testRandomUserHasNoRoles() public {
        // Random user has no roles
        bool isAdmin = exchange.isAdmin(randomUser);
        bool isOperator = exchange.isOperator(randomUser);

        assertFalse(isAdmin, "Random user should not be an admin");
        assertFalse(isOperator, "Random user should not be an operator");
    }

    function testDeployerCanAddAdmin() public {
        // Deployer can add a new admin
        vm.startPrank(deployer);

        vm.expectEmit(true, true, true, false);
        emit NewAdmin(randomUser, deployer);

        exchange.addAdmin(randomUser);
        vm.stopPrank();

        bool isAdmin = exchange.isAdmin(randomUser);
        assertTrue(isAdmin, "Deployer should be able to add new admin");
    }

    function testMarketCreatorCanRegisterTokens() public {
        vm.startPrank(deployer);

        // Create some dummy values for token registration
        uint256 token0 = 123;
        uint256 token1 = 456;
        bytes32 conditionId = keccak256("test-condition");

        // Execute through MarketCreator contract
        vm.mockCall(
            address(marketCreator),
            abi.encodeWithSelector(MarketCreator.createMarket.selector),
            abi.encode(conditionId, token0, token1)
        );

        // Test direct registration first
        vm.expectEmit(true, true, true, false);
        emit TokenRegistered(token0, token1, conditionId);

        vm.stopPrank();

        // Now create a test to simulate MarketCreator's token registration
        // This test sets up a scenario as if MarketCreator called registerToken
        vm.startPrank(address(marketCreator));

        // Expect no revert since MarketCreator is admin
        exchange.registerToken(token0, token1, conditionId);

        vm.stopPrank();

        // Verify token was registered (check would be implementation specific)
        // Just assert that no revert happened, which confirms MarketCreator had admin rights
    }

    function testNonAdminCannotRegisterTokens() public {
        // Set up token registration parameters
        uint256 token0 = 789;
        uint256 token1 = 1011;
        bytes32 conditionId = keccak256("another-condition");

        // Try to register tokens as random user (should fail)
        vm.startPrank(randomUser);

        // Expect revert with NotAdmin error
        vm.expectRevert(abi.encodeWithSignature("NotAdmin()"));
        exchange.registerToken(token0, token1, conditionId);

        vm.stopPrank();
    }

    function testPermissionRemoval() public {
        // Test that deployer can remove MarketCreator as admin
        vm.startPrank(deployer);

        exchange.removeAdmin(address(marketCreator));

        vm.stopPrank();

        bool isStillAdmin = exchange.isAdmin(address(marketCreator));
        assertFalse(isStillAdmin, "MarketCreator should no longer be admin after removal");

        // Verify MarketCreator can no longer register tokens
        vm.startPrank(address(marketCreator));

        uint256 token0 = 1213;
        uint256 token1 = 1415;
        bytes32 conditionId = keccak256("test-after-removal");

        vm.expectRevert(abi.encodeWithSignature("NotAdmin()"));
        exchange.registerToken(token0, token1, conditionId);

        vm.stopPrank();
    }
}
