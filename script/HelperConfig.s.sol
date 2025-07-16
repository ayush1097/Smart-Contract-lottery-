// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script,console} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
abstract contract CodeConstants {
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is Script, CodeConstants {
    /* VRF mock values */
    uint96 public constant MOCK_BASE_FEE = 0.25 ether; // 0.25 LINK
    uint96 public constant GAS_PRICE_LINK = 1e9; // 1 GWEI
    /* Link/eth price */
    uint256 public constant MOCK_WEI_PER_UNIT_LINK = 4e15; // 2000 USD per LINK

    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint32 callbackGasLimit;
        uint256 subscriptionId;
        address link; // Link token address
        address account; // Account address for funding
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].vrfCoordinator != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        console.log("Using Sepolia Eth Config");
        return NetworkConfig({
            entranceFee: 0.01 ether, // 1e16
            interval: 30, // 30 seconds
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            callbackGasLimit: 500000, // 500,000 gas
            subscriptionId: 0,
            link:0x779877A7B0D9E8603169DdbD7836e478b4624789,
            account:0x8554b93451Cef09f22Dc072F8974a06a9683EbAa

        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // Check to see if we set an active network localNetworkConfig
        console.log("Using Anvil/local Eth Config");
        if (localNetworkConfig.vrfCoordinator != address(0)) {
            return localNetworkConfig;
        }
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorMock =
            new VRFCoordinatorV2_5Mock(MOCK_BASE_FEE, GAS_PRICE_LINK, int256(MOCK_WEI_PER_UNIT_LINK));
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether, // 1e16
            interval: 30, // 30 seconds
            vrfCoordinator: address(vrfCoordinatorMock),
            // gasLane value doesn't matter.
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            callbackGasLimit: 500000, // 500,000 gas
            subscriptionId:0,
            link:address(linkToken),
            account:0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
        });
        return localNetworkConfig;
    }
 
}


