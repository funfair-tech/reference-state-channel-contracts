pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

//************************************************************************************************
//** This code is part of a reference implementation of State Channels from FunFair
//** It is for reference purposes only.  It has not been thoroughly audited
//** DO NOT DEPLOY THIS to mainnet
//************************************************************************************************


//************************************************************************************************
//** An example Hi-Lo game with multiple stages

//************************************************************************************************
//** Imports
import "../IGame.sol";

//************************************************************************************************
//** CoinFlip
contract CoinFlip is IGame {
    uint256 constant MAX_CARDS = 8;
    uint256 constant CARDS_IN_DECK = 52;

    struct State {
        uint256 initialStake;

        uint256 numCardsDealt;
        uint256[8 /* == MAX CARDS */] cardsDealt;

        uint256 numCardsPlayed;
    }

    struct StartRoundAction {
        uint256 stake;
    }

    struct ContinueRoundAction {
        bool play;
        bool betHi;
    }

    function dealCard(bytes32 rngSeed) internal pure returns (uint256 card) {
        // assumes an infinite deck
        return uint256(rngSeed) % 52;
    }

    function getPackedInitialGameState() public view returns (bytes memory packedInitialGameState) {
        State memory s;

        return abi.encode(s);
    }

    function validateStartRound(bytes memory /*packedGameState*/, bytes memory packedGameAction) public view returns (bool isValid, uint256 maxP0Loss, uint256 maxP1Loss) {
        StartRoundAction memory action = abi.decode(packedGameAction, (StartRoundAction));

        if (!isSane(action.stake)) {
            // prevent possible overflow
            isValid = false;
        } else {
            isValid = true;
            maxP0Loss = action.stake;
            maxP1Loss = action.stake ** MAX_CARDS;
        }
    }

    function validateContinueRound(bytes memory packedGameState, bytes memory /*packedGameAction*/) public view returns (bool isValid) {
        State memory state = abi.decode(packedGameState, (State));

        bool valid = true;

        if (state.numCardsPlayed == 0) {
            // you must play the first card
            valid = false;
        }

        if (state.numCardsPlayed >= MAX_CARDS) {
            // invalid state to try and play
            valid = false;
        }

        return valid;
    }

    function startRound(bytes32 rngSeed, bytes memory /*packedGameState*/, bytes memory packedGameAction) public view returns (int256 winLoss, bool isEndOfRound, bytes memory packedNewGameState) {
        StartRoundAction memory action = abi.decode(packedGameAction, (StartRoundAction));

        // prepare a new state - there is nothing to carry over from the old one
        State memory newState;

        // store the initial stake
        newState.initialStake = action.stake;

        // deal the first card
        newState.cardsDealt[0] = dealCard(rngSeed);
        newState.numCardsDealt = 1;

        // return the result
        winLoss = -int(action.stake);  // take the stake out of the player's balance
        isEndOfRound = false;
        packedNewGameState = abi.encode(newState);
    }

    function continueRound(bytes32 rngSeed, bytes memory packedGameState, bytes memory packedGameAction) public view returns (int256 winLoss, bool isEndOfRound, bytes memory packedNewGameState) {
        State memory state = abi.decode(packedGameState, (State));
        ContinueRoundAction memory action = abi.decode(packedGameAction, (ContinueRoundAction));

        // prepare a new state
        State memory newState;

        // copy over the old data
        newState = abi.decode(abi.encode(state), (State));

        // does the player want to play another card?
        if (action.play) {
            // yes!

            // deal the next card
            uint256 nextCard = dealCard(rngSeed);

            // get the rank of the card - using an encoding where 2c = 0, 2d = 1, 2h = 2, 2s = 3, 3c = 4 ..... As = 51
            uint256 nextRank = nextCard >> 2;

            // get the rank of the previous card
            uint256 previousRank = newState.cardsDealt[state.numCardsDealt - 1] >> 2;

            // store the next card in the new state
            newState.cardsDealt[state.numCardsDealt] = nextCard;
            newState.numCardsDealt ++;

            // did they win, lose or draw?
            if (previousRank == nextRank) {
                // this is a draw - so no payout for this card, but you keep your winnings so far
                winLoss = int256(state.initialStake ** (newState.numCardsDealt - 2));
                isEndOfRound = true;
            } else if (action.betHi ? (nextRank > previousRank) : (nextRank < previousRank)) {
                // player wins!

                // have they played the maximum number of cards?
                if (newState.numCardsDealt == MAX_CARDS) {
                    // yes - congratulations, they've hit the maximum win - pay them and finish the round
                    winLoss = int256(state.initialStake ** (newState.numCardsDealt - 1));
                    isEndOfRound == true;
                } else {
                    // just continue with the next round
                    winLoss = 0;
                    isEndOfRound = false;
                }
            } else {
                // house wins!
                winLoss = 0;  // the initial stake has already been taken
                isEndOfRound = true;
            }
        } else {
            // no - so claim their winnings and finish the round
            winLoss = int256(state.initialStake ** (state.numCardsPlayed - 1));
            isEndOfRound = true;
        }

        packedNewGameState = abi.encode(newState);
    }
}
