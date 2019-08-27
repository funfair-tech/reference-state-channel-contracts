pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

//************************************************************************************************
//** This code is part of a reference implementation of State Channels from FunFair
//** It is for reference purposes only.  It has not been thoroughly audited
//** DO NOT DEPLOY THIS to mainnet
//************************************************************************************************

import "./StateChannel.sol";

//************************************************************************************************
//** Disputable State Channel

contract DisputableStateChannel is StateChannel {

	//************************************************************************************************
	//** Indices

    // Additional State Channel Close Reasons
    uint256 constant CLOSE_CHANNEL_RESOLUTION_NO_DISPUTE = 1;
    uint256 constant CLOSE_CHANNEL_P0_TIMED_OUT = 2;
    uint256 constant CLOSE_CHANNEL_P1_TIMED_OUT = 3;
    uint256 constant CLOSE_CHANNEL_CHALLENGED_WITH_LATER_STATE_P0_PENALTY = 4;
    uint256 constant CLOSE_CHANNEL_CHALLENGED_WITH_LATER_STATE_P1_PENALTY = 5;
    uint256 constant CLOSE_CHANNEL_CHALLENGED_WITH_DIFFERENT_ACTION_P0_PENALTY = 6;
    uint256 constant CLOSE_CHANNEL_CHALLENGED_WITH_DIFFERENT_ACTION_P1_PENALTY = 7;

	//************************************************************************************************
	//** Data Structures

    struct DisputeData {
        // dispute information
        uint256 startTime;
        uint256 initiator;
        bytes32 stateContentsHash;
        bytes32 actionContentsHash;
        uint256 stateNonce;

        uint256 openBlock;
        uint256 resolutionBlock;
    }

    //************************************************************************************************
    //** Persistent storage

    // Dispute Data
    mapping (bytes32 => DisputeData) public disputeData;

    // Timeout Periods - note that this is in storage for ease of development
    uint256[2] timemoutPeriods = [2 hours, 4 hours];

    //************************************************************************************************
    //** Events
    event DisputeInitiatedWithoutAction(bytes32 indexed channelID, address indexed participant0address, address indexed participant1address, State state);
    event DisputeInitiatedWithAction(bytes32 indexed channelID, address indexed participant0address, address indexed participant1address, State state, Action action, State proposedNewState);
    event DisputeResolvedWithAction(bytes32 indexed channelID, address indexed participant0address, address indexed participant1address, Action action, State newState);

	//************************************************************************************************
    function validateTimeout(DisputeData memory dispute) internal view returns (bool) {
	    // has the appropriate amount of time elapsed for a timeout?
        uint256 timeoutPeriod;

        // Different for P0 and P1
        if (dispute.initiator == 0) {
            timeoutPeriod = timemoutPeriods[0];
        } else {
            timeoutPeriod = timemoutPeriods[1];
        }

        return (now > dispute.startTime + timeoutPeriod);
    }

    //************************************************************************************************
    //************************************************************************************************
    //** Dispute Initiation
    //************************************************************************************************
    //************************************************************************************************

    // note that the nonce of a disputed state needs to be strictly greater than that of any previous disputed state
    // (and that the initial state nonce is 1, whilst the initial "highest nonce of a previously disputed state" is 0)

    //************************************************************************************************
    //** Dispute without action

    // This can only happen at a point when the channel is finalizable
    // it's basically a "do you want to carry on or not"?  This can only be called by one of the participants
    // it can be resolved with an action from the other party, or by closing with no dispute
    // if the only participant that can act on this state is the disputer, then this effectively forces the channel to close as you can't resolve your own dispute

    function disputeWithoutAction(bytes memory packedOpenChannelData, State memory state) public {
        //************************************************************************************************
        // Decode data
        StateChannelOpenData memory stateChannelOpenData = abi.decode(packedOpenChannelData, (StateChannelOpenData));
        IStateMachine stateMachine = IStateMachine(stateChannelOpenData.stateMachineAddress);

		//************************************************************************************************
		// Validity Checks

        // Is the Open Channel Data valid?
        require(stateChannelData[stateChannelOpenData.channelID].packedOpenChannelDataHash == keccak256(packedOpenChannelData), "Invalid State Channel Open Data");

        // is the State Channel open and not in dispute
        require(stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_OPEN, "State Channel is not open");

        // validate state against channel
        ffrequire(validateStateContents(state.contents, stateChannelOpenData));

        // does the state machine consider this a valid point to close a channel
        require(stateMachine.isStateFinalisable(state.contents.packedStateMachineState), "State is not finalisable");

        // is the state correctly co-signed?
        bytes32 stateContentsHash = keccak256(abi.encode(state.contents));
        require(validateSignature(stateContentsHash, state.signatures[0], stateChannelOpenData.participants[0].participantAddress, stateChannelOpenData.participants[0].signingAddress), "Participant #0 state signature validation failed");
        require(validateSignature(stateContentsHash, state.signatures[1], stateChannelOpenData.participants[1].participantAddress, stateChannelOpenData.participants[1].signingAddress), "Participant #1 state signature validation failed");

        // was it initiated by one of the participants?
        uint256 initiator;

        if ((msg.sender == stateChannelOpenData.participants[0].participantAddress) || (msg.sender == stateChannelOpenData.participants[0].signingAddress)) {
            initiator = 0;
        } else if ((msg.sender == stateChannelOpenData.participants[1].participantAddress) || (msg.sender == stateChannelOpenData.participants[1].signingAddress)) {
            initiator = 1;
        } else {
            require(false, "Dispute initiated by non-participant");
        }

        // is the state nonce greater than any previous dispute?
        require(state.contents.nonce > disputeData[stateChannelOpenData.channelID].stateNonce, "State Nonce not higher than a previous dispute");

		//************************************************************************************************
		// Open Dispute

        stateChannelData[stateChannelOpenData.channelID].channelStatus = STATE_CHANNEL_STATUS_IN_DISPUTE;

        DisputeData memory dispute;

        dispute.startTime = now;
        dispute.initiator = initiator;
        dispute.stateContentsHash = stateContentsHash;
        dispute.actionContentsHash = 0x0;
        dispute.stateNonce = state.contents.nonce;
        dispute.openBlock = block.number;

        disputeData[stateChannelOpenData.channelID] = dispute;

        // Log
        emit DisputeInitiatedWithoutAction(stateChannelOpenData.channelID, stateChannelOpenData.participants[0].participantAddress, stateChannelOpenData.participants[1].participantAddress, state);
    }

    //************************************************************************************************
    //** Dispute with action

    // if this action doesn't create a finalisable state, the other participant must respond with a new action
    // otherwise they can additionally Resolve - Agree and Close Channel

    function disputeWithAction(bytes memory packedOpenChannelData, State memory state, Action memory action, State memory proposedNewState) public {
        //************************************************************************************************
        // Decode data
        StateChannelOpenData memory stateChannelOpenData = abi.decode(packedOpenChannelData, (StateChannelOpenData));
        IStateMachine stateMachine = IStateMachine(stateChannelOpenData.stateMachineAddress);

		//************************************************************************************************
		// Validity Checks

        // Is the Open Channel Data valid?
        require(stateChannelData[stateChannelOpenData.channelID].packedOpenChannelDataHash == keccak256(packedOpenChannelData), "Invalid State Channel Open Data");

        // is the State Channel open and not in dispute
        require(stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_OPEN, "State Channel is not open");

        // validate state against channel
        ffrequire(validateStateContents(state.contents, stateChannelOpenData));

        // validate action against state and channel
        ffrequire(validateActionContents(action.contents, state.contents, stateChannelOpenData));

        // is the action of the correct type
        require(action.contents.actionType == ACTION_TYPE_ADVANCE_STATE, "Incorrect Action Type");

        // is the state correctly co-signed?
        bytes32 stateContentsHash = keccak256(abi.encode(state.contents));
        require(validateSignature(stateContentsHash, state.signatures[0], stateChannelOpenData.participants[0].participantAddress, stateChannelOpenData.participants[0].signingAddress), "Participant #0 state signature validation failed");
        require(validateSignature(stateContentsHash, state.signatures[1], stateChannelOpenData.participants[1].participantAddress, stateChannelOpenData.participants[1].signingAddress), "Participant #1 state signature validation failed");

        // is the state nonce greater than any previous dispute?
        require(state.contents.nonce > disputeData[stateChannelOpenData.channelID].stateNonce, "State Nonce not higher than a previous dispute");

        // was it initiated by one of the participants?
        uint256 initiator;

        if ((msg.sender == stateChannelOpenData.participants[0].participantAddress) || (msg.sender == stateChannelOpenData.participants[0].signingAddress)) {
            initiator = 0;
        } else if ((msg.sender == stateChannelOpenData.participants[1].participantAddress) || (msg.sender == stateChannelOpenData.participants[1].signingAddress)) {
            initiator = 1;
        } else {
            require(false, "Dispute initiated by non-participant");
        }

        // is the action from the initiator
        require(action.contents.participant == initiator, "Action not from dispute initiator");

        // is the action correctly signed?
        bytes32 actionContentsHash = keccak256(abi.encode(action.contents));
        require(validateSignature(actionContentsHash, action.signature, stateChannelOpenData.participants[action.contents.participant].participantAddress, stateChannelOpenData.participants[action.contents.participant].signingAddress), "Action signature validation failed");

        // is the new state correctly signed?
        bytes32 proposedNewStateContentsHash = keccak256(abi.encode(proposedNewState.contents));
        require(validateSignature(proposedNewStateContentsHash, proposedNewState.signatures[action.contents.participant], stateChannelOpenData.participants[action.contents.participant].participantAddress, stateChannelOpenData.participants[action.contents.participant].signingAddress), "Proposed new state signature validation failed");

        // advance the state using the state machine
        StateContents memory newStateContents;
        FFR memory isValid;

        (isValid, newStateContents) = advanceState(state.contents, action.contents, stateMachine);

        // was the state transition valid?
        ffrequire(isValid);

        // does the state machine agree with the proposed new state?
        require(keccak256(abi.encode()) == proposedNewStateContentsHash, "Proposed State incorrect");

		//************************************************************************************************
		// Open Dispute

        stateChannelData[stateChannelOpenData.channelID].channelStatus = STATE_CHANNEL_STATUS_IN_DISPUTE;

        DisputeData memory dispute;

        dispute.startTime = now;
        dispute.initiator = action.contents.participant;
        dispute.stateContentsHash = proposedNewStateContentsHash;
        dispute.actionContentsHash = actionContentsHash;
        dispute.stateNonce = proposedNewState.contents.nonce;
        dispute.openBlock = block.number;

        disputeData[stateChannelOpenData.channelID] = dispute;

        // Log
        emit DisputeInitiatedWithAction(stateChannelOpenData.channelID, stateChannelOpenData.participants[0].participantAddress, stateChannelOpenData.participants[1].participantAddress, state, action, proposedNewState);
    }

    //************************************************************************************************
    //************************************************************************************************
    //** Dispute Resolution
    //************************************************************************************************
    //************************************************************************************************

    //************************************************************************************************
    //************************************************************************************************
    //** Resolve Dispute - Without Action
    //************************************************************************************************
    //************************************************************************************************

    // Confirm the disputed state, provide a new action and state, and re-open the channel
    // Can only be called by the counterparty

    function resolveDispute_WithAction(bytes memory packedOpenChannelData, State memory state, Action memory action, State memory proposedNewState) public {
      //************************************************************************************************
        // Decode data
        StateChannelOpenData memory stateChannelOpenData = abi.decode(packedOpenChannelData, (StateChannelOpenData));
        IStateMachine stateMachine = IStateMachine(stateChannelOpenData.stateMachineAddress);
        DisputeData memory dispute = disputeData[stateChannelOpenData.channelID];

		//************************************************************************************************
		// Validity Checks

        // Is the Open Channel Data valid?
        require(stateChannelData[stateChannelOpenData.channelID].packedOpenChannelDataHash == keccak256(packedOpenChannelData), "Invalid State Channel Open Data");

        // is the State Channel open and in dispute
        require(stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_IN_DISPUTE, "State Channel is not in dispute");

        // is the state the one that's in dispute?
        require(keccak256(abi.encode(state.contents)) == dispute.stateContentsHash, "Incorrect State");

        // validate the action against state and channel
        ffrequire(validateActionContents(action.contents, state.contents, stateChannelOpenData));

        // is the action of the correct type
        require(action.contents.actionType == ACTION_TYPE_ADVANCE_STATE, "Incorrect Action Type");

        // is the resolution being made by the counterparty
        require(action.contents.participant != dispute.initiator, "Action not from the counterparty");

        // is the action correctly co-signed?
        require(validateSignature(keccak256(abi.encode(action.contents)), action.signature, stateChannelOpenData.participants[action.contents.participant].participantAddress, stateChannelOpenData.participants[action.contents.participant].signingAddress), "Action signature validation failed");

        // is the new state correctly signed?
        bytes32 proposedNewStateContentsHash = keccak256(abi.encode(proposedNewState.contents));
        require(validateSignature(proposedNewStateContentsHash, proposedNewState.signatures[action.contents.participant], stateChannelOpenData.participants[action.contents.participant].participantAddress, stateChannelOpenData.participants[action.contents.participant].signingAddress), "Proposed new state signature validation failed");

        // advance the state using the state machine
        StateContents memory newStateContents;
        FFR memory isValid;

        (isValid, newStateContents) = advanceState(state.contents, action.contents, stateMachine);

        // was the state transition valid?
        ffrequire(isValid);

        // does the state machine agree with the proposed new state?
        require(keccak256(abi.encode()) == proposedNewStateContentsHash, "Proposed State incorrect");

		//************************************************************************************************
		// Resolution Successful - Re-open the channel
        stateChannelData[stateChannelOpenData.channelID].channelStatus = STATE_CHANNEL_STATUS_OPEN;

        disputeData[stateChannelOpenData.channelID].resolutionBlock = block.number;

        // log
        emit DisputeResolvedWithAction(stateChannelOpenData.channelID, stateChannelOpenData.participants[0].participantAddress, stateChannelOpenData.participants[1].participantAddress, action, proposedNewState);
    }

    //************************************************************************************************
    //** Resolve Disupute - Agree and close channel

    // Accept the state that was proposed in the dispute and close the channel now
    // Requires the state to be finalisable
    // Can only be called with an action from counterparty

    function resolveDispute_AgreeAndCloseChannel(bytes memory packedOpenChannelData, State memory state, Action memory action) public {
        //************************************************************************************************
        // Decode data
        StateChannelOpenData memory stateChannelOpenData = abi.decode(packedOpenChannelData, (StateChannelOpenData));
        IStateMachine stateMachine = IStateMachine(stateChannelOpenData.stateMachineAddress);
        DisputeData memory dispute = disputeData[stateChannelOpenData.channelID];

		//************************************************************************************************
		// Validity Checks

        // Is the Open Channel Data valid?
        require(stateChannelData[stateChannelOpenData.channelID].packedOpenChannelDataHash == keccak256(packedOpenChannelData), "Invalid State Channel Open Data");

        // is the State Channel open and in dispute
        require(stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_IN_DISPUTE, "State Channel is not in dispute");

        // is the state the one that's in dispute?
        require(keccak256(abi.encode(state.contents)) == dispute.stateContentsHash, "Incorrect State");

        // does the state machine consider this a valid point to close a channel
        require(stateMachine.isStateFinalisable(state.contents.packedStateMachineState), "State is not finalisable");

        // validate action against state and channel
        ffrequire(validateActionContents(action.contents, state.contents, stateChannelOpenData));

        // is the resolution being made by the counterparty
        require(action.contents.participant != dispute.initiator, "Action not from the counterparty");

        // is the action a action?
        require(action.contents.actionType == ACTION_TYPE_CLOSE_CHANNEL, "Incorrect Action Type for Action");

        // is the action correctly signed?
        require(validateSignature(keccak256(abi.encode(action.contents)), action.signature, stateChannelOpenData.participants[action.contents.participant].participantAddress, stateChannelOpenData.participants[action.contents.participant].signingAddress), "Action signature validation failed");

		//************************************************************************************************
		// Resolution Successful - Close the Channel
        DistributeFundsAndCloseChannel(packedOpenChannelData, state, PENALISE_NONE, CLOSE_CHANNEL_ORDERLY);
    }

    //************************************************************************************************
    //** Resolve Disupute - Timeout

    // The counterparty has not successfully resolved the dispute - so they are penalised and the channel is closed
    // anyone can call this function

    function resolveDispute_Timeout(bytes memory packedOpenChannelData, State memory state) public {
        //************************************************************************************************
        // Decode data
        StateChannelOpenData memory stateChannelOpenData = abi.decode(packedOpenChannelData, (StateChannelOpenData));
        DisputeData memory dispute = disputeData[stateChannelOpenData.channelID];

		//************************************************************************************************
		// Validity Checks

        // Is the Open Channel Data valid?
        require(stateChannelData[stateChannelOpenData.channelID].packedOpenChannelDataHash == keccak256(packedOpenChannelData), "Invalid State Channel Open Data");

        // is the State Channel open and in dispute
        require(stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_IN_DISPUTE, "State Channel is not in dispute");

        // is the state the one that's in dispute?
        require(keccak256(abi.encode(state.contents)) == dispute.stateContentsHash, "Incorrect State");

		// has the correct amount of time elapsed?
        require(validateTimeout(dispute), "Too early to claim timeout");

		//************************************************************************************************
		// Resolution Successful - Close the Channel
        DistributeFundsAndCloseChannel(packedOpenChannelData, state, (dispute.initiator == 0) ? PENALISE_P1 : PENALISE_P0, (dispute.initiator == 0) ? CLOSE_CHANNEL_P1_TIMED_OUT : CLOSE_CHANNEL_P0_TIMED_OUT);
    }

    //************************************************************************************************
    //** Resolve Disupute - Challenge with later state

    // If the dispute initiator has signed a later state than the one they are disputing, this is a protocol violation, and they are penalised
    // anyone can call this function

    function resolveDispute_ChallengeWithLaterState(bytes memory packedOpenChannelData, State memory state) public {
        //************************************************************************************************
        // Decode data
        StateChannelOpenData memory stateChannelOpenData = abi.decode(packedOpenChannelData, (StateChannelOpenData));
        DisputeData memory dispute = disputeData[stateChannelOpenData.channelID];

		//************************************************************************************************
		// Validity Checks

        // Is the Open Channel Data valid?
        require(stateChannelData[stateChannelOpenData.channelID].packedOpenChannelDataHash == keccak256(packedOpenChannelData), "Invalid State Channel Open Data");

        // is the State Channel open and in dispute
        require(stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_IN_DISPUTE, "State Channel is not in dispute");

        // validate state against channel
        ffrequire(validateStateContents(state.contents, stateChannelOpenData));

        // is this a later state?
        require(state.contents.nonce > dispute.stateNonce, "Nonce is not later than dispute");

        // has this state been co-signed
        bytes32 stateContentsHash = keccak256(abi.encode(state.contents));
        require(validateSignature(stateContentsHash, state.signatures[0], stateChannelOpenData.participants[0].participantAddress, stateChannelOpenData.participants[0].signingAddress), "Participant #0 state signature validation failed");
        require(validateSignature(stateContentsHash, state.signatures[1], stateChannelOpenData.participants[1].participantAddress, stateChannelOpenData.participants[1].signingAddress), "Participant #1 state signature validation failed");

		//************************************************************************************************
		// Resolution Successful - Close the Channel
        DistributeFundsAndCloseChannel(packedOpenChannelData, state, (dispute.initiator == 0) ? PENALISE_P0 : PENALISE_P1, (dispute.initiator == 0) ? CLOSE_CHANNEL_CHALLENGED_WITH_LATER_STATE_P0_PENALTY : CLOSE_CHANNEL_CHALLENGED_WITH_LATER_STATE_P1_PENALTY);
    }

    //************************************************************************************************
    //** Resolve Disupute - Challenge with different action

    // If the dispute initiator has signed a different action on the state they are disputing, this is a protocol violation, and they are penalised
    // anyone can call this function

    function resolveDispute_ChallengeWithDifferentAction(bytes memory packedOpenChannelData, State memory state, Action memory action) public {
        //************************************************************************************************
        // Decode data
        StateChannelOpenData memory stateChannelOpenData = abi.decode(packedOpenChannelData, (StateChannelOpenData));
        DisputeData memory dispute = disputeData[stateChannelOpenData.channelID];
        IStateMachine stateMachine = IStateMachine(stateChannelOpenData.stateMachineAddress);

		//************************************************************************************************
		// Validity Checks

        // Is the Open Channel Data valid?
        require(stateChannelData[stateChannelOpenData.channelID].packedOpenChannelDataHash == keccak256(packedOpenChannelData), "Invalid State Channel Open Data");

        // is the State Channel open and in dispute
        require(stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_IN_DISPUTE, "State Channel is not in dispute");

        // is the state the one that's in dispute?
        require(keccak256(abi.encode(state.contents)) == dispute.stateContentsHash, "Incorrect State");

        // validate action against state and channel
        ffrequire(validateActionContents(action.contents, state.contents, stateChannelOpenData));

        // is the action of the correct type?
        require(action.contents.actionType == ACTION_TYPE_ADVANCE_STATE, "Incorrect Action Type");

        // is the action participant the dispute initiator?
        require(action.contents.participant != dispute.initiator, "Action not from the initiator");

        // is the action correctly co-signed?
        require(validateSignature(keccak256(abi.encode(action.contents)), action.signature, stateChannelOpenData.participants[action.contents.participant].participantAddress, stateChannelOpenData.participants[action.contents.participant].signingAddress), "Action signature validation failed");

        // advance the state using the state machine in order to check that the action is valid
        StateContents memory newStateContents;
        FFR memory isValid;

        (isValid, newStateContents) = advanceState(state.contents, action.contents, stateMachine);

        // was the state transition valid?
        ffrequire(isValid);

        // is the action different to the one used to open the dispute
        require(keccak256(abi.encode(action.contents)) != dispute.actionContentsHash, "Action not different");

		//************************************************************************************************
		// Resolution Successful - Close the Channel
        DistributeFundsAndCloseChannel(packedOpenChannelData, state, (dispute.initiator == 0) ? PENALISE_P0 : PENALISE_P1, (dispute.initiator == 0) ? CLOSE_CHANNEL_CHALLENGED_WITH_DIFFERENT_ACTION_P0_PENALTY : CLOSE_CHANNEL_CHALLENGED_WITH_DIFFERENT_ACTION_P1_PENALTY);
    }
}

