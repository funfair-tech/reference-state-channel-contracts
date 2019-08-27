pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

//************************************************************************************************
//** This code is part of a reference implementation of State Channels from FunFair
//** It is for reference purposes only.  It has not been thoroughly audited
//** DO NOT DEPLOY THIS to mainnet
//************************************************************************************************

import "./IStateMachine.sol";
import "./IGame.sol";

//************************************************************************************************
//** Fate Machine - a state machine incorporating FunFair's RNG and general state progression

contract FateMachine is IStateMachine {

	//************************************************************************************************
	//** Data Structures

    struct RoundData {
        uint256 status;
        uint256 initialStake;
        uint256 totalStaked;
        uint256 winLossInLastAction;
        uint256 runningWinLoss;
    }

    struct AdditionalData {
        uint256 numRoundsPlayed;
        uint256 totalStaked;

        RoundData roundData;
    }

    struct FateMachineState {
        address gameContract;
        address P1SigningAddress;

        bytes32[2] previousSeeds;
        bool isFinalisable;
        bytes packedGameState;

        bool hasPendingP0Action;
        bytes packedP0Action;

        AdditionalData additionalData;
    }

    struct FateMachineP0Action {
        bytes32 seed;
        bytes packedGameAction;
        Signature packedGameActionCoSignature;
    }

    struct FateMachineP1Action {
        bytes32 seed;
    }

    struct FateMachineInitialisationData {
        address gameContract;
        address P1SigningAddress;
        bytes32[2] seeds;
    }

    //************************************************************************************************
    //** Persistent storage
    address platformFeesAddress;

    //************************************************************************************************
    //** Set the platform fees address;
    function setPlatformFeesAddress(address a) public onlyOwner {
        platformFeesAddress = a;
    }

    //************************************************************************************************
    //** Create the initial state
    function getInitialPackedStateMachineState(bytes memory packedStateMachineInitialisationData) public view returns (bytes memory packedStateMachineState) {
        // Decode data
        FateMachineInitialisationData memory initialisationData = abi.decode(packedStateMachineInitialisationData, (FateMachineInitialisationData));

        FateMachineState memory state;

        state.gameContract = initialisationData.gameContract;
        state.P1SigningAddress = initialisationData.P1SigningAddress;

        state.previousSeeds[0] = initialisationData.seeds[0];
        state.previousSeeds[1] = initialisationData.seeds[1];
        state.isFinalisable = true;
        state.hasPendingP0Action = false;

        state.packedGameState = IGame(state.gameContract).getPackedInitialGameState();

        return abi.encode(state);
    }

    //************************************************************************************************
    //** validate Participant #0's proposed action
    function validateP0Action(FateMachineState memory state, bytes memory packedP0ActionData, uint256[2] memory balances) internal view returns (FFR memory) {
        // Decode data
        FateMachineP0Action memory action = abi.decode(packedP0ActionData, (FateMachineP0Action));
        IGame game = IGame(state.gameContract);

        // Validate Seed Progression
        if (keccak256(abi.encodePacked(action.seed)) != state.previousSeeds[0]) {
            return FFR(false, "Participant #0 seed invalid");
        }

        if (state.isFinalisable) {
            // at the start of a round

            // has the initial action been agreed by participant #1?
            bytes32 packedGameActionHash = keccak256(action.packedGameAction);
            if (!validateSignature(packedGameActionHash, action.packedGameActionCoSignature, state.P1SigningAddress)) {
                return FFR(false, "Start Round action not co-signed");
            }

            // validate the action against the game contract
            bool isValid;
            uint256 maxP0Loss;
            uint256 maxP1Loss;

            (isValid, maxP0Loss, maxP1Loss) = game.validateStartRound(state.packedGameState, action.packedGameAction);

            if (!isValid) {
                return FFR(false, "Action not valid for Start Round");
            }

            if (maxP0Loss >= balances[0]) {
                return FFR(false, "Participant #0 has insuffcient funds");
            }

            if (maxP1Loss >= balances[1]) {
                return FFR(false, "Participant #1 has insuffcient funds");
            }
        } else {
            // mid round
            if (!game.validateContinueRound(state.packedGameState, action.packedGameAction)) {
                return FFR(false, "Action not valid for Continue Round");
            }
        }

        return FFR(true, "");
    }

    //************************************************************************************************
    //** validate Participant #1's proposed action
    function validateP1Action(FateMachineState memory state, bytes memory packedP1ActionData) internal pure returns (FFR memory) {
        // Decode data
        FateMachineP1Action memory action = abi.decode(packedP1ActionData, (FateMachineP1Action));

        // Validate Seed Progression
        if (keccak256(abi.encodePacked(action.seed)) != state.previousSeeds[1]) {
            return FFR(false, "Participant #1 seed invalid");
        }

        return FFR(true, "");
    }

    //************************************************************************************************
    //** validate proposed action
    function validateAction(bytes memory packedStateMachineState, bytes memory packedActionData, uint256 participant, uint256[2] memory balances) public view returns (FFR memory) {
        FateMachineState memory state = abi.decode(packedStateMachineState, (FateMachineState));

        if (participant == 0) {
            if (state.hasPendingP0Action) {
                return FFR(false, "Not Participant #0's turn to act");
            } else {
                return validateP0Action(state, packedActionData, balances);
            }
        } else if (participant == 1) {
            if (!state.hasPendingP0Action) {
                return FFR(false, "Not Participant #1's turn to act");
            } else {
                return validateP1Action(state, packedActionData);
            }
        } else {
            return FFR(false, "Invalid Participant Index");
        }
    }


    //************************************************************************************************
    //** advance the state - note that this function must never throw - and assumes that validation of the inputs has already taken place
    function advanceState(bytes memory packedStateMachineState, bytes memory packedActionData, uint256 participant, uint256[2] memory balances) public view returns (FFR memory isValid, bytes memory packedNewCustomState, int256 balanceChange) {
        // Validate the action
        isValid = validateAction(packedStateMachineState, packedActionData, participant, balances);

        // was it valid?
        if (!isValid.b) {
            return (isValid, packedNewCustomState, balanceChange);
        }

        // Decode data
        FateMachineState memory state = abi.decode(packedStateMachineState, (FateMachineState));

        FateMachineState memory newState;
        int256 winLoss;

        if (!state.hasPendingP0Action) {
            // simply store the action for use after participant 1 has acted

            // copy over the old state - welcome for better suggestions here!
            newState = abi.decode(abi.encode(state), (FateMachineState));

            newState.hasPendingP0Action = true;
            newState.packedP0Action = packedActionData;
            newState.isFinalisable = false;

            winLoss = 0; // explicit for clarity
        } else {
            // Advance the state using the game contract

            // Decode data
            FateMachineP0Action memory actionP0 = abi.decode(state.packedP0Action, (FateMachineP0Action));
            FateMachineP1Action memory actionP1 = abi.decode(packedActionData, (FateMachineP1Action));
            IGame game = IGame(state.gameContract);

            // create RNG seed
            bytes32 rngSeed = keccak256(abi.encodePacked(actionP0.seed, actionP1.seed));

            // use the game contract to advance the game state
            bool isEndOfRound;
            bytes memory packedNewGameState;

            if (state.isFinalisable) {
                (winLoss, isEndOfRound, packedNewGameState) = game.startRound(rngSeed, state.packedGameState, actionP0.packedGameAction);
            } else {
                (winLoss, isEndOfRound, packedNewGameState) = game.continueRound(rngSeed, state.packedGameState, actionP0.packedGameAction);
            }

            // and generate the new state
            newState.gameContract = state.gameContract;
            newState.previousSeeds[0] = actionP0.seed;
            newState.previousSeeds[1] = actionP1.seed;
            newState.isFinalisable = isEndOfRound;
            newState.packedGameState = packedNewGameState;

            // This is where the AdditionalData structure would be updated
        }

        return(isValid, abi.encode(newState), winLoss);
    }

    //************************************************************************************************
    //** check if the channel can be finalised at this point
    function isStateFinalisable(bytes memory packedStateMachineState) public view returns (bool) {
        FateMachineState memory state = abi.decode(packedStateMachineState, (FateMachineState));

        return state.isFinalisable;
    }

    //************************************************************************************************
    //** Calculate the payouts of the state if it were closed at this point, taking into account any penalites
    function getPayouts(uint256[2] memory balances, bytes memory /*packedStateMachineState*/, uint256 penalties, address[2] memory participantAddresses, uint256[2] memory initialBalances) public view returns (uint256[] memory payouts, address[] memory payoutAddresses) {
        payouts = new uint256[](3);
        payoutAddresses = new address[](3);

        // Safety - store the total balances;
        uint256 totalBalance = balances[0] + balances[1];

        // set the initial payouts and addresses
        payouts[0] = balances[0];
        payouts[1] = balances[1];
        payoutAddresses[0] = participantAddresses[0];
        payoutAddresses[1] = participantAddresses[1];

        // apply penalties
        if (penalties == PENALISE_P0) {
            // in this case, penalise the participant 1% of their initial balance
            uint256 penalty = initialBalances[0] / 100;

            if (penalty > payouts[0]) {
                penalty = payouts[0];  // if they cant afford it, take what's left
            }

            payouts[0] -= penalty;
            payouts[1] += penalty;

        } else if (penalties == PENALISE_P1) {
            // in this case, give all the balance to P0
            payouts[0] += payouts[1];
            payouts[1] = 0;
        }

        // apply platform fees from P1
        if (balances[1] > initialBalances[1]) {
            // only apply platform fees from P1
            uint256 P1Gain = balances[1] - initialBalances[1];
            uint256 fees = P1Gain / 100;  // take 1% of P1Gain

            if (fees > payouts[1]) {
                fees = payouts[1]; // if they can't afford it, take what's left.
            }

            payouts[1] -= fees;
            payouts[2] += fees;

            payoutAddresses[2] = platformFeesAddress;
        }

        // safety - check that nothing crazy went wrong.
        require(payouts[0] + payouts[1] + payouts[2] == totalBalance, "Error in payout calculation");
        require(payouts[0] <= totalBalance, "Error in P0 payout calculation");
        require(payouts[1] <= totalBalance, "Error in P1 payout calculation");
        require(payouts[2] <= totalBalance, "Error in Platform Fees payout calculation");
    }
}













