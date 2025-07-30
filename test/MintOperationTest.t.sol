// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/CTFExchange.sol";
import "../src/ConditionalTokens.sol";
import {MarketCreator} from "../src/MarketCreator.sol";
import {Side, SignatureType, Order} from "../src/libraries/OrderStructs.sol";

// Mocked ERC20 token for testing
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("MockUSDC", "USDC") {
        _mint(msg.sender, 1000000 * 10 ** 6); // Mint 1M USDC
    }

    function decimals() public pure override returns (uint8) {
        return 6; // Standard for USDC
    }
}

contract MintOperationTest is Test {
    // Contracts
    MockUSDC usdc;
    ConditionalTokens ctf;
    CTFExchange exchange;

    // Addresses
    address admin = address(1);
    address oracle = address(2);
    address user1 = address(3);
    address user2 = address(4);

    // Market data
    bytes32 conditionId;
    uint256 yesTokenId;
    uint256 noTokenId;

    function setUp() public {
        // Deploy contracts
        vm.startPrank(admin);
        usdc = new MockUSDC();
        ctf = new ConditionalTokens();
        exchange = new CTFExchange(address(usdc), address(ctf));

        // Setup the market directly with the CTF contract
        bytes32 questionId = keccak256(abi.encodePacked("Will ETH reach $10k?"));
        ctf.prepareCondition(oracle, questionId, 2);
        conditionId = ctf.getConditionId(oracle, questionId, 2);

        // Calculate token IDs
        bytes32 yesCollectionId = ctf.getCollectionId(bytes32(0), conditionId, 1);
        bytes32 noCollectionId = ctf.getCollectionId(bytes32(0), conditionId, 2);
        yesTokenId = ctf.getPositionId(IERC20(address(usdc)), yesCollectionId);
        noTokenId = ctf.getPositionId(IERC20(address(usdc)), noCollectionId);

        // Register tokens on exchange
        exchange.registerToken(yesTokenId, noTokenId, conditionId);

        // Transfer USDC to users
        usdc.transfer(user1, 100_000 * 10 ** 6);
        usdc.transfer(user2, 100_000 * 10 ** 6);

        // Make user1 and user2 operators
        exchange.addOperator(user1);
        exchange.addOperator(user2);
        vm.stopPrank();

        // Setup approvals for user1
        vm.startPrank(user1);
        usdc.approve(address(exchange), type(uint256).max);
        ctf.setApprovalForAll(address(exchange), true);
        vm.stopPrank();

        // Setup approvals for user2
        vm.startPrank(user2);
        usdc.approve(address(exchange), type(uint256).max);
        ctf.setApprovalForAll(address(exchange), true);
        vm.stopPrank();
    }

    function testMintOperation() public {
        vm.startPrank(user1);

        // Print diagnostics
        console.log("Exchange YES token ID:", yesTokenId);
        console.log("Exchange NO token ID:", noTokenId);
        console.log("Condition ID:");
        console.logBytes32(conditionId);

        // Create and sign orders
        Order memory buyYesOrder = createOrder(
            user1,
            yesTokenId,
            1_000_000, // 1 USDC
            2_854_289, // ~0.35 price
            Side.BUY
        );

        vm.stopPrank();
        vm.startPrank(user2);

        Order memory buyNoOrder = createOrder(
            user2,
            noTokenId,
            6_500_000, // 6.5 USDC
            10_000_000, // 0.65 price
            Side.BUY
        );

        // Log initial balances
        logBalances("Before match");

        // First try with standard parameters
        console.log("=== Testing standard parameters ===");
        try exchange.matchOrders(buyYesOrder, _toArray(buyNoOrder), 1_000_000, _toArrayUint(1_000_000)) {
            console.log("Standard match successful!");
        } catch Error(string memory reason) {
            console.log("Standard match failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.logBytes(lowLevelData);
            console.log("Standard match failed with low-level error");
        }

        // Now try with adjusted parameters (5% buffer, 90% fill)
        console.log("\n=== Testing adjusted parameters ===");

        // Create orders with buffers
        Order memory adjustedYesOrder = createOrder(
            user1,
            yesTokenId,
            1_050_000, // Added 5% buffer
            2_854_289,
            Side.BUY
        );

        Order memory adjustedNoOrder = createOrder(
            user2,
            noTokenId,
            6_825_000, // Added 5% buffer
            10_000_000,
            Side.BUY
        );

        // Calculate 90% fill amount
        uint256 fillAmount = 945_000; // 90% of adjusted amount

        try exchange.matchOrders(adjustedYesOrder, _toArray(adjustedNoOrder), fillAmount, _toArrayUint(fillAmount)) {
            console.log("Adjusted match successful!");
        } catch Error(string memory reason) {
            console.log("Adjusted match failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.logBytes(lowLevelData);
            console.log("Adjusted match failed with low-level error");
        }

        logBalances("After adjusted match");

        vm.stopPrank();
    }

    function testPriceRatioSweep() public {
        // Test multiple price combinations
        console.log("=== Price Ratio Sweep ===");

        uint256[] memory yesPrices = new uint256[](3);
        yesPrices[0] = 35; // 0.35
        yesPrices[1] = 40; // 0.40
        yesPrices[2] = 45; // 0.45

        uint256[] memory noPrices = new uint256[](3);
        noPrices[0] = 65; // 0.65
        noPrices[1] = 60; // 0.60
        noPrices[2] = 55; // 0.55

        // Standard test amount (1 USDC)
        uint256 baseAmount = 1_000_000;

        for (uint256 i = 0; i < yesPrices.length; i++) {
            uint256 yesPrice = yesPrices[i];

            for (uint256 j = 0; j < noPrices.length; j++) {
                uint256 noPrice = noPrices[j];
                console.log("\nTesting YES:", yesPrice, "/ NO:", noPrice);

                // Skip if prices don't add up to 100
                if (yesPrice + noPrice != 100) {
                    console.log("Prices don't add up to 100, skipping");
                    continue;
                }

                // Calculate token amounts for the given prices
                uint256 yesTokens = (baseAmount * 100) / yesPrice;
                uint256 noTokens = (baseAmount * 100) / noPrice;

                vm.startPrank(user1);
                Order memory yesOrder = createOrder(user1, yesTokenId, baseAmount, yesTokens, Side.BUY);
                vm.stopPrank();

                vm.startPrank(user2);
                Order memory noOrder = createOrder(user2, noTokenId, baseAmount, noTokens, Side.BUY);

                // Try standard match first
                bool standardSuccess = false;
                try exchange.matchOrders(yesOrder, _toArray(noOrder), baseAmount, _toArrayUint(baseAmount)) {
                    standardSuccess = true;
                    console.log("Standard match succeeded");
                } catch {
                    console.log("Standard match failed");
                }

                // Try with our adjustments if standard failed
                if (!standardSuccess) {
                    // Apply buffers
                    uint256 buffer = 5; // 5%
                    uint256 adjustedYesAmount = baseAmount + (baseAmount * buffer / 100);
                    uint256 adjustedNoAmount = baseAmount + (baseAmount * buffer / 100);

                    Order memory adjustedYesOrder =
                        createOrder(user1, yesTokenId, adjustedYesAmount, yesTokens, Side.BUY);

                    Order memory adjustedNoOrder = createOrder(user2, noTokenId, adjustedNoAmount, noTokens, Side.BUY);

                    // Calculate 90% fill
                    uint256 reduceFactor = 10; // 10%
                    uint256 fillAmount = (adjustedYesAmount * (100 - reduceFactor)) / 100;

                    try exchange.matchOrders(
                        adjustedYesOrder, _toArray(adjustedNoOrder), fillAmount, _toArrayUint(fillAmount)
                    ) {
                        console.log("Adjusted match succeeded with:");
                        console.log("  Buffer:", buffer, "%");
                        console.log("  Fill reduction:", reduceFactor, "%");
                    } catch Error(string memory reason) {
                        console.log("Adjusted match failed with reason:", reason);

                        // Try with more aggressive parameters
                        buffer = 10; // 10%
                        reduceFactor = 20; // 20%

                        adjustedYesAmount = baseAmount + (baseAmount * buffer / 100);
                        adjustedNoAmount = baseAmount + (baseAmount * buffer / 100);
                        fillAmount = (adjustedYesAmount * (100 - reduceFactor)) / 100;

                        adjustedYesOrder = createOrder(user1, yesTokenId, adjustedYesAmount, yesTokens, Side.BUY);

                        adjustedNoOrder = createOrder(user2, noTokenId, adjustedNoAmount, noTokens, Side.BUY);

                        try exchange.matchOrders(
                            adjustedYesOrder, _toArray(adjustedNoOrder), fillAmount, _toArrayUint(fillAmount)
                        ) {
                            console.log("Aggressive match succeeded with:");
                            console.log("  Buffer:", buffer, "%");
                            console.log("  Fill reduction:", reduceFactor, "%");
                        } catch {
                            console.log("Even aggressive match failed");
                        }
                    }
                }

                vm.stopPrank();

                // Reset state for next test by minting some tokens to users
                // This avoids having to resolve markets between tests
                vm.deal(user1, 1 ether);
                vm.deal(user2, 1 ether);
                vm.startPrank(admin);
                usdc.transfer(user1, 10_000_000);
                usdc.transfer(user2, 10_000_000);
                vm.stopPrank();
            }
        }
    }

    // Helper function to create and sign an order
    function createOrder(address maker, uint256 tokenId, uint256 makerAmount, uint256 takerAmount, Side side)
        internal
        view
        returns (Order memory)
    {
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, maker, tokenId));

        return Order({
            salt: uint256(salt),
            maker: maker,
            signer: maker,
            taker: address(0), // Public order
            tokenId: tokenId,
            makerAmount: makerAmount,
            takerAmount: takerAmount,
            expiration: 0, // No expiration
            nonce: 0,
            feeRateBps: 200, // 2% fee
            side: side,
            signatureType: SignatureType.EOA,
            signature: "0x" // No signature needed in test
        });
    }

    // Helper to convert to array
    function _toArray(Order memory order) internal pure returns (Order[] memory) {
        Order[] memory orders = new Order[](1);
        orders[0] = order;
        return orders;
    }

    function _toArrayUint(uint256 amount) internal pure returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        return amounts;
    }

    // Log balances for debugging
    function logBalances(string memory label) internal view {
        console.log("=== Balances:", label, "===");
        console.log("User1 USDC:", usdc.balanceOf(user1) / 10 ** 6);
        console.log("User2 USDC:", usdc.balanceOf(user2) / 10 ** 6);
        console.log("Exchange USDC:", usdc.balanceOf(address(exchange)) / 10 ** 6);
        console.log("User1 YES tokens:", ctf.balanceOf(user1, yesTokenId) / 10 ** 6);
        console.log("User2 YES tokens:", ctf.balanceOf(user2, yesTokenId) / 10 ** 6);
        console.log("User1 NO tokens:", ctf.balanceOf(user1, noTokenId) / 10 ** 6);
        console.log("User2 NO tokens:", ctf.balanceOf(user2, noTokenId) / 10 ** 6);
        console.log("Exchange YES tokens:", ctf.balanceOf(address(exchange), yesTokenId) / 10 ** 6);
        console.log("Exchange NO tokens:", ctf.balanceOf(address(exchange), noTokenId) / 10 ** 6);
    }
}
