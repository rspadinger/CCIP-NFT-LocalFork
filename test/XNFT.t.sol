// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
//@note CCIPLocalSimulatorFork
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

import {XNFT} from "../src/XNFT.sol";
import {EncodeExtraArgs} from "./utils/EncodeExtraArgs.sol";

contract XNFTTest is Test {
    //@note define chain forks and network details
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    uint256 ethSepoliaFork;
    uint256 arbSepoliaFork;
    Register.NetworkDetails ethSepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    address alice;
    address bob;

    XNFT public ethSepoliaXNFT;
    XNFT public arbSepoliaXNFT;

    EncodeExtraArgs public encodeExtraArgs;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        //@note get RPC URLs from .env & create network forks
        string memory ETHEREUM_SEPOLIA_RPC_URL = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
        string memory ARBITRUM_SEPOLIA_RPC_URL = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");

        ethSepoliaFork = vm.createSelectFork(ETHEREUM_SEPOLIA_RPC_URL);
        arbSepoliaFork = vm.createFork(ARBITRUM_SEPOLIA_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        //@note mark the specified accounts as persistent, which means that their state
        //is available regardless of which fork is currently active.
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // Step 1) Deploy XNFT.sol to Ethereum Sepolia
        assertEq(vm.activeFork(), ethSepoliaFork);

        //@get network details
        ethSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid); // we are currently on Ethereum Sepolia Fork
        assertEq(
            ethSepoliaNetworkDetails.chainSelector,
            16015286601757825753,
            "Sanity check: Ethereum Sepolia chain selector should be 16015286601757825753"
        );

        ethSepoliaXNFT = new XNFT(
            ethSepoliaNetworkDetails.routerAddress,
            ethSepoliaNetworkDetails.linkAddress,
            ethSepoliaNetworkDetails.chainSelector
        );

        // Step 2) Deploy XNFT.sol to Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        assertEq(vm.activeFork(), arbSepoliaFork);

        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid); // we are currently on Arbitrum Sepolia Fork - chainId: 421614
        assertEq(
            arbSepoliaNetworkDetails.chainSelector,
            3478487238524512106,
            "Sanity check: Arbitrum Sepolia chain selector should be 3478487238524512106"
        );

        arbSepoliaXNFT = new XNFT(
            arbSepoliaNetworkDetails.routerAddress,
            arbSepoliaNetworkDetails.linkAddress,
            arbSepoliaNetworkDetails.chainSelector
        );
    }

    function testShouldMintNftOnArbitrumSepoliaAndTransferItToEthereumSepolia() public {
        // Step 3) On Ethereum Sepolia, call enableChain function
        vm.selectFork(ethSepoliaFork);
        assertEq(vm.activeFork(), ethSepoliaFork);

        encodeExtraArgs = new EncodeExtraArgs();

        uint256 gasLimit = 200_000;
        bytes memory extraArgs = encodeExtraArgs.encode(gasLimit);
        assertEq(extraArgs, hex"97a657c90000000000000000000000000000000000000000000000000000000000030d40"); // value taken from https://cll-devrel.gitbook.io/ccip-masterclass-3/ccip-masterclass/exercise-xnft#step-3-on-ethereum-sepolia-call-enablechain-function

        //enable Arbitrum chain & XNFT on Ethereum
        ethSepoliaXNFT.enableChain(arbSepoliaNetworkDetails.chainSelector, address(arbSepoliaXNFT), extraArgs);

        // Step 4) On Arbitrum Sepolia, call enableChain function
        vm.selectFork(arbSepoliaFork);
        assertEq(vm.activeFork(), arbSepoliaFork);

        arbSepoliaXNFT.enableChain(ethSepoliaNetworkDetails.chainSelector, address(ethSepoliaXNFT), extraArgs);

        // Step 5) On Arbitrum Sepolia, fund XNFT.sol with 10 LINK
        assertEq(vm.activeFork(), arbSepoliaFork);

        ccipLocalSimulatorFork.requestLinkFromFaucet(address(arbSepoliaXNFT), 10 ether);

        // Step 6) On Arbitrum Sepolia, mint new xNFT
        assertEq(vm.activeFork(), arbSepoliaFork);

        vm.startPrank(alice);

        arbSepoliaXNFT.mint();
        uint256 tokenId = 0;
        assertEq(arbSepoliaXNFT.balanceOf(alice), 1);
        assertEq(arbSepoliaXNFT.ownerOf(tokenId), alice);

        // Step 7) On Arbitrum Sepolia, crossTransferFrom xNFT to Bob on Ethereum
        arbSepoliaXNFT.crossChainTransferFrom(
            address(alice),
            address(bob),
            tokenId,
            ethSepoliaNetworkDetails.chainSelector,
            XNFT.PayFeesIn.LINK
        );

        vm.stopPrank();

        assertEq(arbSepoliaXNFT.balanceOf(alice), 0);

        // On Ethereum Sepolia, check if xNFT was succesfully transferred
        //@note switch ccipLocalSimulator from Arbitrum to Ethereum & route all messages =>
        // selectFork would not be sufficient
        ccipLocalSimulatorFork.switchChainAndRouteMessage(ethSepoliaFork);
        assertEq(vm.activeFork(), ethSepoliaFork);

        assertEq(ethSepoliaXNFT.balanceOf(bob), 1);
        assertEq(ethSepoliaXNFT.ownerOf(tokenId), bob);
    }
}
