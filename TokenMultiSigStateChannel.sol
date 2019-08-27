pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

//************************************************************************************************
//** This code is part of a reference implementation of State Channels from FunFair
//** It is for reference purposes only.  It has not been thoroughly audited
//** DO NOT DEPLOY THIS to mainnet
//************************************************************************************************

import "./DisputableStateChannel.sol";
import "./IFUNTokenControllerV2.sol";

//************************************************************************************************
//** Token MultiSig State Channel

contract TokenMultiSigStateChannel is DisputableStateChannel {
    //************************************************************************************************
    //** Persistent storage

    // Permitted Channel Openers
    mapping (address => bool) public permittedChannelOpeners;

    // Token Address
    address public tokenAddress;

    //************************************************************************************************
    //** Modifiers
    modifier onlyPermittedChannelOpeners() {
        require(permittedChannelOpeners[msg.sender], "Contract caller not permitted to open a State Channel");
        _;
    }

    //************************************************************************************************
    //** Configuration
    function setChannelOpeningPermission(address a, bool isPermitted) public onlyOwner {
        permittedChannelOpeners[a] = isPermitted;
    }

    function setTokenAddress(address a) public onlyOwner {
        tokenAddress = a;
    }

    //************************************************************************************************
    //** Respond to multi-sig transfer
    function afterMultisigTransfer(bytes memory packedMultiSigInputData) public onlyPermittedChannelOpeners returns (bool) {
        //************************************************************************************************
        // Decode data
        IFUNTokenControllerV2.MultiSigTokenTransferAndContractCallData memory inputData = abi.decode(packedMultiSigInputData, (IFUNTokenControllerV2.MultiSigTokenTransferAndContractCallData));
        StateChannelOpenData memory stateChannelOpenData = abi.decode(inputData.receiverData, (StateChannelOpenData));

        // verify the contents of the State Channel Open Data line up with the multisig data
        require(inputData.TXID == stateChannelOpenData.channelID, "Channel ID doesn't match");
        require(inputData.receiver == stateChannelOpenData.channelAddress, "Channel address doesn't match");
        require(inputData.controllerAddress == stateChannelOpenData.controllerAddress, "Controller Address doesn't match");
        require(inputData.participants[0].participantAddress == stateChannelOpenData.participants[0].participantAddress, "Participant #0 Address doesn't match");
        require(inputData.participants[1].participantAddress == stateChannelOpenData.participants[1].participantAddress, "Participant #1 Address doesn't match");
        require(inputData.participants[0].delegateAddress == stateChannelOpenData.participants[0].delegateAddress, "Participant #0 Delegate Address doesn't match");
        require(inputData.participants[1].delegateAddress == stateChannelOpenData.participants[1].delegateAddress, "Participant #1 Delegate Address doesn't match");
        require(inputData.participants[0].amount == stateChannelOpenData.participants[0].amount, "Participant #0 amount doesn't match");
        require(inputData.participants[1].amount == stateChannelOpenData.participants[1].amount, "Participant #1 amount doesn't match");

        // does this message refer to us?
        require(inputData.receiver == address(this), "MultiSig transfer does not refer to this contract");

        // open the StateChannel
        return openStateChannel(inputData.receiverData);
    }

    //************************************************************************************************
    function DistributeFunds(bytes memory packedOpenChannelData, State memory state, uint256 penalties) internal returns (uint256[] memory finalBalances, address[] memory finalAddresses) {
        //************************************************************************************************
        // Decode data
        StateChannelOpenData memory stateChannelOpenData = abi.decode(packedOpenChannelData, (StateChannelOpenData));
        IStateMachine stateMachine = IStateMachine(stateChannelOpenData.stateMachineAddress);

        uint256 channelValue = state.contents.balances[0] + state.contents.balances[1];

        // for safety - double check against the on-chain stored value.
        require(channelValue == stateChannelData[stateChannelOpenData.channelID].channelValue, "Balances don't match channel value");

        // determine the addresses to return tokens to
        address[2] memory participantAddresses;

        participantAddresses[0] = (stateChannelOpenData.participants[0].delegateAddress != address(0x0)) ? stateChannelOpenData.participants[0].delegateAddress : stateChannelOpenData.participants[0].participantAddress;
        participantAddresses[1] = (stateChannelOpenData.participants[1].delegateAddress != address(0x0)) ? stateChannelOpenData.participants[1].delegateAddress : stateChannelOpenData.participants[1].participantAddress;

        // pull out the participants' initial balances
        address[2] memory initialBalances;

        initialBalances[0] = stateChannelOpenData.participants[0].amount;
        initialBalances[1] = stateChannelOpenData.participants[1].amount;

        // get the final payouts from the State Machine
        (finalBalances, finalAddresses) = stateMachine.GetPayouts(state.contents.balances, state.contents.packedStateMachineState, penalties, participantAddresses, initalBalances);

        // verify that the balances add up
        uint256 i;
        uint256 finalBalancesSum = 0;

        for (i = 0; i < finalBalances.length; i ++) {
            finalBalancesSum += finalBalances[i];
        }

        require(finalBalancesSum == channelValue, "Final Balances do not sum to channel value");

		// get the token contract
		Token token = Token(tokenAddress);

        // and make the payouts
        for (i = 0; i < finalBalances.length; i ++) {
            require(token.transfer(finalAddresses[i], finalAddresses[i]), "Token Transfer failed");
        }

    }
}
