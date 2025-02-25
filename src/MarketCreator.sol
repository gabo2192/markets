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
        require(initialLiquidity > 0, "Initial liquidity must be greater than zero");

        bytes32 questionId = keccak256(abi.encodePacked(question));
        ctf.prepareCondition(oracle, questionId, 2);
        conditionId = ctf.getConditionId(oracle, questionId, 2);
        marketOracles[conditionId] = oracle;

        // Lock collateral
        collateral.transferFrom(msg.sender, address(this), initialLiquidity);
        collateral.approve(address(ctf), initialLiquidity);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1; // YES token
        partition[1] = 2; // NO token

        // Mint YES/NO tokens (held in this contract)
        ctf.splitPosition((collateral), bytes32(0), conditionId, partition, initialLiquidity);

        yesTokenId = ctf.getPositionId((collateral), ctf.getCollectionId(bytes32(0), conditionId, 1));
        noTokenId = ctf.getPositionId((collateral), ctf.getCollectionId(bytes32(0), conditionId, 2));

        // Transfer YES/NO tokens to the user (this line is added)
        IERC1155(address(ctf)).safeTransferFrom(address(this), msg.sender, yesTokenId, initialLiquidity, "");
        IERC1155(address(ctf)).safeTransferFrom(address(this), msg.sender, noTokenId, initialLiquidity, "");

        // Directly register tokens in `ICTFExchange`
        exchange.registerToken(yesTokenId, noTokenId, conditionId);

        return (conditionId, yesTokenId, noTokenId);
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
}
