// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IConditionalTokens.sol";

contract OracleResolver is Ownable {
    IConditionalTokens public ctf;
    mapping(bytes32 => bool) public resolvedMarkets;

    constructor(address _ctf) Ownable(msg.sender) {
        ctf = IConditionalTokens(_ctf);
    }

    function resolveMarket(bytes32 questionId, uint256 outcome) external onlyOwner {
        require(!resolvedMarkets[questionId], "Market already resolved");
        require(outcome == 0 || outcome == 1, "Invalid outcome");

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = outcome == 1 ? 1 : 0;
        payouts[1] = outcome == 1 ? 0 : 1;

        // Submit outcome to CTF
        ctf.reportPayouts(questionId, payouts);
        resolvedMarkets[questionId] = true;
    }
}
