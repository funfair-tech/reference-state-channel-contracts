pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

//************************************************************************************************
//** This code is part of a reference implementation of State Channels from FunFair
//** It is for reference purposes only.  It has not been thoroughly audited
//** DO NOT DEPLOY THIS to mainnet
//************************************************************************************************

//************************************************************************************************
//** "Interface" to a contract that implements game rules

contract IGame {
    function getPackedInitialGameState() public view returns (bytes memory packedInitialGameState);

    function validateStartRound(bytes memory packedGameState, bytes memory packedGameAction) public view returns (bool isValid, uint256 maxP0Loss, uint256 maxP1Loss);
    function validateContinueRound(bytes memory packedGameState, bytes memory packedGameAction) public view returns (bool isValid);

    function startRound(bytes32 rngSeed, bytes memory packedGameState, bytes memory packedGameAction) public view returns (int256 winLoss, bool isEndOfRound, bytes memory packedNewGameState);
    function continueRound(bytes32 rngSeed, bytes memory packedGameState, bytes memory packedGameAction) public view returns (int256 winLoss, bool isEndOfRound, bytes memory packedNewGameState);

    //************************************************************************************************
    function isSane(uint256 value) internal pure returns (bool sane) {
        return (value < 0x000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }
}