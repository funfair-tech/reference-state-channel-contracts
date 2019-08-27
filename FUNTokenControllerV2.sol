pragma solidity ^0.4.23;
pragma experimental ABIEncoderV2;

//************************************************************************************************
//** This code is part of a reference implementation of State Channels from FunFair
//** It is for reference purposes only.  It has not been thoroughly audited
//** DO NOT DEPLOY THIS to mainnet
//************************************************************************************************

//************************************************************************************************
//** Imports
import "./IMultiSigTransferReceiver.sol";
import "./FUnFairTokenContracts.sol";
import "./IFUNTokenControllerV2.sol";

//************************************************************************************************
//** FunFair extended Token Controller
contract FUNTokenControllerV2 is Controller, IFUNTokenControllerV2 {
	//************************************************************************************************
	//** Persistent storage

	// Used TXIDs
    mapping (bytes32 => bool) public usedTXIDs;

    // Delegation
    mapping (address => mapping (address => bool)) public delegation;

    // MultiSig Receiver Contract Whitelisting
    mapping (address => bool) public permittedMultiSigReceivers;

    //************************************************************************************************
    //** Events
    event MultiSigTransfer(bytes32 TXID, bytes input);

    //************************************************************************************************
    //** Contract name
    function getName() public pure returns (string memory) {
        return "FunFair Token Controller - v2.00.00";
    }

    //************************************************************************************************
    //** Accessor for ERC20 interface
    function getTokenAddress() public view returns (address) {
		return address(token);
	}

    //************************************************************************************************
    //** Address Delegation
    function setDelegation(address delegate, bool delegationAllowed) public {
        // you are not allowed to delegate yourself - this defeats the point!
        require(delegate != msg.sender, "You cannot delegate your own address");

        delegation[msg.sender][delegate] = delegationAllowed;
    }

    //************************************************************************************************
    //** MultiSig Receiver Contract Whitelisting
    function setPermittedMultiSigReceiver(address receiver, bool permission) public onlyOwner {
        permittedMultiSigReceivers[receiver] = permission;
    }

	//************************************************************************************************
	//** Internal transfer function
    function transferInternal(address _from, address _to, uint _value) internal returns (bool success) {
        if (ledger.transfer(_from, _to, _value)) {
            Token(token).controllerTransfer(_from, _to, _value);
            return true;
        } else {
            return false;
        }
    }

	//************************************************************************************************
	//** Multisig transfer
    function multiSigTokenTransferAndContractCall(MultiSigTokenTransferAndContractCallData memory data, Signature[2] memory signatures) public {
        // Encode input
        bytes memory input = abi.encode(data);

        // Check that the TXID has not been used
        require(usedTXIDs[data.TXID] == false, "TXID already used");
        usedTXIDs[data.TXID] = true; // Set here to prevent reentrancy

        // Check that this message is meant for us
        require(data.controllerAddress == address(this), "Transaction sent to wrong address");

        // Validate addresses
        require(data.participants[0].participantAddress != address(0x0), "Participant #0 address is invalid");
        require(data.participants[1].participantAddress != address(0x0), "Participant #1 address is invalid");

        // Validate signatures
        bytes32 inputHash = keccak256(input);
        require(ecrecover(inputHash, signatures[0].v, signatures[0].r, signatures[0].s) == data.participants[0].participantAddress, "Participant #0 signature validation failed");
        require(ecrecover(inputHash, signatures[1].v, signatures[1].r, signatures[1].s) == data.participants[1].participantAddress, "Participant #1 signature validation failed");

        // Validate the receiver
        require(permittedMultiSigReceivers[data.receiver], "Recieiver is not permitted");

        // Check the request hasn't expired
        if (data.expiry != 0) {
            require(now < data.expiry, "Request has expired");
        }

        // Check delegation and get the addresses to send tokens from
        address[2] memory sendingAddresses;

        if (data.participants[0].delegateAddress != address(0x0)) {
            require(delegation[data.participants[0].delegateAddress][data.participants[0].participantAddress], "Delegate address not authorised for Particpant #0");
            sendingAddresses[0] = data.participants[0].delegateAddress;
        } else {
            sendingAddresses[0] = data.participants[0].participantAddress;
        }

        if (data.participants[1].delegateAddress != address(0x0)) {
            require(delegation[data.participants[1].delegateAddress][data.participants[1].participantAddress], "Delegate address not authorised for Particpant #1");
            sendingAddresses[1] = data.participants[1].delegateAddress;
        } else {
            sendingAddresses[1] = data.participants[1].participantAddress;
        }

        // Transfer tokens
        require(transferInternal(sendingAddresses[0], data.receiver, data.participants[0].amount), "Token transfer for Participant #0 failed");
        require(transferInternal(sendingAddresses[1], data.receiver, data.participants[1].amount), "Token transfer for Participant #1 failed");

        // Call receiver
        require(IMultiSigTransferReceiver(data.receiver).afterMultisigTransfer(input), "MultiSig Receiver returned an error");

        // Finally, emit an event
        emit MultiSigTransfer(data.TXID, input);
    }
}

