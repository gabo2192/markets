// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseExchangeTest} from "./BaseExchangeTest.sol";
import {MarketCreator} from "../src/MarketCreator.sol";
import {OracleResolver} from "../src/OracleResolver.sol";
import {Order, Side, SignatureType} from "../src/libraries/OrderStructs.sol";

/**
 * @title MarketCreatorTest
 * @notice Test contract for MarketCreator functionality
 */
contract MarketCreatorTest is BaseExchangeTest {
    MarketCreator public marketCreator;
    OracleResolver public oracleResolver;

    // Market data
    bytes32 public conditionId;
    uint256 public yesTokenId;
    uint256 public noTokenId;
    string public questionText = "Will ETH surpass $5000 by the end of 2025?";
    uint256 public initialLiquidity = 1000 * 10 ** 6; // 1000 USDC
    uint256 public amount = 400 * 10 ** 6; // 400 USDC

    function setUp() public override {
        super.setUp();

        // Deploy market creator and oracle resolver
        marketCreator = new MarketCreator(address(ctf), address(exchange), address(collateral));
        oracleResolver = new OracleResolver(address(ctf));

        // Add market creator as admin of exchange
        vm.prank(admin);
        exchange.addAdmin(address(marketCreator));

        // Transfer ownership of OracleResolver to the oracle
        oracleResolver.transferOwnership(oracle);

        // Set up accounts with funds
        dealTokens(address(collateral), admin, initialLiquidity * 2);
        dealTokens(address(collateral), trader1, initialLiquidity);
        dealTokens(address(collateral), trader2, initialLiquidity);

        // Approvals
        vm.prank(admin);
        collateral.approve(address(marketCreator), initialLiquidity);

        // Label contracts
        vm.label(address(marketCreator), "MarketCreator");
        vm.label(address(oracleResolver), "OracleResolver");
    }

    /* Helper methods specific to market creator tests */

    function _createMarket() internal returns (bytes32, uint256, uint256) {
        vm.prank(admin);
        (bytes32 condId, uint256 yesId, uint256 noId) =
            marketCreator.createMarket(questionText, address(oracleResolver), initialLiquidity);
        return (condId, yesId, noId);
    }

    function _resolveMarket(bytes32 _conditionId, uint256 outcome) internal {
        vm.prank(oracle);
        oracleResolver.resolveMarket(_conditionId, outcome);
    }

    /* Test cases */

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
        (conditionId, yesTokenId, noTokenId) = _createMarket();

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
    }

    function testTradingWithRealExchange() public {
        // First create the market
        (conditionId, yesTokenId, noTokenId) = _createMarket();

        // Admin approves CTF for exchange
        vm.startPrank(admin);
        ctf.setApprovalForAll(address(exchange), true);
        vm.stopPrank();

        // Create and sign a sell order for YES tokens using our helper
        Order memory sellOrder = _createAndSignOrder(
            adminPK,
            yesTokenId,
            amount, // Selling 400 YES tokens
            amount, // For 400 USDC (1:1 price)
            Side.SELL
        );

        // Trader1 fills the order
        vm.startPrank(trader1);
        collateral.approve(address(exchange), amount);
        exchange.fillOrder(sellOrder, amount);
        vm.stopPrank();

        // Verify trader1 received YES tokens
        assertEq(ctf.balanceOf(trader1, yesTokenId), amount, "Trader1 didn't receive YES tokens");
        // Verify admin received collateral
        assertEq(
            collateral.balanceOf(admin),
            initialLiquidity * 2 - initialLiquidity + amount,
            "Admin didn't receive collateral"
        );
    }

    function testMarketResolution() public {
        // First create the market and do some trading
        testTradingWithRealExchange();

        // Oracle resolves the market (YES outcome)
        _resolveMarket(conditionId, 1); // YES wins (outcome = 1)

        // Verify market is resolved
        assertTrue(ctf.isMarketResolved(conditionId), "Market was not resolved");

        // Trader1 redeems their winning YES tokens
        vm.startPrank(trader1);

        uint256 trader1BalanceBefore = collateral.balanceOf(trader1);

        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = 1; // YES tokens (index set 1)

        ctf.redeemPositions(collateral, bytes32(0), conditionId, indexSets);

        uint256 trader1BalanceAfter = collateral.balanceOf(trader1);

        // Verify trader1 received collateral for winning tokens
        assertEq(trader1BalanceAfter - trader1BalanceBefore, 400 * 10 ** 6, "Trader1 didn't receive winnings");

        vm.stopPrank();
    }

    function testCompleteFlow() public {
        // ================ PHASE 1: MARKET CREATION ================
        (conditionId, yesTokenId, noTokenId) = _createMarket();

        // Admin approves exchange to transfer tokens
        vm.startPrank(admin);
        ctf.setApprovalForAll(address(exchange), true);
        collateral.approve(address(exchange), 1000 * 10 ** 6); // Approve exchange to transfer collateral

        // Create sell orders for both YES and NO tokens
        Order memory sellYesOrder = _createAndSignOrder(adminPK, yesTokenId, amount, amount, Side.SELL);

        Order memory sellNoOrder = _createAndSignOrder(adminPK, noTokenId, amount, amount, Side.SELL);

        vm.stopPrank();

        // ================ PHASE 2: TRADING ================

        // Trader1 approves collateral for exchange
        vm.startPrank(trader1);
        collateral.approve(address(exchange), amount);

        // Trader1 fills the order
        exchange.fillOrder(sellYesOrder, amount);
        vm.stopPrank();

        // Verify trader1 received YES tokens
        assertEq(ctf.balanceOf(trader1, yesTokenId), amount, "Trader1 didn't receive YES tokens");

        // Trader2 approves collateral for exchange
        vm.startPrank(trader2);
        collateral.approve(address(exchange), amount);

        // Trader2 fills the NO order
        exchange.fillOrder(sellNoOrder, amount);
        vm.stopPrank();

        // Verify trader2 received NO tokens
        assertEq(ctf.balanceOf(trader2, noTokenId), amount, "Trader2 didn't receive NO tokens");

        // ================ PHASE 3: MARKET RESOLUTION ================

        // Move time forward
        vm.warp(block.timestamp + 30 days);

        // Oracle resolves the market (YES outcome)
        _resolveMarket(conditionId, 1); // YES wins

        // ================ PHASE 4: REDEMPTION ================

        // Trader1 redeems winning YES tokens
        vm.startPrank(trader1);
        uint256 balanceBefore = collateral.balanceOf(trader1);

        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = 1; // YES tokens

        ctf.redeemPositions(collateral, bytes32(0), conditionId, indexSets);

        uint256 balanceAfter = collateral.balanceOf(trader1);
        assertEq(balanceAfter - balanceBefore, amount, "Trader1 didn't receive correct winnings");
        vm.stopPrank();

        // Trader2 tries to redeem losing NO tokens (should get 0)
        vm.startPrank(trader2);
        balanceBefore = collateral.balanceOf(trader2);

        indexSets = new uint256[](1);
        indexSets[0] = 2; // NO tokens

        ctf.redeemPositions(collateral, bytes32(0), conditionId, indexSets);

        balanceAfter = collateral.balanceOf(trader2);
        assertEq(balanceAfter, balanceBefore, "Trader2 shouldn't receive winnings for losing tokens");
        vm.stopPrank();

        // Admin redeems remaining YES tokens
        vm.startPrank(admin);
        balanceBefore = collateral.balanceOf(admin);

        indexSets = new uint256[](1);
        indexSets[0] = 1; // YES tokens

        ctf.redeemPositions(collateral, bytes32(0), conditionId, indexSets);

        balanceAfter = collateral.balanceOf(admin);
        uint256 expectedWinnings = initialLiquidity - amount; // Initial YES tokens minus tokens sold
        assertEq(balanceAfter - balanceBefore, expectedWinnings, "Admin didn't receive correct winnings");
        vm.stopPrank();
    }

    function testMarketWithMultipleTraders() public {
        // Create market
        (conditionId, yesTokenId, noTokenId) = _createMarket();

        // Admin creates a liquidity pool by offering both YES and NO tokens
        vm.startPrank(admin);
        ctf.setApprovalForAll(address(exchange), true);

        // Create YES sell order at 0.4 (40%)
        Order memory sellYesOrder = _createAndSignOrder(
            adminPK,
            yesTokenId,
            500 * 10 ** 6, // Selling 500 YES tokens
            200 * 10 ** 6, // For 200 USDC (price 0.4)
            Side.SELL
        );

        // Create NO sell order at 0.7 (70%)
        Order memory sellNoOrder = _createAndSignOrder(
            adminPK,
            noTokenId,
            500 * 10 ** 6, // Selling 500 NO tokens
            350 * 10 ** 6, // For 350 USDC (price 0.7)
            Side.SELL
        );
        vm.stopPrank();

        // Trader1 buys YES tokens
        vm.startPrank(trader1);
        collateral.approve(address(exchange), 200 * 10 ** 6);
        exchange.fillOrder(sellYesOrder, 500 * 10 ** 6);
        vm.stopPrank();

        // Trader2 buys NO tokens
        vm.startPrank(trader2);
        collateral.approve(address(exchange), 350 * 10 ** 6);
        exchange.fillOrder(sellNoOrder, 500 * 10 ** 6);
        vm.stopPrank();

        // Verify traders received correct tokens
        assertEq(ctf.balanceOf(trader1, yesTokenId), 500 * 10 ** 6, "Trader1 didn't receive correct YES tokens");
        assertEq(ctf.balanceOf(trader2, noTokenId), 500 * 10 ** 6, "Trader2 didn't receive correct NO tokens");

        // Resolve market as YES
        _resolveMarket(conditionId, 1);

        // Trader1 redeems winning YES tokens
        vm.startPrank(trader1);
        uint256 balanceBefore = collateral.balanceOf(trader1);

        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = 1; // YES tokens

        ctf.redeemPositions(collateral, bytes32(0), conditionId, indexSets);

        uint256 balanceAfter = collateral.balanceOf(trader1);
        assertEq(balanceAfter - balanceBefore, 500 * 10 ** 6, "Trader1 didn't receive full winnings");
        vm.stopPrank();
    }

    function testInvalidMarketCreation() public {
        // Test with zero address for oracle
        vm.startPrank(admin);
        vm.expectRevert("Oracle cannot be zero address");
        marketCreator.createMarket(questionText, address(0), initialLiquidity);
        vm.stopPrank();

        // Test with zero initial liquidity
        vm.startPrank(admin);
        vm.expectRevert("Initial liquidity must be greater than zero");
        marketCreator.createMarket(questionText, address(oracleResolver), 0);
        vm.stopPrank();

        // Test insufficient allowance
        vm.startPrank(trader1);
        // Don't approve any tokens
        vm.expectRevert(); // Will revert when trying to transfer tokens
        marketCreator.createMarket(questionText, address(oracleResolver), initialLiquidity);
        vm.stopPrank();
    }

    function testMultipleMarketsCreation() public {
        // Create first market
        (bytes32 condId1, uint256 yesId1, uint256 noId1) = _createMarket();

        // Create second market with different question
        string memory questionText2 = "Will BTC reach $100,000 by the end of 2025?";

        vm.startPrank(admin);
        collateral.approve(address(marketCreator), initialLiquidity);
        (bytes32 condId2, uint256 yesId2, uint256 noId2) =
            marketCreator.createMarket(questionText2, address(oracleResolver), initialLiquidity);
        vm.stopPrank();

        // Verify different condition IDs were created
        assertTrue(condId1 != condId2, "Condition IDs should be different");
        assertTrue(yesId1 != yesId2, "YES token IDs should be different");
        assertTrue(noId1 != noId2, "NO token IDs should be different");

        // Verify both markets are properly registered
        (uint256 complement1, bytes32 registeredCondId1) = exchange.registry(yesId1);
        assertEq(complement1, noId1, "First market YES token complement mismatch");
        assertEq(registeredCondId1, condId1, "First market condition ID mismatch");

        (uint256 complement2, bytes32 registeredCondId2) = exchange.registry(yesId2);
        assertEq(complement2, noId2, "Second market YES token complement mismatch");
        assertEq(registeredCondId2, condId2, "Second market condition ID mismatch");
    }

    function testDifferentOutcomeResolutions() public {
        // Create market
        (conditionId, yesTokenId, noTokenId) = _createMarket();

        // Split initial liquidity between traders
        vm.startPrank(admin);
        ctf.safeTransferFrom(admin, trader1, yesTokenId, amount, "");
        ctf.safeTransferFrom(admin, trader2, noTokenId, amount, "");
        vm.stopPrank();

        // Verify initial distribution
        assertEq(ctf.balanceOf(trader1, yesTokenId), amount, "Trader1 didn't receive YES tokens");
        assertEq(ctf.balanceOf(trader2, noTokenId), amount, "Trader2 didn't receive NO tokens");

        // Resolve market as NO (outcome = 0)
        _resolveMarket(conditionId, 0);

        // Trader2 redeems winning NO tokens
        vm.startPrank(trader2);
        uint256 balanceBefore = collateral.balanceOf(trader2);

        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = 2; // NO tokens

        ctf.redeemPositions(collateral, bytes32(0), conditionId, indexSets);

        uint256 balanceAfter = collateral.balanceOf(trader2);
        assertEq(balanceAfter - balanceBefore, amount, "Trader2 didn't receive winnings");
        vm.stopPrank();

        // Trader1 tries to redeem losing YES tokens (should get 0)
        vm.startPrank(trader1);
        balanceBefore = collateral.balanceOf(trader1);

        indexSets[0] = 1; // YES tokens

        ctf.redeemPositions(collateral, bytes32(0), conditionId, indexSets);

        balanceAfter = collateral.balanceOf(trader1);
        assertEq(balanceAfter, balanceBefore, "Trader1 shouldn't receive winnings for losing tokens");
        vm.stopPrank();
    }
}
