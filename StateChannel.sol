pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

//************************************************************************************************
//** This code is part of a reference implementation of State Channels from FunFair
//** It is for reference purposes only.  It has not been thoroughly audited
//** DO NOT DEPLOY THIS to mainnet
//************************************************************************************************

import "./Common.sol";
import "./IMultiSigTransferReceiver.sol";
import "./IFUNTokenControllerV2.sol";
import "./IStateMachine.sol";
import "./IToken.sol";

//************************************************************************************************
//** State Channel

contract StateChannel is IMultiSigTransferReceiver, Common {

    //************************************************************************************************
    //** Indices

    // State Channel States
    uint256 constant STATE_CHANNEL_STATUS_UNUSED = 0;
    uint256 constant STATE_CHANNEL_STATUS_OPEN = 1;
    uint256 constant STATE_CHANNEL_STATUS_CLOSED = 2;
    uint256 constant STATE_CHANNEL_STATUS_IN_DISPUTE = 3;

    // State Channel Close Reasons
    uint256 constant CLOSE_CHANNEL_ORDERLY = 0;

    //************************************************************************************************
    //** Data Structures

    struct StateContents {
        bytes32 channelID;
        address channelAddress;
        uint256 nonce;
        uint256[2] balances;
        bytes packedStateMachineState;
    }

    struct State {
        StateContents contents;
        Signature[2] signatures;
    }

    uint256 constant ACTION_TYPE_ADVANCE_STATE = 0x01;
    uint256 constant ACTION_TYPE_CLOSE_CHANNEL = 0xff;

    struct ActionContents {
        bytes32 channelID;
        address channelAddress;
        uint256 stateNonce;
        uint256 participant;
        uint256 actionType;
        bytes packedActionData;
    }

    struct Action {
        ActionContents contents;
        Signature signature;
    }

    struct StateChannelParticipant {
        address participantAddress;
        address delegateAddress;
        address signingAddress;

        uint256 amount;
    }

    struct StateChannelOpenData {
        bytes32 channelID;
        address channelAddress;

        StateChannelParticipant[2] participants;
        address stateMachineAddress;
        uint256 timeStamp;
        bytes32 initialStateHash;
        Signature[2] initialStateSignatures;
        bytes packedStateMachineInitialisationData;
    }

    struct StateChannelData {
        // State Channel Status - will default to STATE_CHANNEL_STATUS_UNUSED for unused entries
        uint256 channelStatus;

        // hash of the open channel input data
        bytes32 packedOpenChannelDataHash;

        // value of the channel - note this is for safety until full contract audits are complete.  It *should* be unneccessary
        uint256 channelValue;
    }

    //************************************************************************************************
    //** Persistent storage

    // State Channel Data
    mapping (bytes32 => StateChannelData) public stateChannelData;

    //************************************************************************************************
    //** Events
    event StateChannelOpened(bytes32 indexed channelID, address indexed participant0address, address indexed participant1address, bytes input);
    event StateChannelClosed(bytes32 indexed channelID, address indexed participant0address, address indexed participant1address, bytes packedOpenChannelData, State finalState, uint256[] finalBalances, address[] finalAddresses, uint256 reasonforClose, uint256 closingTimestamp);

    //************************************************************************************************
    //** Validation Checks
    function validateStateContents(StateContents memory stateContents, StateChannelOpenData memory openChannelData) internal view returns (FFR memory) {
        // does the state refer to this contract?
        if (stateContents.channelAddress != address(this)) {
            return FFR(false, "Incorrect State Channel Address");
        }

        // does the state refer to this channel?
        if (stateContents.channelID != openChannelData.channelID) {
            return FFR(false, "Incorrect State Channel ID");
        }

        // do the balances add up?
        if (stateContents.balances[0] + stateContents.balances[1] != stateChannelData[openChannelData.channelID].channelValue) {
            return FFR(false, "Incorrect state balances sum");
        }

        // does the sum of balances overflow?
        if (stateContents.balances[0] + stateContents.balances[1] < stateContents.balances[0]) {
            return FFR(false, "State Balances overflow");
        }

        return FFR(true, "");
    }

    //************************************************************************************************
    function validateActionContents(ActionContents memory actionContents, StateContents memory stateContents, StateChannelOpenData memory openChannelData) internal view returns (FFR memory) {
        // does the action refer to this contract?
        if (actionContents.channelAddress != address(this)) {
            return FFR(false, "Incorrect State Channel Address");
        }
        // does the action refer to this channel?
        if (actionContents.channelID != openChannelData.channelID) {
            return FFR(false, "Incorrect Action Channel ID");
        }

        // does the action have the correct nonce?
        if (actionContents.stateNonce != stateContents.nonce) {
            return FFR(false, "Incorrect Action Nonce");
        }

        // is the participant value in range
        if ((actionContents.participant != 0) && (actionContents.participant != 1)) {
            return FFR(false, "Invalid Action Participant");
        }

        return FFR(true, "");
    }

    //************************************************************************************************
    function getPackedInitialStateContents(address stateMachineAddress, bytes32 channelID, uint256[2] memory amounts, bytes memory packedStateMachineInitialisationData) public view returns (bytes memory packedInitialStateContents) {
        StateContents memory initialState;

        initialState.channelID = channelID;
        initialState.channelAddress = address(this);
        initialState.nonce = 0;
        initialState.balances[0] = amounts[0];
        initialState.balances[1] = amounts[1];
        initialState.packedStateMachineState = IStateMachine(stateMachineAddress).getInitialPackedStateMachineState(packedStateMachineInitialisationData);

        return abi.encode(initialState);
    }

	//************************************************************************************************
    function advanceState(StateContents memory stateContents, ActionContents memory actionContents, IStateMachine stateMachine) public view returns (FFR memory isValid, StateContents memory newStateContents) {
        // advance the state using the state machine
        int256 balanceChange;
        bytes memory packedNewCustomState;

        (isValid, packedNewCustomState, balanceChange) = stateMachine.advanceState(stateContents.packedStateMachineState, actionContents.packedActionData, actionContents.participant, stateContents.balances);

        // was the action valid?
        if (!isValid.b) {
            return (FFR(false, "Invalid Action"), newStateContents);
        }

        // check that the balance change is acceptable
        // this must *never* trigger
        assert((balanceChange >= 0) || (int256(stateContents.balances[0]) > (-balanceChange))); // Does Participant #0 have enough funds
        assert((balanceChange <= 0) || (int256(stateContents.balances[1]) > ( balanceChange))); // Does Participant #1 have enough funds

        newStateContents.channelID = stateContents.channelID;
        newStateContents.channelAddress = stateContents.channelAddress;
        newStateContents.nonce = stateContents.nonce + 1;
        newStateContents.balances[0] = uint256(int256(stateContents.balances[0]) + balanceChange);
        newStateContents.balances[1] = uint256(int256(stateContents.balances[1]) - balanceChange);
        newStateContents.packedStateMachineState = packedNewCustomState;
    }

    //************************************************************************************************
    function DistributeFunds(bytes memory packedOpenChannelData, State memory state, uint256 penalties) internal returns (uint256[] memory finalBalances, address[] memory finalAddresses);
    // This function intentionally has no body and must be implemented by a derived class

    //************************************************************************************************
    function DistributeFundsAndCloseChannel(bytes memory packedOpenChannelData, State memory state, uint256 penalties, uint256 reasonForClose) internal {
        //************************************************************************************************
        // Decode data
        StateChannelOpenData memory stateChannelOpenData = abi.decode(packedOpenChannelData, (StateChannelOpenData));

        // can only call this if the channel is open
        assert((stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_OPEN) || (stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_IN_DISPUTE));

        // close the channel
        stateChannelData[stateChannelOpenData.channelID].channelStatus = STATE_CHANNEL_STATUS_CLOSED;

        // distribute Funds
        uint256[] memory finalBalances;
        address[] memory finalAddresses;

        (finalBalances, finalAddresses) = DistributeFunds(packedOpenChannelData, state, penalties);

        // Extra Safety - check that the channel value is correct
        // require(sum_of_balances == stateChannelData[stateChannelOpenData.channelID].channelValue, "Balances don't match channel value");

        emit StateChannelClosed(
            stateChannelOpenData.channelID, stateChannelOpenData.participants[0].participantAddress, stateChannelOpenData.participants[1].participantAddress, packedOpenChannelData, state, finalBalances, finalAddresses, reasonForClose, now);
    }

    //************************************************************************************************
    //** Open State Channel
    //
    // Assumes that any funds have already been deposited into the contract

    function openStateChannel(bytes memory packedOpenChannelData) internal returns (bool) {
        //************************************************************************************************
        // Decode data
        StateChannelOpenData memory stateChannelOpenData = abi.decode(packedOpenChannelData, (StateChannelOpenData));

        //************************************************************************************************
        // Validity Checks

        // does a State Channel with this ID already exist?
        require(stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_UNUSED, "State Channel is already in use");

        // does the Open Channel data refer to this contract
        require(stateChannelOpenData.channelAddress == address(this), "State Channel Open Data does not refer to this contract");

        // check the timestamp - was this co-signed "recently"
        require(now < stateChannelOpenData.timeStamp + 1 hours, "State Channel open timeout exceeded");

        // get and check the initial state and hash
        bytes memory packedInitialStateContents = getPackedInitialStateContents(stateChannelOpenData.stateMachineAddress, stateChannelOpenData.channelID,
            [stateChannelOpenData.participants[0].amount, stateChannelOpenData.participants[1].amount], stateChannelOpenData.packedStateMachineInitialisationData);

        require(keccak256(packedInitialStateContents) == stateChannelOpenData.initialStateHash, "Initial state failed to verify");

        // validate the initial state signatures
        require(validateSignature(stateChannelOpenData.initialStateHash, stateChannelOpenData.initialStateSignatures[0], stateChannelOpenData.participants[0].participantAddress, stateChannelOpenData.participants[0].signingAddress), "Participant #0 state signature validation failed");
        require(validateSignature(stateChannelOpenData.initialStateHash, stateChannelOpenData.initialStateSignatures[1], stateChannelOpenData.participants[1].participantAddress, stateChannelOpenData.participants[1].signingAddress), "Participant #1 state signature validation failed");

        //************************************************************************************************
        // Store data

        // mark the channel as opened
        stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_OPEN;

        // the hash of the input data
        stateChannelData[stateChannelOpenData.channelID].packedOpenChannelDataHash = keccak256(packedOpenChannelData);

        // the value of the Channel
        stateChannelData[stateChannelOpenData.channelID].channelValue = stateChannelOpenData.participants[0].amount + stateChannelOpenData.participants[1].amount;

        //************************************************************************************************
        // and the channel is opened!
        emit StateChannelOpened(stateChannelOpenData.channelID, stateChannelOpenData.participants[0].participantAddress, stateChannelOpenData.participants[1].participantAddress, packedOpenChannelData);

        return true;
    }

    //************************************************************************************************
    //** Close State Channel - both participants send a signed "Close Channel" action.
    function closeStateChannel(bytes memory packedOpenChannelData, State memory state, Action[2] memory actions) public {
        //************************************************************************************************
        // Decode data
        StateChannelOpenData memory stateChannelOpenData = abi.decode(packedOpenChannelData, (StateChannelOpenData));
        IStateMachine stateMachine = IStateMachine(stateChannelOpenData.stateMachineAddress);

        //************************************************************************************************
        // Validity checks

        // Is the Open Channel Data valid?
        require(stateChannelData[stateChannelOpenData.channelID].packedOpenChannelDataHash == keccak256(packedOpenChannelData), "Invalid State Channel Open Data");

        // is the State Channel open or in dispute (a disputed channel can be closed if both participants agree)
        require((stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_OPEN) || (stateChannelData[stateChannelOpenData.channelID].channelStatus == STATE_CHANNEL_STATUS_IN_DISPUTE), "State Channel is not open or in dispute");

        // validate state against channel
        ffrequire(validateStateContents(state.contents, stateChannelOpenData));

        // validate actions against state and channel
        ffrequire(validateActionContents(actions[0].contents, state.contents, stateChannelOpenData));
        ffrequire(validateActionContents(actions[1].contents, state.contents, stateChannelOpenData));

        // are they both close actions?
        require(actions[0].contents.actionType == ACTION_TYPE_CLOSE_CHANNEL, "Incorrect Action Type for Action #0");
        require(actions[1].contents.actionType == ACTION_TYPE_CLOSE_CHANNEL, "Incorrect Action Type for Action #1");

        // do the actions both have the correct participant
        require(actions[0].contents.participant == 0, "Action 0 not from participant #0");
        require(actions[1].contents.participant == 1, "Action 1 not from participant #1");

        // is the state correctly co-signed?
        bytes32 hash = keccak256(abi.encode(state.contents));
        require(validateSignature(hash, state.signatures[0], stateChannelOpenData.participants[0].participantAddress, stateChannelOpenData.participants[0].signingAddress), "Participant #0 state signature validation failed");
        require(validateSignature(hash, state.signatures[1], stateChannelOpenData.participants[1].participantAddress, stateChannelOpenData.participants[1].signingAddress), "Participant #1 state signature validation failed");

        // are the actions correctly signed?
        require(validateSignature(keccak256(abi.encode(actions[0].contents)), actions[0].signature, stateChannelOpenData.participants[0].participantAddress, stateChannelOpenData.participants[0].signingAddress), "Participant #0 action signature validation failed");
        require(validateSignature(keccak256(abi.encode(actions[1].contents)), actions[1].signature, stateChannelOpenData.participants[1].participantAddress, stateChannelOpenData.participants[1].signingAddress), "Participant #1 action signature validation failed");

        // does the state machine consider this a valid point to close a channel
        require(stateMachine.isStateFinalisable(state.contents.packedStateMachineState), "State is not finalisable");

        //************************************************************************************************
        // Close the Channel
        DistributeFundsAndCloseChannel(packedOpenChannelData, state, PENALISE_NONE, CLOSE_CHANNEL_ORDERLY);
    }
}
