// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {MarketCreator} from "../src/MarketCreator.sol";
import {OracleResolver} from "../src/OracleResolver.sol";
import {Order, Side, SignatureType} from "../src/libraries/OrderStructs.sol";
import {CTFExchange} from "../src/CTFExchange.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockConditionalTokens} from "./mocks/MockConditionalTokens.sol";
import {ISignatures} from "../src/interfaces/ISignatures.sol";

contract MarketCreatorTest is Test {
    MarketCreator public marketCreator;
    OracleResolver public oracleResolver;
    MockERC20 public collateral;
    MockConditionalTokens public ctf;
    CTFExchange public exchange;

    // Test accounts
    address public admin = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    address public oracle = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
    address public trader1 = address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC);
    address public trader2 = address(0x90F79bf6EB2c4f870365E785982E1f101E93b906);

    // Market data
    bytes32 public conditionId;
    uint256 public yesTokenId;
    uint256 public noTokenId;
    string public questionText = "Will ETH surpass $5000 by the end of 2025?";
    uint256 public initialLiquidity = 1000 * 10 ** 6; // 1000 USDC
    uint256 amount = 400 * 10 ** 6;
    uint256 pk;
    // Constants for proxy factories (using dummy addresses for testing)
    address public constant PROXY_FACTORY = address(0x5);
    address public constant SAFE_FACTORY = address(0x6);

    function setUp() public {
        // Deploy mock tokens
        collateral = new MockERC20("USD Coin", "USDC", 6);
        ctf = new MockConditionalTokens();
        pk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        admin = vm.addr(pk);
        // Deploy real CTFExchange
        exchange = new CTFExchange(address(collateral), address(ctf), PROXY_FACTORY, SAFE_FACTORY);

        // Deploy our contracts
        marketCreator = new MarketCreator(address(ctf), address(exchange), address(collateral));

        oracleResolver = new OracleResolver(address(ctf));

        // Setup admin permissions in the exchange
        vm.startPrank(admin);
        vm.expectRevert(); // Should revert since admin is not set yet
        exchange.addAdmin(admin);
        vm.stopPrank();

        // We need to add admin from the contract deployer (this contract)
        exchange.addAdmin(admin);
        exchange.addAdmin(address(marketCreator));
        exchange.addOperator(admin);

        // Transfer ownership of OracleResolver to the oracle
        oracleResolver.transferOwnership(oracle);

        // Set up accounts with funds
        collateral.mint(admin, initialLiquidity * 2);
        collateral.mint(trader1, initialLiquidity);
        collateral.mint(trader2, initialLiquidity);

        // Approvals
        vm.startPrank(admin);
        collateral.approve(address(marketCreator), initialLiquidity);
        vm.stopPrank();
    }

    function testTraderCanCreateMarket() public {
        uint256 traderLiquidity = 500 * 10 ** 6;

        // Trader1 approves the MarketCreator to spend their USDC
        vm.startPrank(trader1);
        collateral.approve(address(marketCreator), traderLiquidity);

        // Trader1 calls createMarket
        (bytes32 condId, uint256 yesId, uint256 noId) =
            marketCreator.createMarket(questionText, address(oracleResolver), traderLiquidity);

        vm.stopPrank();

        // Verify that the condition was prepared
        bool isPrepared = ctf.conditionPrepared(condId);
        assertTrue(isPrepared, "Condition was not prepared by trader");

        // Verify the tokens minted to trader1
        uint256 yesBalance = ctf.balanceOf(trader1, yesId);
        uint256 noBalance = ctf.balanceOf(trader1, noId);
        assertEq(yesBalance, traderLiquidity, "Trader did not receive correct YES tokens");
        assertEq(noBalance, traderLiquidity, "Trader did not receive correct NO tokens");

        // And confirm it was registered on the exchange
        (uint256 complement, bytes32 registeredCondId) = exchange.registry(yesId);
        assertEq(complement, noId, "YES token complement mismatch");
        assertEq(registeredCondId, condId, "YES token conditionId mismatch");

        // Similarly for the NO token
        (complement, registeredCondId) = exchange.registry(noId);
        assertEq(complement, yesId, "NO token complement mismatch");
        assertEq(registeredCondId, condId, "NO token conditionId mismatch");
    }

    function testMarketCreation() public {
        vm.startPrank(admin);

        // Create the market
        (conditionId, yesTokenId, noTokenId) =
            marketCreator.createMarket(questionText, address(oracleResolver), initialLiquidity);

        // Verify market was created correctly
        assertTrue(ctf.conditionPrepared(conditionId), "Condition not prepared");
        assertEq(ctf.balanceOf(admin, yesTokenId), initialLiquidity, "Admin didn't receive YES tokens");
        assertEq(ctf.balanceOf(admin, noTokenId), initialLiquidity, "Admin didn't receive NO tokens");

        // Verify tokens are registered in the exchange
        (uint256 complement, bytes32 registeredCondition) = exchange.registry(yesTokenId);
        assertEq(complement, noTokenId, "YES token complement incorrect");
        assertEq(registeredCondition, conditionId, "YES token condition ID incorrect");

        (complement, registeredCondition) = exchange.registry(noTokenId);
        assertEq(complement, yesTokenId, "NO token complement incorrect");
        assertEq(registeredCondition, conditionId, "NO token condition ID incorrect");

        vm.stopPrank();
    }

    function testTradingWithRealExchange() public {
        // First create the market
        testMarketCreation();
        // Now set up for trading
        vm.startPrank(admin);

        // Admin approves CTF for exchange
        ctf.setApprovalForAll(address(exchange), true);

        // Admin creates a sell order for YES tokens
        Order memory sellOrder = Order({
            salt: uint256(keccak256(abi.encodePacked("sell-order-1"))),
            maker: admin,
            signer: admin,
            taker: address(0), // Public order
            tokenId: yesTokenId,
            makerAmount: amount, // Selling 400 YES tokens
            takerAmount: amount, // For 400 USDC
            expiration: block.timestamp + 1 days,
            nonce: 0,
            feeRateBps: 0, // No fee for testing
            side: Side.SELL, // SELL (Side.SELL)
            signatureType: SignatureType.EOA, // EOA (SignatureType.EOA)
            signature: "" // We'll mock signature validation
        });

        // Mock signature for the order
        bytes32 orderHash = exchange.hashOrder(sellOrder);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, orderHash); // Admin's private key is 1
        sellOrder.signature = abi.encodePacked(r, s, v);

        vm.stopPrank();

        // Trader1 fills the order
        vm.startPrank(trader1);
        collateral.approve(address(exchange), amount);
        vm.stopPrank();
        collateral.mint(admin, 1_000_000_000);
        // Admin fills the order as an operator (tokens go to admin)
        vm.startPrank(admin);
        collateral.approve(address(exchange), 1_000_000_000);
        exchange.fillOrder(sellOrder, amount);

        // Admin manually transfers the received tokens to trader1
        // This simulates what a relayer would do in the real system
        ctf.safeTransferFrom(admin, trader1, yesTokenId, amount, "");
        vm.stopPrank();

        // Verify trader1 received YES tokens
        assertEq(ctf.balanceOf(trader1, yesTokenId), amount, "Trader1 didn't receive YES tokens");

        vm.stopPrank();
    }

    function testMarketResolution() public {
        // First create the market and do some trading
        testTradingWithRealExchange();

        // Oracle resolves the market (YES outcome)
        vm.startPrank(oracle);
        oracleResolver.resolveMarket(conditionId, 1); // YES wins (outcome = 1)
        vm.stopPrank();

        // Verify market is resolved
        assertTrue(ctf.isMarketResolved(conditionId), "Market was not resolved");

        // Trader1 redeems their winning YES tokens
        vm.startPrank(trader1);

        uint256 trader1BalanceBefore = collateral.balanceOf(trader1);

        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = 1; // YES tokens (index set 1)

        ctf.redeemPositions((collateral), bytes32(0), conditionId, indexSets);

        uint256 trader1BalanceAfter = collateral.balanceOf(trader1);

        // Verify trader1 received collateral for winning tokens
        assertEq(trader1BalanceAfter - trader1BalanceBefore, 400 * 10 ** 6, "Trader1 didn't receive winnings");

        vm.stopPrank();
    }

    function testCompleteFlow() public {
        // ================ PHASE 1: MARKET CREATION ================
        vm.startPrank(admin);
        // Create the market
        (conditionId, yesTokenId, noTokenId) =
            marketCreator.createMarket(questionText, address(oracleResolver), initialLiquidity);

        // Admin approves exchange to transfer tokens
        vm.startPrank(admin);
        ctf.setApprovalForAll(address(exchange), true);
        collateral.approve(address(exchange), 1000 * 10 ** 6); // Approve exchange to transfer collateral

        // Create sell orders for both YES and NO tokens
        Order memory sellYesOrder = Order({
            salt: uint256(keccak256(abi.encodePacked("sell-yes-1"))),
            maker: admin,
            signer: admin,
            taker: address(0),
            tokenId: yesTokenId,
            makerAmount: amount,
            takerAmount: amount,
            expiration: block.timestamp + 1 days,
            nonce: 0,
            feeRateBps: 0,
            side: Side.SELL, // SELL
            signatureType: SignatureType.EOA, // EOA
            signature: ""
        });

        Order memory sellNoOrder = Order({
            salt: uint256(keccak256(abi.encodePacked("sell-no-1"))),
            maker: admin,
            signer: admin,
            taker: address(0),
            tokenId: noTokenId,
            makerAmount: amount,
            takerAmount: amount,
            expiration: block.timestamp + 1 days,
            nonce: 1,
            feeRateBps: 0,
            side: Side.SELL, // SELL
            signatureType: SignatureType.EOA, // EOA
            signature: ""
        });

        // Sign the orders with the matching private key
        bytes32 yesOrderHash = exchange.hashOrder(sellYesOrder);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(pk, yesOrderHash);
        sellYesOrder.signature = abi.encodePacked(r1, s1, v1);

        bytes32 noOrderHash = exchange.hashOrder(sellNoOrder);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(pk, noOrderHash);
        sellNoOrder.signature = abi.encodePacked(r2, s2, v2);

        vm.stopPrank();

        // ================ PHASE 2: TRADING ================

        // Trader1 approves collateral for exchange (this is still needed)
        vm.startPrank(trader1);
        collateral.approve(address(exchange), amount);
        vm.stopPrank();

        // Admin fills the order as an operator (tokens go to admin)
        vm.startPrank(admin);
        exchange.fillOrder(sellYesOrder, amount);

        // Admin manually transfers the received tokens to trader1
        // This simulates what a relayer would do in the real system
        ctf.safeTransferFrom(admin, trader1, yesTokenId, amount, "");
        vm.stopPrank();

        // Then verify trader1 received tokens
        assertEq(ctf.balanceOf(trader1, yesTokenId), amount, "Trader1 didn't receive YES tokens");

        // After filling the first order
        vm.startPrank(admin);
        exchange.incrementNonce(); // Increment to nonce 1
        vm.stopPrank();

        // Trader2 approves collateral for exchange (this is still needed)
        vm.startPrank(trader2);
        collateral.approve(address(exchange), amount);
        vm.stopPrank();

        // Admin (as an operator) fills the order on behalf of trader1
        vm.startPrank(admin);
        exchange.fillOrder(sellNoOrder, amount);
        ctf.safeTransferFrom(admin, trader2, noTokenId, amount, "");
        vm.stopPrank();

        // Then verify trader1 received tokens
        assertEq(ctf.balanceOf(trader2, noTokenId), amount, "Trader1 didn't receive YES tokens");

        // ================ PHASE 3: MARKET RESOLUTION ================

        // Move time forward
        vm.warp(block.timestamp + 30 days);

        // Oracle resolves the market (YES outcome)
        vm.startPrank(oracle);
        oracleResolver.resolveMarket(conditionId, 1); // YES wins
        vm.stopPrank();

        // ================ PHASE 4: REDEMPTION ================

        // Trader1 redeems winning YES tokens
        vm.startPrank(trader1);
        uint256 balanceBefore = collateral.balanceOf(trader1);

        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = 1; // YES tokens

        ctf.redeemPositions((collateral), bytes32(0), conditionId, indexSets);

        uint256 balanceAfter = collateral.balanceOf(trader1);
        assertEq(balanceAfter - balanceBefore, amount, "Trader1 didn't receive correct winnings");
        vm.stopPrank();

        // Trader2 tries to redeem losing NO tokens (should get 0)
        vm.startPrank(trader2);
        balanceBefore = collateral.balanceOf(trader2);

        indexSets = new uint256[](1);
        indexSets[0] = 2; // NO tokens

        ctf.redeemPositions((collateral), bytes32(0), conditionId, indexSets);

        balanceAfter = collateral.balanceOf(trader2);
        assertEq(balanceAfter, balanceBefore, "Trader2 shouldn't receive winnings for losing tokens");
        vm.stopPrank();

        // Admin redeems remaining YES tokens
        vm.startPrank(admin);
        balanceBefore = collateral.balanceOf(admin);

        indexSets = new uint256[](1);
        indexSets[0] = 1; // YES tokens

        ctf.redeemPositions((collateral), bytes32(0), conditionId, indexSets);

        balanceAfter = collateral.balanceOf(admin);
        uint256 expectedWinnings = initialLiquidity - amount; // Initial YES tokens minus tokens sold
        assertEq(balanceAfter - balanceBefore, expectedWinnings, "Admin didn't receive correct winnings");
        vm.stopPrank();
    }
}
