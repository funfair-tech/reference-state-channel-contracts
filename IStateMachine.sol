pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

//************************************************************************************************
//** This code is part of a reference implementation of State Channels from FunFair
//** It is for reference purposes only.  It has not been thoroughly audited
//** DO NOT DEPLOY THIS to mainnet
//************************************************************************************************

import "./Common.sol";

//************************************************************************************************
//** "Interface" to a contract that implements a state machine

contract IStateMachine is Common {
    function getInitialPackedStateMachineState(bytes memory packedStateMachineInitialisationData) public view returns (bytes memory packedStateMachineState);
    function advanceState(bytes memory packedStateMachineState, bytes memory packedActionData, uint256 participant, uint256[2] memory balances) public view returns (FFR memory isValid, bytes memory packedNewCustomState, int256 balanceChange);
    function isStateFinalisable(bytes memory packedStateMachineState) public view returns (bool);
    function getPayouts(uint256[2] memory balances, bytes memory packedStateMachineState, uint256 penalties, address[2] memory participantAddresses, uint256[2] memory initialBalances) public view returns (uint256[] memory payouts, address[] memory payoutAddresses);
}