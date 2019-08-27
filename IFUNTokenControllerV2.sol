pragma solidity ^0.4.23;

//************************************************************************************************
//** This code is part of a reference implementation of State Channels from FunFair
//** It is for reference purposes only.  It has not been thoroughly audited
//** DO NOT DEPLOY THIS to mainnet
//************************************************************************************************

//************************************************************************************************
//** "Interface" to the the FunFair Token Controller, containing data structure definitions

contract IFUNTokenControllerV2 {
	//************************************************************************************************
	//** Data Structures
    struct MultiSigParticipant {
        address participantAddress;
        address delegateAddress;
        uint256 amount;
    }

    struct MultiSigTokenTransferAndContractCallData {
        bytes32 TXID;
        address controllerAddress;
        MultiSigParticipant[2] participants;
        address receiver;
        uint256 expiry;
        bytes receiverData;
    }

    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    //************************************************************************************************
    //** Accessor for ERC20 interface
    function getTokenAddress() public view returns (address);
}
