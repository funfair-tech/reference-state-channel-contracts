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
//** European Roulette

contract EuropeanRoulette is IGame {
    uint256 private constant NUM_BET_POSITIONS = 163;
    uint256 private constant NUM_BALL_POSITIONS = 37;

    struct State {
        uint256 lastBallPosition;
        uint256[163 /*NUM_BET_POSITIONS*/] lastBetResults;
    }

    struct Action {
        uint256[163 /*NUM_BET_POSITIONS*/] stakeAmounts;
    }

    // each of the 163 possible bets are encoded
    // the least significant 37 (padded to 40) bits are used to store if this bet wins given the ball position
    // (the least significant bit represents zero)
    // the most significant 8 bits represent the multiple of the stake for a win
    // eg:
    // "0x240000000001" - pay out 0x24 == 36:1 for a straight up bet on zero
    // "0x020AAAAAAAAA" - pay out 0x02 == 2:1 on odd numbers
    function getBetDescriptors() private pure returns (uint48[163 /*NUM_BET_POSITIONS*/] memory betDescriptors) {
        betDescriptors = [
            0x240000000001, 0x240000000002, 0x240000000004, 0x240000000008, 0x240000000010, 0x240000000020, 0x240000000040, 0x240000000080,
            0x240000000100, 0x240000000200, 0x240000000400, 0x240000000800, 0x240000001000, 0x240000002000, 0x240000004000, 0x240000008000,
            0x240000010000, 0x240000020000, 0x240000040000, 0x240000080000, 0x240000100000, 0x240000200000, 0x240000400000, 0x240000800000,
            0x240001000000, 0x240002000000, 0x240004000000, 0x240008000000, 0x240010000000, 0x240020000000, 0x240040000000, 0x240080000000,
            0x240100000000, 0x240200000000, 0x240400000000, 0x240800000000, 0x241000000000, 0x000000000000, 0x030000001FFE, 0x030001FFE000,
            0x031FFE000000, 0x02000007FFFE, 0x021FFFF80000, 0x021555555554, 0x020AAAAAAAAA, 0x020AB552AD54, 0x02154AAD52AA, 0x030492492492,
            0x030924924924, 0x031249249248, 0x0C000000000E, 0x0C0000000070, 0x0C0000000380, 0x0C0000001C00, 0x0C000000E000, 0x0C0000070000,
            0x0C0000380000, 0x0C0001C00000, 0x0C000E000000, 0x0C0070000000, 0x0C0380000000, 0x0C1C00000000, 0x06000000007E, 0x0600000003F0,
            0x060000001F80, 0x06000000FC00, 0x06000007E000, 0x0600003F0000, 0x060001F80000, 0x06000FC00000, 0x06007E000000, 0x0603F0000000,
            0x061F80000000, 0x120000000006, 0x120000000012, 0x12000000000C, 0x120000000024, 0x120000000048, 0x120000000030, 0x120000000090,
            0x120000000060, 0x120000000120, 0x120000000240, 0x120000000180, 0x120000000480, 0x120000000300, 0x120000000900, 0x120000001200,
            0x120000000C00, 0x120000002400, 0x120000001800, 0x120000004800, 0x120000009000, 0x120000006000, 0x120000012000, 0x12000000C000,
            0x120000024000, 0x120000048000, 0x120000030000, 0x120000090000, 0x120000060000, 0x120000120000, 0x120000240000, 0x120000180000,
            0x120000480000, 0x120000300000, 0x120000900000, 0x120001200000, 0x120000C00000, 0x120002400000, 0x120001800000, 0x120004800000,
            0x120009000000, 0x120006000000, 0x120012000000, 0x12000C000000, 0x120024000000, 0x120048000000, 0x120030000000, 0x120090000000,
            0x120060000000, 0x120120000000, 0x120240000000, 0x120180000000, 0x120480000000, 0x120300000000, 0x120900000000, 0x121200000000,
            0x120C00000000, 0x121800000000, 0x090000000036, 0x09000000006C, 0x0900000001B0, 0x090000000360, 0x090000000D80, 0x090000001B00,
            0x090000006C00, 0x09000000D800, 0x090000036000, 0x09000006C000, 0x0900001B0000, 0x090000360000, 0x090000D80000, 0x090001B00000,
            0x090006C00000, 0x09000D800000, 0x090036000000, 0x09006C000000, 0x0901B0000000, 0x090360000000, 0x090D80000000, 0x091B00000000,
            0x0C0000000007, 0x0C000000000D, 0x000000000000, 0x000000000000, 0x09000000000F, 0x000000000000, 0x120000000003, 0x120000000005,
            0x120000000009, 0x000000000000, 0x000000000000
        ];
    }


    //******************************************************************************************
    function getIndividualBetResultMultiplier(uint48 betDescriptor, uint256 ballPosition) public pure returns (uint result) {
        // does this bet win given the ball position, and if so, how much
        uint256 ballBitPosition = betDescriptor >> ballPosition;

        if ((ballBitPosition & 1) > 0) {
            // win!
            return ((betDescriptor >> 40) & 0xff);
        } else {
            // lose...
            return 0x0;
        }
    }

    //************************************************************************************************
    function getBatchBetResults(uint48[163] memory betDescriptors, uint[163] memory stakeAmounts, uint ballPosition) public pure returns (uint[163] memory betResults) {
        for (uint256 i = 0; i < NUM_BET_POSITIONS; i++) {
            betResults[i] = getIndividualBetResultMultiplier(betDescriptors[i], ballPosition) * stakeAmounts[i];
        }
    }

    //************************************************************************************************
    function getBallPosition(bytes32 seed) private pure returns (uint256 ballPosition) {
        return uint256(seed) % NUM_BALL_POSITIONS;
    }

    //************************************************************************************************
    function getTotalStaked(uint256[163] memory stakeAmounts) private pure returns (uint256 totalStaked) {
        totalStaked = 0;

        for (uint256 i = 0; i < NUM_BET_POSITIONS; i++) {
            totalStaked += stakeAmounts[i];
        }
    }

    //************************************************************************************************
    function getWinTotal(uint256[163] memory betResults) private pure returns (uint256 winTotal) {
        winTotal = 0;

        for (uint256 i = 0; i < NUM_BET_POSITIONS; i++) {
            winTotal += betResults[i];
        }
    }

    //************************************************************************************************
    function getMaxWin(uint48[163] memory betDescriptors, uint256[163] memory stakeAmounts) public pure returns (uint maxWin) {
        // step through all possible ball positions to look for the maxiumum possible win
        maxWin = 0;

        for (uint256 i = 0; i < NUM_BET_POSITIONS; i++) {
            uint256 winTotal = getWinTotal(getBatchBetResults(betDescriptors, stakeAmounts, i));

            if (winTotal > maxWin) {
                maxWin = winTotal;
            }
        }
    }

    //************************************************************************************************
    function getPackedInitialGameState() public view returns (bytes memory packedInitialGameState) {
        State memory s;

        return abi.encode(s);
    }


    //************************************************************************************************
    function validateStartRound(bytes memory /*packedGameState*/, bytes memory packedGameAction) public view returns (bool isValid, uint256 maxP0Loss, uint256 maxP1Loss) {
        Action memory action = abi.decode(packedGameAction, (Action));

        isValid = true;
        // are the bets sane?
        for (uint256 i = 0; i < NUM_BET_POSITIONS; i++) {
            if (!isSane(action.stakeAmounts[i])) {
                isValid = false;
            }
        }

        if (isValid) {
            // calculate the max win and loss
            maxP0Loss = getTotalStaked(action.stakeAmounts);
            maxP1Loss = getMaxWin(getBetDescriptors(), action.stakeAmounts);
        }
    }

    //**************************************************************************************************
    function validateContinueRound(bytes memory /*packedGameState*/, bytes memory /*packedGameAction*/) public view returns (bool isValid) {
        return false;
    }

    //**************************************************************************************************
    function startRound(bytes32 rngSeed, bytes memory /*packedGameState*/, bytes memory packedGameAction) public view returns (int256 winLoss, bool isEndOfRound, bytes memory packedNewGameState) {
        Action memory action = abi.decode(packedGameAction, (Action));

        // spin the wheel
        uint256 ballPosition = getBallPosition(rngSeed);

        // get the results
        uint[163] memory betResults = getBatchBetResults(getBetDescriptors(), action.stakeAmounts, ballPosition);

        // create the new state
        State memory newState;
        newState.lastBallPosition = ballPosition;
        newState.lastBetResults = betResults;

        // return the result
        winLoss = int256(getWinTotal(betResults)) - int256(getTotalStaked(action.stakeAmounts));
        isEndOfRound = true;
        packedNewGameState = abi.encode(newState);
    }

    //**************************************************************************************************
    function continueRound(bytes32 /*rngSeed*/, bytes memory /*packedGameState*/, bytes memory /*packedGameAction*/) public view returns (int256 /*winLoss*/, bool /*isEndOfRound*/, bytes memory /*packedNewGameState*/) {
        // this can never be called
    }
}

