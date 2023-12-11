// SPDX-License-Identifier: MIT
// solhint-disable func-name-mixedcase,contract-name-camelcase,max-line-length,no-inline-assembly,one-contract-per-file
pragma solidity 0.8.19;

import { Test, Vm } from "forge-std/Test.sol";
import { Error } from "src/librairies/Error.sol";
import { Constants } from "test/utils/Constants.sol";
import { LayerZeroPacket } from "test/utils/LZPacket.sol";
import { StargateReceiver, IStargateReceiver } from "src/stargate/StargateReceiver.sol";
import { TokenKeeper } from "src/zap/TokenKeeper.sol";
import { IStargateRouter } from "src/interfaces/stargate/IStargateRouter.sol";
import { IStargateBridge } from "src/interfaces/stargate/IStargateBridge.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract StargateReceiverTest is Test {
    uint256 public mainnetFork;
    uint256 public arbitrumFork;

    TokenKeeper public tokenKeeper;

    StargateReceiver public receiverArb;

    // LayerZero - ILayerZeroUltraLightNodeV2
    event Packet(bytes payload);

    event Received(
        uint16 _chainId, bytes _srcAddress, uint256 _nonce, address _token, uint256 _amountLD, bytes _payload
    );

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_779_949);
        arbitrumFork = vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 115_248_573);

        tokenKeeper = new TokenKeeper(address(this));

        receiverArb = new StargateReceiver(Constants.STG_ROUTER_ARB, address(tokenKeeper));

        tokenKeeper.setZapAndStargateReceiver(address(this), address(receiverArb));

        vm.label(Constants.TOKEN_USDC_MAINNET, "usdcMainnet");
        vm.label(Constants.STG_ROUTER_MAINNET, "stgRouterMainnet");
    }
}

contract Constructor is StargateReceiverTest {
    function test_RevertIf_RouterIsZero() public {
        vm.expectRevert(Error.ZeroAddress.selector);
        new StargateReceiver(address(0), address(this));
    }

    function test_RevertIf_TokenKeeperIsZero() public {
        vm.expectRevert(Error.ZeroAddress.selector);
        new StargateReceiver(address(this), address(0));
    }
}

contract sgReceive is StargateReceiverTest {
    function test_RevertsIf_NotRouter() public {
        vm.expectRevert(IStargateReceiver.InvalidSender.selector);
        receiverArb.sgReceive(1, "", 1, address(this), 1, "");
    }

    function test_ReceivesTokensAndEmitsEvent() public {
        uint256 usdcToSwapFrom = 100e6;
        uint256 usdtMin = 98e6;

        // Switch back to mainnet and setup our sender
        // Should have enough ETH and USDC to send across the chain
        vm.selectFork(mainnetFork);
        address swapUser = vm.addr(10);
        vm.label(swapUser, "swapUser");
        deal(swapUser, 100e18);
        deal(Constants.TOKEN_USDC_MAINNET, swapUser, usdcToSwapFrom * 10);

        vm.startPrank(swapUser);

        // Ensure the router can take our USDC
        IERC20(Constants.TOKEN_USDC_MAINNET).approve(Constants.STG_ROUTER_MAINNET, usdcToSwapFrom * 10);

        // Mimic some data we'll need to send across the chain
        bytes memory outgoingData = abi.encode(swapUser);

        // Start recording the logs so we can find the LayerZero Packet
        // and forward it on
        vm.recordLogs();

        // Swap from USDC on Mainnet to USDT on Arbitrum
        IStargateRouter(Constants.STG_ROUTER_MAINNET).swap{ value: 1e18 }(
            Constants.STG_CHAIN_ID_ARBITRUM, // the destination chain id
            Constants.STG_POOL_ID_MAINNET_USDC, // the source Stargate poolId
            Constants.STG_POOL_ID_ARB_USDT, // the destination Stargate poolId
            payable(msg.sender), // refund address. if msg.sender pays too much gas, return extra eth
            usdcToSwapFrom, // total tokens to send to destination chain
            usdtMin, // min amount allowed out
            IStargateRouter.lzTxObj(200_000, 0, "0x"), // default lzTxObj, 200_000 amt of gas to execute sgReceive()
            abi.encodePacked(address(receiverArb)), // destination address, the sgReceive() implementer
            outgoingData // bytes payload
        );

        vm.stopPrank();

        // Find the LayerZero Packet
        bytes memory lzPacket;
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            // Had to save off the selector as there is an IR bug if we try to use it directly
            if (entries[i].topics[0] == Constants.LZ_PACKET_EVT_SELECTOR) {
                lzPacket = abi.decode(entries[i].data, (bytes));
            }
        }

        // A LayerZero Packet is pack encoded and is made of
        // - nonce - uint64
        // - localChainId - uint16
        // - ua - the sender (STG Bridge) - address
        // - dstChainId - uint16
        // - dstAddress - bytes memory
        // - payload - bytes memory

        // This will decode the packet
        // We've tweak the getPacketV3 from LayerZero to perform some of the srcAddress manipulation
        // that the LZ endpoint would normally do since we are delivering the packet directly
        // to the STG bridge. The LZ endpoint will take the srcAddress
        // which is just the STG bridge and attach the destination to it at all well
        // so by the time it gets to the STG bridge its actually srcAddress+dstAddress
        LayerZeroPacket.Packet memory packet = LayerZeroPacket.getPacketV3(lzPacket, 20);

        // Now we deliver the packet to the Arbitrum STG Bridge
        vm.selectFork(arbitrumFork);
        IStargateBridge arbStgBridge = IStargateBridge(packet.dstAddress);

        // We're doing a swap from USDC->USDT, make sure we get our tokens
        uint256 usdtBalBefore = IERC20(Constants.TOKEN_USDT_ARB).balanceOf(address(receiverArb));

        // Bridge only accepts messages from LayerZero so figure out who we
        // need to impersonate
        address lzEndpoint = arbStgBridge.layerZeroEndpoint();
        vm.startPrank(lzEndpoint);

        vm.expectEmit(false, false, false, false);
        emit Received(Constants.STG_CHAIN_ID_ARBITRUM, packet.srcAddress, packet.nonce, Constants.TOKEN_USDT_ARB, 0, "");
        arbStgBridge.lzReceive(packet.srcChainId, packet.srcAddress, packet.nonce, packet.payload);

        vm.stopPrank();

        // The TokenKeeper contract should have at least our minimum USDT
        uint256 usdtBalAfter = IERC20(Constants.TOKEN_USDT_ARB).balanceOf(address(tokenKeeper));
        assertTrue(usdtBalAfter - usdtBalBefore >= usdtMin);

        // TokenKeeper should also have a balance entry for swapUser
        assertTrue(tokenKeeper.balances(swapUser, Constants.TOKEN_USDT_ARB) >= usdtMin);
    }
}
