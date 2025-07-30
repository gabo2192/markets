// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IConditionalTokens} from "./interfaces/IConditionalTokens.sol";
import {ICTFExchange} from "./interfaces/ICTFExchange.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title MarketCreator
 * @notice Creates a prediction market & registers it with the exchange
 */
contract MarketCreator is Ownable, IERC1155Receiver {
    IConditionalTokens public ctf;
    IERC20 public collateral;
    ICTFExchange public exchange;
    mapping(bytes32 => address) public marketOracles;
    mapping(bytes32 => MarketData) public questionIdToMarketData;

    struct MarketData {
        bytes32 conditionId;
        uint256 yesTokenId;
        uint256 noTokenId;
        uint256 initialLiquidity;
    }

    constructor(address _ctf, address _exchange, address _collateral) Ownable(msg.sender) {
        ctf = IConditionalTokens(_ctf);
        exchange = ICTFExchange(_exchange);
        collateral = IERC20(_collateral);
    }

    function createMarket(string memory question, address oracle, uint256 initialLiquidity)
        external
        returns (bytes32 conditionId, uint256 yesTokenId, uint256 noTokenId)
    {
        require(oracle != address(0), "Oracle cannot be zero address");
        return _createMarket(question, oracle, initialLiquidity);
    }

    function createMultipleMarkets(string[] calldata questions, address oracle)
        external
        returns (bytes32[] memory conditionIds, uint256[] memory yesTokenIds, uint256[] memory noTokenIds)
    {
        require(oracle != address(0), "Oracle cannot be zero address");
        uint256 length = questions.length;

        conditionIds = new bytes32[](length);
        yesTokenIds = new uint256[](length);
        noTokenIds = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            (bytes32 conditionId, uint256 yesTokenId, uint256 noTokenId) = _createMarket(questions[i], oracle, 0);
            conditionIds[i] = conditionId;
            yesTokenIds[i] = yesTokenId;
            noTokenIds[i] = noTokenId;
        }

        return (conditionIds, yesTokenIds, noTokenIds);
    }

    function _createMarket(string memory question, address oracle, uint256 initialLiquidity)
        internal
        returns (bytes32 conditionId, uint256 yesTokenId, uint256 noTokenId)
    {
        bytes32 questionId = keccak256(abi.encodePacked(question));

        ctf.prepareCondition(oracle, questionId, 2);
        conditionId = ctf.getConditionId(oracle, questionId, 2);
        marketOracles[conditionId] = oracle;

        yesTokenId = ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), conditionId, 1));
        noTokenId = ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), conditionId, 2));

        MarketData memory marketData = MarketData({
            conditionId: conditionId,
            yesTokenId: yesTokenId,
            noTokenId: noTokenId,
            initialLiquidity: initialLiquidity
        });

        questionIdToMarketData[questionId] = marketData;

        exchange.registerToken(yesTokenId, noTokenId, conditionId);

        emit MarketCreated(questionId);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    event MarketCreated(bytes32 questionId);
}
