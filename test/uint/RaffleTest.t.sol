// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {LinkToken} from "../../test/mocks/LinkToken.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Vm} from "forge-std/Vm.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperConfig;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;
    LinkToken public link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;
        link = LinkToken(config.link);
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    /*                                Enter Raffle                                          */
    //////////////////////////////////////////////////////////////////////////////////////////
    function testRaffleRevertsWhenNotEnoughEthSent() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle_NotEnoughEthSent.selector);
        raffle.entreRaffle();
        vm.stopPrank();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        //Arrange
        vm.prank(PLAYER);
        //ACT
        raffle.entreRaffle{value: entranceFee}(); //Here the PLAYER enter the raffle along with the entrance fee
        //assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER); // IT compare the address of the player who entered the raffle with the PLAYER address
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        //console.log(address(raffle));
        //console.log(address(PLAYER));
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEnter(PLAYER);
        raffle.entreRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.entreRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep(""); // This will change the state to CALCULATING
        vm.expectRevert(Raffle.Raffle_NotOpen.selector);
        vm.prank(PLAYER);
        raffle.entreRaffle{value: entranceFee}();
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    /*                                Check UP KEEP                                         */
    //////////////////////////////////////////////////////////////////////////////////////////

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
        //Arrange
        /* A note how this function works
        Here in this first we make a fake player NAME::PLAYER which enters the raffle with some money it is written
        it passes the given timestamp vm.roll switch to the next block or player (Till now s_raffleState is OPEN)
        then we call the performUpkeep it switches the s_raffleState into CALCULATING So when raffle.checkUpkeep returns 1 which
        means that it is calculating , checkup already false because we have spend time and many players have entered the raffle,
        
         */
        vm.prank(PLAYER);
        raffle.entreRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep(""); // This will change the state to CALCULATING
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        //ACT
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //assert
        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(upkeepNeeded == false);
    }

    //challenges
    //testCheckUpkeepReturnsFalseIfEnoughTimeHasPassed
    //testCheckUpkeepReturnsTrueWhenParametersGood

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        raffle.entreRaffle{value: entranceFee}();
        // vm.warp(block.timestamp + interval + 1);
        //vm.roll(block.number + 1);
        // raffle.performUpkeep("");
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        vm.prank(PLAYER);
        raffle.entreRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded == true);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    /*                                Perform Upkeep                                        */
    //////////////////////////////////////////////////////////////////////////////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        vm.prank(PLAYER);
        raffle.entreRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep(""); // This will change the state to CALCULATING
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        //ARRANGE
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.entreRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayers = numPlayers + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle_UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                uint256(rState)
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEntredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.entreRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEntredAndTimePassed
    {
        //    ACT
        vm.recordLogs();
        raffle.performUpkeep(""); // This will change the state to CALCULATING
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        /*entries[1]:: It means that when we are calling the revert function, it redirect to it then send the
            second thing which are in the log ("Give me the second event that was emitted during performUpkeep.")
            
            topics[1]::Every event has a topics array that stores important indexed values, like requestId.
            topics[0] is the event signature (like a label that tells which event was emitted). 
            topics[1] is usually the first indexed argument (here, likely the requestId).
            So .topics[1] gives us the actual value of requestId that Chainlink emitted.*/
        //assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1); //0=open, 1=calculating
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    /*                                FulfillRandomWords                                    */
    //////////////////////////////////////////////////////////////////////////////////////////

    modifier skipfork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEntredAndTimePassed skipfork {
        //FUZZ testing
        vm.expectRevert(
                VRFCoordinatorV2_5Mock.InvalidRequest.selector
            ); /*//This line tell that you will expect revert of InvalidRequest */
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEntredAndTimePassed
        skipfork
    {
        //ARRANGE
        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);
        for (
            uint256 i = startingIndex;
            i < additionalEntrants + startingIndex;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARTING_PLAYER_BALANCE);
            raffle.entreRaffle{value: entranceFee}();
        }
        //uint256 prize = entranceFee * (additionalEntrants + 1);
        uint256 winnerStartingBalance = expectedWinner.balance;
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        //ACT
        vm.recordLogs();
        raffle.performUpkeep(""); // This will change the state to CALCULATING & emits requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        //assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(expectedWinner == recentWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
