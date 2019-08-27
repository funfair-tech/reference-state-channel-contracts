pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

//************************************************************************************************
//** This code is part of a reference implementation of State Channels from FunFair
//** It is for reference purposes only.  It has not been thoroughly audited
//** DO NOT DEPLOY THIS to mainnet
//************************************************************************************************

//************************************************************************************************
//** An example Coin Flip game

//************************************************************************************************
//** Imports
import "../IGame.sol";

//************************************************************************************************
//** CoinFlip
contract CoinFlip is IGame {

    struct State {
        bool lastGameResult;  // true = heads;
    }

    struct Action {
        uint256 stake;
        bool betOnHeads;
    }

    function getPackedInitialGameState() public view returns (bytes memory packedInitialGameState) {
        State memory s;

        return abi.encode(s);
    }

    function validateStartRound(bytes memory /*packedGameState*/, bytes memory packedGameAction) public view returns (bool isValid, uint256 maxP0Loss, uint256 maxP1Loss) {
        Action memory action = abi.decode(packedGameAction, (Action));

        if (!isSane(action.stake)) {
            isValid = false;
        } else {
            isValid = true;
            maxP0Loss = action.stake;
            maxP1Loss = action.stake;
        }
    }

    function validateContinueRound(bytes memory /*packedGameState*/, bytes memory /*packedGameAction*/) public view returns (bool isValid) {
        return false;
    }

    function startRound(bytes32 rngSeed, bytes memory /*packedGameState*/, bytes memory packedGameAction) public view returns (int256 winLoss, bool isEndOfRound, bytes memory packedNewGameState) {
        Action memory action = abi.decode(packedGameAction, (Action));

        // flip the coin
        bool isHeads = (uint256(rngSeed) & 1) == 1;

        // did the player win?
        bool won = isHeads ? action.betOnHeads : (!action.betOnHeads);

        // create the new state
        State memory newState;
        newState.lastGameResult = isHeads;

        // return the result
        winLoss = won ? int256(action.stake) : -int256(action.stake);
        isEndOfRound = true;
        packedNewGameState = abi.encode(newState);
    }

    function continueRound(bytes32 /*rngSeed*/, bytes memory /*packedGameState*/, bytes memory /*packedGameAction*/) public view returns (int256 /*winLoss*/, bool /*isEndOfRound*/, bytes memory /*packedNewGameState*/) {
        // this can never be called
    }
}
