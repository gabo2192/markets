// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Order, Side, SignatureType} from "../src/libraries/OrderStructs.sol";
import {CTFExchange} from "../src/CTFExchange.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockConditionalTokens} from "./mocks/MockConditionalTokens.sol";

/**
 * @title BaseExchangeTest
 * @notice Base contract with common utilities for testing the CTF Exchange and Market Creator
 */
contract BaseExchangeTest is Test {
    MockERC20 public collateral;
    MockConditionalTokens public ctf;
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
    uint256 internal trader1PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 internal trader2PK = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

    // Common test values
    uint256 public constant INITIAL_BALANCE = 1000 * 10 ** 6; // 1000 USDC

    mapping(address => mapping(address => mapping(uint256 => uint256))) private _checkpoints1155;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event TransferSingle(
        address indexed operator, address indexed from, address indexed to, uint256 id, uint256 amount
    );
    event OrderFilled(
        bytes32 indexed orderHash,
        address indexed maker,
        address indexed taker,
        uint256 makerAssetId,
        uint256 takerAssetId,
        uint256 makerAmountFilled,
        uint256 takerAmountFilled,
        uint256 fee
    );

    function setUp() public virtual {
        // Deploy mock tokens
        collateral = new MockERC20("USD Coin", "USDC", 6);
        ctf = new MockConditionalTokens();

        // Deploy exchange
        exchange = new CTFExchange(address(collateral), address(ctf), PROXY_FACTORY, SAFE_FACTORY);

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
    }

    /* Order creation and signing helpers */

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

    function _createAndSignOrderWithFee(
        uint256 pk,
        uint256 tokenId,
        uint256 makerAmount,
        uint256 takerAmount,
        uint256 feeRateBps,
        Side side
    ) internal view returns (Order memory) {
        address maker = vm.addr(pk);
        Order memory order = _createOrder(maker, tokenId, makerAmount, takerAmount, side);
        order.feeRateBps = feeRateBps;
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

    /* Token operations helpers */

    function _mintTestTokens(address to, address spender, uint256 amount) internal {
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        vm.startPrank(to);
        collateral.approve(address(ctf), type(uint256).max);
        collateral.approve(spender, amount);
        ctf.setApprovalForAll(spender, true);

        // Mint some tokens to the user first
        collateral.mint(to, amount);

        // Split position to get outcome tokens
        bytes32 conditionId = ctf.getConditionId(oracle, bytes32(0), 2);
        ctf.splitPosition(collateral, bytes32(0), conditionId, partition, amount);
        vm.stopPrank();
    }

    /* Conditional tokens helpers */

    function _prepareCondition(address _oracle, bytes32 _questionId) internal returns (bytes32) {
        ctf.prepareCondition(_oracle, _questionId, 2);
        return ctf.getConditionId(_oracle, _questionId, 2);
    }

    function _getPositionId(bytes32 conditionId, uint256 indexSet) internal view returns (uint256) {
        return ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), conditionId, indexSet));
    }

    /* Balance assertion helpers */

    function assertTokenBalance(address token, address account, uint256 expected) internal view {
        assertEq(MockERC20(token).balanceOf(account), expected, "Token balance mismatch");
    }

    function assertCTFBalance(address account, uint256 tokenId, uint256 expected) internal view {
        assertEq(ctf.balanceOf(account, tokenId), expected, "CTF token balance mismatch");
    }

    function checkpointCTF(address account, uint256 tokenId) internal {
        _checkpoints1155[address(ctf)][account][tokenId] = ctf.balanceOf(account, tokenId);
    }

    function assertCTFBalanceDiff(address account, uint256 tokenId, uint256 diff) internal view {
        assertEq(
            ctf.balanceOf(account, tokenId) - _checkpoints1155[address(ctf)][account][tokenId],
            diff,
            "CTF balance diff mismatch"
        );
    }

    /* Fund allocation helpers */

    function dealTokens(address token, address to, uint256 amount) internal {
        if (token == address(collateral)) {
            collateral.mint(to, amount);
        }
    }

    /* Modifier shortcuts */

    modifier asPerson(address person) {
        vm.startPrank(person);
        _;
        vm.stopPrank();
    }
}
