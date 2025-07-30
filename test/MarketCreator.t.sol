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

    function _initialLiquidity(address to, address spender, uint256 tokenAmount) internal {
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        approve(address(collateral), address(ctf), type(uint256).max);

        dealAndApprove(address(collateral), to, spender, tokenAmount);
        IERC1155(address(ctf)).setApprovalForAll(spender, true);

        uint256 splitAmount = tokenAmount;
        ctf.splitPosition(IERC20(address(collateral)), bytes32(0), conditionId, partition, splitAmount);
    }

    function _resolveMarket(uint256 outcome) internal {
        bytes32 questionId = keccak256(abi.encodePacked(questionText));
        conditionId = ctf.getConditionId(oracle, questionId, 2);
        vm.prank(oracle);
        oracleResolver.resolveMarket(conditionId, outcome);
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

    // function testMarketResolution() public {
    //     // First create the market and do some trading
    //     (conditionId, yesTokenId, noTokenId) = _createMarket();
    //     // Admin approves CTF for exchange
    //     vm.startPrank(admin);
    //     IERC1155(address(ctf)).setApprovalForAll(address(exchange), true);
    //     vm.stopPrank();

    //     Order memory buy = _createAndSignOrder(trader1PK, yes, 60_000_000, 100_000_000, Side.BUY);
    //     Order memory sellA = _createAndSignOrder(trader2PK, yes, 50_000_000, 25_000_000, Side.SELL);
    //     Order memory sellB = _createAndSignOrder(trader2PK, yes, 100_000_000, 50_000_000, Side.SELL);
    //     Order[] memory makerOrders = new Order[](2);
    //     makerOrders[0] = sellA;
    //     makerOrders[1] = sellB;

    //     uint256[] memory fillAmounts = new uint256[](2);
    //     fillAmounts[0] = 50_000_000;
    //     fillAmounts[1] = 70_000_000;

    //     checkpointCollateral(trader2);
    //     checkpointCTF(trader1, yes);

    //     // First maker order is filled completely
    //     vm.expectEmit(true, true, true, false);
    //     emit OrderFilled(exchange.hashOrder(sellA), trader2, trader1, yes, 0, 50_000_000, 25_000_000, 0);

    //     // Second maker order is partially filled
    //     vm.expectEmit(true, true, true, false);
    //     emit OrderFilled(exchange.hashOrder(sellB), trader2, trader1, yes, 0, 70_000_000, 35_000_000, 0);

    //     // The taker order is filled completely
    //     vm.expectEmit(true, true, true, false);
    //     emit OrderFilled(exchange.hashOrder(buy), trader1, address(exchange), 0, yes, 60_000_000, 120_000_000, 0);

    //     vm.prank(admin);
    //     exchange.matchOrders(buy, makerOrders, 60_000_000, fillAmounts);

    //     // Oracle resolves the market (YES outcome)
    //     _resolveMarket(1); // YES wins (outcome = 1)

    //     // Trader1 redeems their winning YES tokens
    //     vm.startPrank(trader1);

    //     uint256 trader1BalanceBefore = collateral.balanceOf(trader1);

    //     uint256[] memory indexSets = new uint256[](1);
    //     indexSets[0] = 1; // YES tokens (index set 1)

    //     ctf.redeemPositions(IERC20(address(collateral)), bytes32(0), conditionId, indexSets);

    //     uint256 trader1BalanceAfter = collateral.balanceOf(trader1);

    //     // Verify trader1 received collateral for winning tokens
    //     assertEq(trader1BalanceAfter - trader1BalanceBefore, 49_000_000, "Trader1 didn't receive winnings");

    //     vm.stopPrank();
    // }

    function testGetMarketDataByQuestion_Success() public {
        // Step 1: Create a market with a specific question
        vm.startPrank(trader1);
        collateral.approve(address(ctf), initialLiquidity);

        (bytes32 conditionId, uint256 yesTokenId, uint256 noTokenId) = marketCreator.createMarket(questionText, oracle);

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

        // Step 2: Try to retrieve with extra whitespace
        string memory questionWithExtraSpace = " Will ETH surpass $5000 by the end of 2025? ";

        vm.expectRevert("Market not found");
        marketCreator.getMarketDataByQuestion(questionWithExtraSpace);

        // This shows that whitespace matters
    }

    function testGetMarketDataByQuestion_ExactStringMatching() public {
        // Step 1: Create a market
        vm.startPrank(trader1);
        collateral.approve(address(ctf), initialLiquidity);
        (bytes32 conditionId, uint256 yesTokenId, uint256 noTokenId) = marketCreator.createMarket(questionText, oracle);
        vm.stopPrank();

        // Step 2: Log the hash of the question for debugging
        bytes32 questionId = keccak256(abi.encodePacked(questionText));

        // Step 3: Try different variations of the string to find exact match
        // (This is helpful for debugging when working with UUIDs)

        // Get original question hash
        bytes32 originalQuestionHash = keccak256(abi.encodePacked(questionText));

        // Log the market data to verify it exists
        (bytes32 storedConditionId, uint256 storedYesTokenId, uint256 storedNoTokenId) =
            marketCreator.questionIdToMarketData(questionId);

        // Verify they match the returned values
        assertEq(storedConditionId, conditionId, "Condition ID mismatch in stored data");
        assertEq(storedYesTokenId, yesTokenId, "YES token ID mismatch in stored data");
        assertEq(storedNoTokenId, noTokenId, "NO token ID mismatch in stored data");
    }
}
