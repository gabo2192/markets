// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MarketCreator} from "../src/MarketCreator.sol";
import {OracleResolver} from "../src/OracleResolver.sol";
import {Order, Side, SignatureType} from "../src/libraries/OrderStructs.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {USDC, ERC20} from "./mocks/USDC.sol";
import {ConditionalTokens} from "src/ConditionalTokens.sol";
import {CTFExchange} from "../src/CTFExchange.sol";
import {Test, console} from "forge-std/Test.sol";

/**
 * @title MarketCreatorTest
 * @notice Test contract for MarketCreator functionality
 */
contract CloseMarketTest is Test {
    error NotCrossing();
    error NotTaker();
    error MakingGtRemaining();
    error MismatchedTokenIds();

    USDC public collateral;
    ConditionalTokens public ctf;
    CTFExchange public exchange;

    // Constants for proxy factories (using dummy addresses for testing)
    address public constant PROXY_FACTORY = address(0x5);
    address public constant SAFE_FACTORY = address(0x6);

    // Test accounts
    address public admin = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    address public oracle = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
    address public trader1 = address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC);
    address public trader2 = address(0x90F79bf6EB2c4f870365E785982E1f101E93b906);

    // Private keys (useful for signing orders)
    uint256 internal adminPK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 internal oraclePK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 internal trader1PK = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 internal trader2PK = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    // Common test values
    uint256 public constant INITIAL_BALANCE = 1000 * 10 ** 6; // 1000 USDC
    bytes32 public constant questionID = hex"1234";
    bytes32 public conditionId;
    uint256 public yes;
    uint256 public no;
    MarketCreator public marketCreator;
    OracleResolver public oracleResolver;

    // Market data

    uint256 public yesTokenId;
    uint256 public noTokenId;
    string public questionText = "Will ETH surpass $5000 by the end of 2025?";
    uint256 public initialLiquidity = 1000 * 10 ** 6; // 1000 USDC
    uint256 public amount = 400 * 10 ** 6; // 400 USDC

    function setUp() public {
        // Deploy mock tokens
        collateral = new USDC();
        ctf = new ConditionalTokens();

        // Deploy exchange
        exchange = new CTFExchange(address(collateral), address(ctf));
        // exchange.registerToken(yes, no, conditionId);
        // Setup exchange permissions
        exchange.addAdmin(admin);
        exchange.addOperator(admin);
        exchange.addOperator(trader1);
        exchange.addOperator(trader2);
        // Label accounts for better test output
        vm.label(admin, "admin");
        vm.label(oracle, "oracle");
        vm.label(trader1, "trader1");
        vm.label(trader2, "trader2");
        vm.label(address(collateral), "USDC");
        vm.label(address(ctf), "CTF");
        vm.label(address(exchange), "Exchange");

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
        dealTokens(address(collateral), trader1, initialLiquidity * 2);
        dealTokens(address(collateral), trader2, initialLiquidity);

        // Approvals
        vm.prank(admin);
        approve(address(collateral), address(ctf), initialLiquidity);

        // Label contracts
        vm.label(address(marketCreator), "MarketCreator");
        vm.label(address(oracleResolver), "OracleResolver");
        // _mintTestTokens(trader1, address(exchange), 20_000_000_000_000);
        // _mintTestTokens(trader2, address(exchange), 20_000_000_000_000);
    }

    function _prepareCondition(address _oracle, bytes32 _questionId) internal returns (bytes32) {
        ctf.prepareCondition(_oracle, _questionId, 2);
        return ctf.getConditionId(_oracle, _questionId, 2);
    }

    /* Helper methods specific to market creator tests */

    function _createMarket() internal returns (bytes32, uint256, uint256) {
        vm.prank(admin);
        console.log("createMarket");
        console.log("oracleResolver", address(oracleResolver));
        console.log("marketCreator", address(marketCreator));
        (bytes32 condId, uint256 yesId, uint256 noId) =
            marketCreator.createMarket(questionText, address(oracleResolver));
        return (condId, yesId, noId);
    }

    function _resolveMarket(bytes32 _conditionId, uint256 outcome) internal {
        vm.prank(oracle);
        bytes32 questionId = keccak256(abi.encodePacked(questionText));
        oracleResolver.resolveMarket(questionId, outcome);
    }

    function dealAndApprove(address _token, address _to, address _spender, uint256 _amount) internal {
        deal(_token, _to, _amount);
        approve(_token, _spender, _amount);
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

    function _mintTestTokens(address to, address spender, uint256 amount) internal {
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        vm.startPrank(to);
        approve(address(collateral), address(ctf), type(uint256).max);

        dealAndApprove(address(collateral), to, spender, amount);
        IERC1155(address(ctf)).setApprovalForAll(spender, true);

        uint256 splitAmount = amount / 2;
        ctf.splitPosition(IERC20(address(collateral)), bytes32(0), conditionId, partition, splitAmount);
        vm.stopPrank();
    }

    /* Test cases */

    function testMarketResolution() public {
        // First create the market and do some trading
        (conditionId, yesTokenId, noTokenId) = _createMarket();
        console.log("conditionId");
        console.logBytes32(conditionId);
        console.log("yesTokenId");
        console.log(yesTokenId);
        console.log("noTokenId");
        console.log(noTokenId);
        _initialLiquidity(trader1, address(exchange), initialLiquidity * 2);
        // Admin approves CTF for exchange
        vm.startPrank(admin);
        IERC1155(address(ctf)).setApprovalForAll(address(exchange), true);
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
        assertEq(IERC1155(address(ctf)).balanceOf(trader1, yesTokenId), amount, "Trader1 didn't receive YES tokens");
        // Verify admin received collateral
        assertEq(
            collateral.balanceOf(admin),
            initialLiquidity * 2 - initialLiquidity + amount,
            "Admin didn't receive collateral"
        );

        // Oracle resolves the market (YES outcome)
        _resolveMarket(conditionId, 1); // YES wins (outcome = 1)

        // Trader1 redeems their winning YES tokens
        vm.startPrank(trader1);

        uint256 trader1BalanceBefore = collateral.balanceOf(trader1);

        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = 1; // YES tokens (index set 1)

        ctf.redeemPositions(IERC20(address(collateral)), bytes32(0), conditionId, indexSets);

        uint256 trader1BalanceAfter = collateral.balanceOf(trader1);

        // Verify trader1 received collateral for winning tokens
        assertEq(trader1BalanceAfter - trader1BalanceBefore, 400 * 10 ** 6, "Trader1 didn't receive winnings");

        vm.stopPrank();
    }

    function dealTokens(address token, address to, uint256 a) internal {
        if (token == address(collateral)) {
            collateral.mint(to, a);
        }
    }

    function _createAndSignOrder(uint256 pk, uint256 tokenId, uint256 makerAmount, uint256 takerAmount, Side side)
        internal
        view
        returns (Order memory)
    {
        address maker = vm.addr(pk);
        Order memory order = _createOrder(maker, tokenId, makerAmount, takerAmount, side);
        order.signature = _signMessage(pk, exchange.hashOrder(order));
        return order;
    }

    function _createOrder(address maker, uint256 tokenId, uint256 makerAmount, uint256 takerAmount, Side side)
        internal
        pure
        returns (Order memory)
    {
        Order memory order = Order({
            salt: 1,
            signer: maker,
            maker: maker,
            taker: address(0), // Public order
            tokenId: tokenId,
            makerAmount: makerAmount,
            takerAmount: takerAmount,
            expiration: 0, // No expiration
            nonce: 0,
            feeRateBps: 0, // No fee
            signatureType: SignatureType.EOA,
            side: side,
            signature: new bytes(0)
        });
        return order;
    }

    function _signMessage(uint256 pk, bytes32 message) internal pure returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, message);
        sig = abi.encodePacked(r, s, v);
    }

    function approve(address _token, address _spender, uint256 _amount) internal {
        ERC20(_token).approve(_spender, _amount);
    }
}
