// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IConditionalTokens} from "../../src/interfaces/IConditionalTokens.sol";

/**
 * @title MockConditionalTokens
 * @notice Mock implementation of the Gnosis Conditional Tokens Framework
 * that matches the updated interface with IERC20 parameters
 */
contract MockConditionalTokens is ERC1155("https://mock.conditional-tokens.io/{id}.json"), IConditionalTokens {
    // Events to match the real CTF
    event ConditionPreparation(
        bytes32 indexed conditionId, address indexed oracle, bytes32 indexed questionId, uint256 outcomeSlotCount
    );

    event ConditionResolution(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint256 outcomeSlotCount,
        uint256[] payoutNumerators
    );

    event PositionSplit(
        address indexed stakeholder,
        address collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint256[] partition,
        uint256 amount
    );

    event PositionsMerge(
        address indexed stakeholder,
        address collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint256[] partition,
        uint256 amount
    );

    event PayoutRedemption(
        address indexed redeemer,
        address indexed collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 conditionId,
        uint256[] indexSets,
        uint256 payout
    );

    // State variables
    struct Condition {
        address oracle;
        bytes32 questionId;
        uint256 outcomeSlotCount;
        uint256[] payoutNumerators;
        uint256 payoutDenominator;
        bool isResolved;
    }

    mapping(bytes32 => Condition) public conditions;

    // ====== Implementation of IConditionalTokens ======

    function payoutNumerators(bytes32 conditionId, uint256 index) external view override returns (uint256) {
        require(index < conditions[conditionId].payoutNumerators.length, "Invalid index");
        return conditions[conditionId].payoutNumerators[index];
    }

    function payoutDenominator(bytes32 conditionId) external view override returns (uint256) {
        return conditions[conditionId].payoutDenominator;
    }

    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external override {
        require(outcomeSlotCount > 1, "Invalid outcome slot count");

        bytes32 conditionId = getConditionId(oracle, questionId, outcomeSlotCount);
        require(conditions[conditionId].oracle == address(0), "Condition already prepared");

        conditions[conditionId] = Condition({
            oracle: oracle,
            questionId: questionId,
            outcomeSlotCount: outcomeSlotCount,
            payoutNumerators: new uint256[](0),
            payoutDenominator: 0,
            isResolved: false
        });

        emit ConditionPreparation(conditionId, oracle, questionId, outcomeSlotCount);
    }

    function reportPayouts(bytes32 conditionId, uint256[] calldata payouts) external {
        Condition storage condition = conditions[conditionId];

        // Ensure the condition actually exists
        require(condition.oracle != address(0), "Condition not found");
        // Ensure only that condition’s oracle can resolve
        require(condition.oracle == msg.sender, "Not condition's oracle");
        // Ensure not already resolved
        require(!condition.isResolved, "Condition already resolved");
        // Validate the length
        require(payouts.length == condition.outcomeSlotCount, "Invalid payouts length");

        // Sum up the payout
        uint256 totalPayouts = 0;
        for (uint256 i = 0; i < payouts.length; i++) {
            totalPayouts += payouts[i];
        }
        require(totalPayouts > 0, "Payouts must sum to > 0");

        // Store them
        condition.payoutNumerators = payouts;
        condition.payoutDenominator = totalPayouts;
        condition.isResolved = true;

        emit ConditionResolution(
            conditionId, condition.oracle, condition.questionId, condition.outcomeSlotCount, payouts
        );
    }

    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external override {
        require(conditions[conditionId].oracle != address(0), "Condition not prepared");
        require(partition.length > 0, "Partition cannot be empty");

        // If coming from collateral, pull tokens from user
        if (parentCollectionId == bytes32(0)) {
            require(collateralToken.transferFrom(msg.sender, address(this), amount), "Collateral transfer failed");
        } else {
            // Burn parent position tokens
            uint256 parentPositionId = getPositionId(collateralToken, parentCollectionId);
            _burn(msg.sender, parentPositionId, amount);
        }

        // Mint outcome tokens
        for (uint256 i = 0; i < partition.length; i++) {
            bytes32 collectionId = getCollectionId(parentCollectionId, conditionId, partition[i]);
            uint256 positionId = getPositionId(collateralToken, collectionId);
            _mint(msg.sender, positionId, amount, "");
        }

        emit PositionSplit(msg.sender, address(collateralToken), parentCollectionId, conditionId, partition, amount);
    }

    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external override {
        require(conditions[conditionId].oracle != address(0), "Condition not prepared");
        require(partition.length > 0, "Partition cannot be empty");

        // Burn outcome tokens
        for (uint256 i = 0; i < partition.length; i++) {
            bytes32 collectionId = getCollectionId(parentCollectionId, conditionId, partition[i]);
            uint256 positionId = getPositionId(collateralToken, collectionId);
            _burn(msg.sender, positionId, amount);
        }

        // Mint parent tokens or return collateral
        if (parentCollectionId == bytes32(0)) {
            require(collateralToken.transfer(msg.sender, amount), "Collateral transfer failed");
        } else {
            uint256 parentPositionId = getPositionId(collateralToken, parentCollectionId);
            _mint(msg.sender, parentPositionId, amount, "");
        }

        emit PositionsMerge(msg.sender, address(collateralToken), parentCollectionId, conditionId, partition, amount);
    }

    function redeemPositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external override {
        Condition storage condition = conditions[conditionId];
        require(condition.isResolved, "Condition not resolved yet");
        require(indexSets.length > 0, "IndexSets cannot be empty");

        uint256 totalPayout = 0;

        // Calculate payout for each outcome token held
        for (uint256 i = 0; i < indexSets.length; i++) {
            uint256 indexSet = indexSets[i];
            require(indexSet > 0, "Invalid outcome index set");

            bytes32 collectionId = getCollectionId(parentCollectionId, conditionId, indexSet);
            uint256 positionId = getPositionId(collateralToken, collectionId);

            // Get the user's balance of this outcome token
            uint256 balance = balanceOf(msg.sender, positionId);
            if (balance == 0) continue;

            // Calculate payouts for this indexSet based on condition resolution
            uint256 payoutForIndexSet = 0;
            for (uint256 j = 0; j < condition.outcomeSlotCount; j++) {
                if ((indexSet & (1 << j)) != 0) {
                    payoutForIndexSet += condition.payoutNumerators[j];
                }
            }

            // Calculate the proportional payout
            uint256 payoutAmount = balance * payoutForIndexSet / condition.payoutDenominator;
            totalPayout += payoutAmount;

            // Burn the position tokens
            _burn(msg.sender, positionId, balance);
        }

        // Transfer payout to the redeemer
        if (totalPayout > 0) {
            require(collateralToken.transfer(msg.sender, totalPayout), "Collateral transfer failed");
        }

        emit PayoutRedemption(
            msg.sender, address(collateralToken), parentCollectionId, conditionId, indexSets, totalPayout
        );
    }

    function getOutcomeSlotCount(bytes32 conditionId) external view override returns (uint256) {
        return conditions[conditionId].outcomeSlotCount;
    }

    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        public
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
    }

    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet)
        public
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(parentCollectionId, conditionId, indexSet));
    }

    function getPositionId(IERC20 collateralToken, bytes32 collectionId) public pure override returns (uint256) {
        return uint256(keccak256(abi.encodePacked(address(collateralToken), collectionId)));
    }

    // ====== Helper methods for testing ======

    function conditionPrepared(bytes32 conditionId) external view returns (bool) {
        return conditions[conditionId].oracle != address(0);
    }

    function isMarketResolved(bytes32 conditionId) external view returns (bool) {
        return conditions[conditionId].isResolved;
    }
}
