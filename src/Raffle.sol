// Layout of the contract file:
// version
// imports
// errors
// interfaces, libraries, contracts
// Inside Contract:
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A Raffle Contract
 * @dev It implements Chainlink VRFv2.5 and Chainlink Automation
 * @author Ayush Maurya(github::ayush1097)
 * @notice This contract is for creating a sample raffle
 */
contract Raffle is VRFConsumerBaseV2Plus {
    error Raffle_NotEnoughEthSent();
    error Raffle_TransferFailed();
    error Raffle_NotOpen();
    error Raffle_UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

    // Type declarations
    enum RaffleState {
        OPEN, //0
        CALCULATING //1

    }

    uint256 private immutable i_entranceFee;
    //@dev This is the time interval for lottery to run
    uint256 private immutable i_interval;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address payable private s_recentWinner;
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    RaffleState private s_raffleState;

    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinatorV2,
        uint256 subscriptionId,
        bytes32 gasLane,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinatorV2) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_subscriptionId = subscriptionId;
        i_gasLane = gasLane;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function entreRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle_NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_NotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }
    /**
     * @dev This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return True.
     * the following should be true for this to return true:
     * 1. The time interval has passed between raffle runs.
     * 2. The lottery is open.
     * 3. The contract has ETH.
     * 4. There are players registered.
     * 5. Implicitly, your subscription is funded with LINK.
     */
    //Called off-chain by Chainlink nodes

    function checkUpkeep(bytes memory /*checkData*/ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /*performData*/ )
    {
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayers = (s_players.length > 0);
        bool hasBalance = (address(this).balance > 0);
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
        return (upkeepNeeded, "0x0");
    }
    //BE automatically called by Chainlink Keepers

    //1)  A random number
    //2)  Use the random number to pick a winning player
    //3)  Call pickWinner automatically
    // All the functions should follow the methodlogies of first (Checks, Effects, Interactions)
    //Perform on chain by Chainlink Keepers
    function performUpkeep(bytes calldata /*performData*/ ) external {
        // Checks
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        } //Effects

        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_gasLane,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        }); //Interactions
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId);
    }
    //getter functions

    function fulfillRandomWords(uint256, /*requestId*/ uint256[] calldata randomWords) internal override {
        //Cheaks
        //Effects
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(recentWinner);
        // Interactions(External calls)
        (bool sucess,) = recentWinner.call{value: address(this).balance}("");
        if (!sucess) {
            revert Raffle_TransferFailed();
        }
    }
    /// Getter functions

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }
}
