//pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

//************************************************************************************************
//** This code is part of a reference implementation of State Channels from FunFair
//** It is for reference purposes only.  It has not been thoroughly audited
//** DO NOT DEPLOY THIS to mainnet
//************************************************************************************************

//************************************************************************************************
//** "Interface" to a contract that can receive tokens from a multi-sig transfer and do something afterwards

contract IMultiSigTransferReceiver {
    function afterMultisigTransfer(bytes memory input) public returns (bool);
}