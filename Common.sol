pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

//************************************************************************************************
//** This code is part of a reference implementation of State Channels from FunFair
//** It is for reference purposes only.  It has not been thoroughly audited
//** DO NOT DEPLOY THIS to mainnet
//************************************************************************************************

//************************************************************************************************
//** Common data structures and utilities

//************************************************************************************************
// Owned
//************************************************************************************************
contract Owned {
    address public owner;

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "contract not called by owner");
        _;
    }

    address newOwner;

    function changeOwner(address _newOwner) public onlyOwner {
        newOwner = _newOwner;
    }

    function acceptOwnership() public {
        if (msg.sender == newOwner) {
            owner = newOwner;
        }
    }
}

//************************************************************************************************
// Common
//************************************************************************************************
contract Common is Owned {

	//************************************************************************************************
	//** Constants

    // Penalties
    uint256 constant PENALISE_NONE = 0;
    uint256 constant PENALISE_P0 = 1;
    uint256 constant PENALISE_P1 = 2;

	//************************************************************************************************
	//** Data Structures
    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

	//************************************************************************************************
    //** Utilities

	// Validate signature against a non 0x0 address
    function validateSignature(bytes32 hash, Signature memory signature, address address1) internal pure returns (bool) {
        if (address1 != address(0x0)) {
            if (ecrecover(hash, signature.v, signature.r, signature.s) == address1) {
                return true;
            }
        }
        return false;
    }

	// Validate signature against two addresses - either address can be used as long as it's not 0x0
    function validateSignature(bytes32 hash, Signature memory signature, address address1, address address2) internal pure returns (bool) {
        if (address1 != address(0x0)) {
            if (ecrecover(hash, signature.v, signature.r, signature.s) == address1) {
                return true;
            }
        }

        if (address2 != address(0x0)) {
            if (ecrecover(hash, signature.v, signature.r, signature.s) == address2) {
                return true;
            }
        }

        return false;
    }

    //************************************************************************************************
    // modified require to support slightly different coding style
    struct FFR {
        bool b;
        string s;
    }

    function ffrequire(FFR memory ffr) internal pure {
        require(ffr.b, ffr.s);
    }
}

