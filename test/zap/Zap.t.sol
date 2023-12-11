// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase,contract-name-camelcase,max-line-length,one-contract-per-file */
pragma solidity 0.8.19;

import { Test, Vm } from "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { AsyncSwapper, SwapParams } from "src/swapper/AsyncSwapper.sol";
import { MockAsyncSwapper } from "test/mocks/MockAsyncSwapper.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { Pool } from "src/pool/Pool.sol";
import { Registry } from "src/pool/Registry.sol";
import { Zap, IZap } from "src/zap/Zap.sol";
import { TokenKeeper } from "src/zap/TokenKeeper.sol";
import { StargateReceiver } from "src/stargate/StargateReceiver.sol";
import { LayerZeroPacket } from "test/utils/LZPacket.sol";
import { IStargateBridge } from "src/interfaces/stargate/IStargateBridge.sol";

import { Error } from "src/librairies/Error.sol";
import { Constants } from "test/utils/Constants.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

contract ZapTest is Test {
    MockAsyncSwapper public mockSwapper;
    Pool public pool;
    Registry public registry;
    Zap public zap;
    TokenKeeper public tokenKeeper;
    StargateReceiver public receiverArb;

    MockERC20 public poolToken;
    MockERC20 public sellToken;

    SwapParams public swapParams;

    address public user;
    address public poolFactory;

    uint256 public mainnetFork;
    uint256 public arbitrumFork;

    uint256 public constant STAKE_AMOUNT = 100;
    uint256 public constant SEEDING_PERIOD = 10 days;
    uint256 public constant LOCK_PERIOD = 10 days;
    uint256 public constant MAX_STAKE_PER_ADDRESS = 500;
    uint256 public constant MAX_STAKE_PER_POOL = MAX_STAKE_PER_ADDRESS * 10;
    uint256 public constant PROTOCOL_FEE = 500;

    event SwapperSet(address indexed swapper);

    event Received(
        uint16 _chainId, bytes _srcAddress, uint256 _nonce, address _token, uint256 _amountLD, bytes _payload
    );

    event StargateDestinationsSet(uint16[] chainIds, address[] destinations);

    function setUp() public virtual {
        user = vm.addr(1);
        poolFactory = vm.addr(2);

        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), 17_988_825);
        arbitrumFork = vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC_URL"), 124_691_069);

        poolToken = new MockERC20("CRYSTALIZE", "CRYSTL");
        sellToken = new MockERC20("SELLTOKEN", "SELL");

        swapParams.sellTokenAddress = address(sellToken);
        swapParams.sellAmount = STAKE_AMOUNT;
        swapParams.buyTokenAddress = address(poolToken);
        swapParams.buyAmount = STAKE_AMOUNT;
        swapParams.data = "";

        mockSwapper = new MockAsyncSwapper();
        registry = new Registry(address(this));
        pool = new Pool(address(registry));
        tokenKeeper = new TokenKeeper(address(this));

        receiverArb = new StargateReceiver(Constants.STG_ROUTER_ARB, address(tokenKeeper));

        zap =
        new Zap(address(mockSwapper), address(registry), Constants.STG_ROUTER_MAINNET, address(tokenKeeper), address(this));

        uint16[] memory chainIds = new uint16[](1);
        chainIds[0] = 1;
        address[] memory destinations = new address[](1);
        destinations[0] = vm.addr(6);

        zap.setStargateDestinations(chainIds, destinations);

        tokenKeeper.setZapAndStargateReceiver(address(zap), address(receiverArb));

        registry.setFactory(poolFactory);

        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        pool.initialize(
            address(this),
            address(this),
            address(poolToken),
            SEEDING_PERIOD,
            LOCK_PERIOD,
            MAX_STAKE_PER_ADDRESS,
            PROTOCOL_FEE,
            MAX_STAKE_PER_POOL
        );

        registry.approvePool(address(pool));
        pool.start();

        vm.label(address(registry), "registry");
        vm.label(address(pool), "pool");
        vm.label(address(sellToken), "sellToken");
        vm.label(address(poolToken), "poolToken");
        vm.label(address(zap), "zap");
        vm.label(address(user), "user");
        vm.label(address(mockSwapper), "mockSwapper");
    }
}

contract Constructor is ZapTest {
    function test_RevertIf_SwapperIsZero() public {
        vm.expectRevert(Error.ZeroAddress.selector);
        new Zap(address(0), address(registry), address(this), address(this), address(this));
    }

    function test_RevertIf_RegistryIsZero() public {
        vm.expectRevert(Error.ZeroAddress.selector);
        new Zap(address(mockSwapper), address(0), address(this), address(this), address(this));
    }

    function test_SetsSwapperAndRegistryAddresses() public {
        Zap zap = new Zap(address(mockSwapper), address(registry), address(this), address(this), address(this));
        assertTrue(zap.swapper() == address(mockSwapper));
        assertTrue(zap.registry() == address(registry));
    }
}

contract Stake is ZapTest {
    function test_RevertIf_PoolIsNotRegistered() public {
        vm.expectRevert(IZap.PoolNotRegistered.selector);
        zap.stake(user, STAKE_AMOUNT);
    }

    function test_SetsPoolSupplyAndBalance() public {
        vm.startPrank(user);
        poolToken.approve(address(zap), STAKE_AMOUNT);
        deal(address(poolToken), user, STAKE_AMOUNT);

        assertTrue(pool.totalSupply() == 0);
        assertTrue(pool.totalSupplyLocked() == 0);
        assertTrue(pool.balances(user) == 0);
        assertTrue(pool.balancesLocked(user) == 0);

        zap.stake(address(pool), STAKE_AMOUNT);

        assertTrue(pool.totalSupply() == STAKE_AMOUNT);
        assertTrue(pool.totalSupplyLocked() == STAKE_AMOUNT);
        assertTrue(pool.balances(user) == STAKE_AMOUNT);
        assertTrue(pool.balancesLocked(user) == STAKE_AMOUNT);
        vm.stopPrank();
    }

    function test_TransfersTokensToPoolContract() public {
        vm.startPrank(user);
        poolToken.approve(address(zap), STAKE_AMOUNT);
        deal(address(poolToken), user, STAKE_AMOUNT);

        assertTrue(poolToken.balanceOf(address(pool)) == 0);
        assertTrue(poolToken.balanceOf(address(user)) == STAKE_AMOUNT);

        zap.stake(address(pool), STAKE_AMOUNT);

        assertTrue(poolToken.balanceOf(address(pool)) == STAKE_AMOUNT);
        assertTrue(poolToken.balanceOf(address(user)) == 0);

        vm.stopPrank();
    }
}

/// Since StakeFromBridge() and stake() are using the same internal stake function,
/// there is no need to duplicate the tests here
contract StakeFromBridge is ZapTest {
    function test_RevertIf_PoolIsNotRegistered() public {
        vm.expectRevert(IZap.PoolNotRegistered.selector);
        zap.stakeFromBridge(user);
    }

    function test_RevertIf_ZeroAmount() public {
        vm.expectRevert(Error.ZeroAmount.selector);
        zap.stakeFromBridge(address(pool));
    }

    function test_StakeTokenToPool() public {
        // we create a balance in TokenKeeper
        poolToken.mint(address(receiverArb), STAKE_AMOUNT);
        vm.startPrank(address(receiverArb));
        poolToken.approve(address(tokenKeeper), STAKE_AMOUNT);
        tokenKeeper.transferFromStargateReceiver(user, address(poolToken), STAKE_AMOUNT);
        vm.stopPrank();

        assertTrue(poolToken.balanceOf(address(tokenKeeper)) == STAKE_AMOUNT);
        assertTrue(tokenKeeper.balances(user, address(poolToken)) == STAKE_AMOUNT);

        // we can now call stakeFromBridge
        vm.prank(user);
        zap.stakeFromBridge(address(pool));

        assertTrue(poolToken.balanceOf(address(tokenKeeper)) == 0);
        assertTrue(tokenKeeper.balances(user, address(poolToken)) == 0);
        assertTrue(pool.balances(user) == STAKE_AMOUNT);
    }
}

/// Since SwapAndStake() and stake() are using the same internal stake function,
/// there is no need to duplicate the tests here
contract SwapAndStake is ZapTest {
    function test_RevertIf_PoolIsNotRegistered() public {
        vm.expectRevert(IZap.PoolNotRegistered.selector);
        zap.swapAndStake(swapParams, user);
    }

    function test_RevertIf_WrongPoolToken() public {
        vm.expectRevert(IZap.WrongPoolToken.selector);
        swapParams.buyTokenAddress = user;
        zap.swapAndStake(swapParams, address(pool));
    }

    /// we are just testing if revert messages work with delegatecall
    /// so no need to test every revert cases in AsyncSwapper.sol
    // as it's already being tested properly in AsyncSwapper.t.sol
    function test_RevertIf_BuyTokenAddressIsZero() public {
        vm.expectRevert(Error.ZeroAmount.selector);
        swapParams.sellAmount = 0;
        zap.swapAndStake(swapParams, address(pool));
    }

    function test_SwapsAndStakeTokenToPool() public {
        vm.startPrank(user);

        deal(address(sellToken), user, STAKE_AMOUNT);
        sellToken.approve(address(zap), STAKE_AMOUNT);

        zap.swapAndStake(swapParams, address(pool));

        assertTrue(sellToken.balanceOf(user) == 0);
        assertTrue(pool.balances(user) == swapParams.buyAmount);

        vm.stopPrank();
    }
}

/// Since SwapAndStake() and SwapAndStakeFromBridge() are using the same internal stake function,
/// there is no need to duplicate the tests here
contract SwapAndStakeFromBridge is ZapTest {
    function test_RevertIf_PoolIsNotRegistered() public {
        vm.expectRevert(IZap.PoolNotRegistered.selector);
        zap.swapAndStakeFromBridge(swapParams, user);
    }

    function test_RevertIf_ZeroAmount() public {
        vm.expectRevert(Error.ZeroAmount.selector);
        zap.swapAndStakeFromBridge(swapParams, address(pool));
    }

    /// Amount to swap is 100, but we bridged 101
    /// Both amounts should match or the tx will revert
    function test_RevertIf_AmountMismatch() public {
        // we create a balance in TokenKeeper
        sellToken.mint(address(receiverArb), STAKE_AMOUNT + 1);
        vm.startPrank(address(receiverArb));
        sellToken.approve(address(tokenKeeper), STAKE_AMOUNT + 1);
        tokenKeeper.transferFromStargateReceiver(user, address(sellToken), STAKE_AMOUNT + 1);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(IZap.WrongAmount.selector);
        zap.swapAndStakeFromBridge(swapParams, address(pool));
    }

    function test_SwapsAndStakeTokenToPool() public {
        // we create a balance in TokenKeeper
        sellToken.mint(address(receiverArb), STAKE_AMOUNT);
        vm.startPrank(address(receiverArb));
        sellToken.approve(address(tokenKeeper), STAKE_AMOUNT);
        tokenKeeper.transferFromStargateReceiver(user, address(sellToken), STAKE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user);

        assertTrue(sellToken.balanceOf(address(tokenKeeper)) == STAKE_AMOUNT);
        assertTrue(pool.balances(user) == 0);

        zap.swapAndStakeFromBridge(swapParams, address(pool));

        assertTrue(sellToken.balanceOf(address(tokenKeeper)) == 0);
        assertTrue(pool.balances(user) == swapParams.buyAmount);

        vm.stopPrank();
    }
}

contract SetStargateDestinations is ZapTest {
    function test_RevertIf_NotOwner() public {
        address testUser = vm.addr(9);

        vm.startPrank(testUser);

        uint16[] memory chainIds = new uint16[](1);
        chainIds[0] = 2;
        address[] memory destinations = new address[](1);
        destinations[0] = vm.addr(4);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, testUser));
        zap.setStargateDestinations(chainIds, destinations);

        vm.stopPrank();
    }

    function test_RevertIf_LengthZero() public {
        uint16[] memory chainIds = new uint16[](0);
        address[] memory destinations = new address[](0);

        vm.expectRevert(Error.ZeroAmount.selector);
        zap.setStargateDestinations(chainIds, destinations);
    }

    function test_RevertIf_ArrayLengthsMismatch() public {
        uint16[] memory chainIds = new uint16[](1);
        address[] memory destinations = new address[](2);

        vm.expectRevert(Error.ArrayLengthMismatch.selector);
        zap.setStargateDestinations(chainIds, destinations);
    }

    function test_RevertIf_ChainIdIsZero() public {
        uint16[] memory chainIds = new uint16[](1);
        address[] memory destinations = new address[](1);
        destinations[0] = vm.addr(5);

        vm.expectRevert(IZap.InvalidChainId.selector);
        zap.setStargateDestinations(chainIds, destinations);
    }

    function test_AllowsSettingsZeroDestination() public {
        uint16[] memory chainIds = new uint16[](1);
        chainIds[0] = 1;
        address[] memory destinations = new address[](1);

        zap.setStargateDestinations(chainIds, destinations);
    }

    function test_SetsDestination() public {
        uint16[] memory chainIds = new uint16[](1);
        chainIds[0] = 1;
        address[] memory destinations = new address[](1);
        destinations[0] = vm.addr(20);

        address existingDestination = zap.stargateDestinations(1);

        zap.setStargateDestinations(chainIds, destinations);

        address newDestination = zap.stargateDestinations(1);

        assertFalse(existingDestination == newDestination);
        assertEq(newDestination, vm.addr(20));
    }

    function test_EmitsEvents() public {
        uint16[] memory chainIds = new uint16[](1);
        chainIds[0] = 1;
        address[] memory destinations = new address[](1);
        destinations[0] = vm.addr(20);

        vm.expectEmit(false, false, false, false);
        emit StargateDestinationsSet(chainIds, destinations);
        zap.setStargateDestinations(chainIds, destinations);
    }
}

contract Bridge is ZapTest {
    function setUp() public virtual override {
        super.setUp();
        vm.mockCall(address(sellToken), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
    }

    function test_RevertIf_TokenIsZero() public {
        vm.mockCall(address(0), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.expectRevert(Error.ZeroAddress.selector);
        zap.bridge(address(0), STAKE_AMOUNT, STAKE_AMOUNT, 1, 1, 1, address(this));
    }

    function test_RevertIf_AmountIsZero() public {
        vm.expectRevert(Error.ZeroAmount.selector);
        zap.bridge(address(sellToken), 0, STAKE_AMOUNT, 1, 1, 1, address(this));
    }

    function test_RevertIf_ReceiverIsZero() public {
        vm.expectRevert(IZap.InvalidChainId.selector);
        zap.bridge(address(sellToken), STAKE_AMOUNT, STAKE_AMOUNT, 9, 1, 1, address(this));
    }

    function test_RevertIf_DestinationAccountIsZero() public {
        vm.expectRevert(Error.ZeroAddress.selector);
        zap.bridge(address(sellToken), STAKE_AMOUNT, STAKE_AMOUNT, 1, 1, 1, address(0));
    }

    function test_BridgesTokensAndEmitsEvent() public {
        uint256 usdcToSwapFrom = 100e6;
        uint256 usdtMin = 98e6;

        // Switch back to mainnet and setup our sender
        // Should have enough ETH and USDC to send across the chain
        vm.selectFork(mainnetFork);

        deal(user, 100e18);
        deal(Constants.TOKEN_USDC_MAINNET, user, usdcToSwapFrom * 10);
        // Ensure the router can take our USDC

        Zap mainnetZap = new Zap(
            address(mockSwapper),
            address(registry),
            Constants.STG_ROUTER_MAINNET,
            address(tokenKeeper),
            address(this)
        );

        uint16[] memory chainIds = new uint16[](1);
        chainIds[0] = Constants.STG_CHAIN_ID_ARBITRUM;
        address[] memory destinations = new address[](1);
        destinations[0] = address(receiverArb);

        mainnetZap.setStargateDestinations(chainIds, destinations);

        vm.startPrank(user);
        IERC20(Constants.TOKEN_USDC_MAINNET).approve(address(mainnetZap), usdcToSwapFrom * 10);
        IERC20(Constants.TOKEN_USDC_MAINNET).approve(Constants.STG_ROUTER_MAINNET, usdcToSwapFrom * 10);

        // Start recording the logs so we can find the LayerZero Packet
        // and forward it on
        vm.recordLogs();

        mainnetZap.bridge{ value: 1e18 }(
            Constants.TOKEN_USDC_MAINNET,
            usdcToSwapFrom,
            usdtMin,
            Constants.STG_CHAIN_ID_ARBITRUM,
            Constants.STG_POOL_ID_MAINNET_USDC,
            Constants.STG_POOL_ID_ARB_USDT,
            user
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

        LayerZeroPacket.Packet memory packet = LayerZeroPacket.getPacketV3(lzPacket, 20);

        // Now we deliver the packet to the Arbitrum STG Bridge
        vm.selectFork(arbitrumFork);
        IStargateBridge arbStgBridge = IStargateBridge(packet.dstAddress);

        // Bridge only accepts messages from LayerZero so figure out who we
        // need to impersonate
        address lzEndpoint = arbStgBridge.layerZeroEndpoint();

        vm.startPrank(lzEndpoint);

        vm.expectEmit(false, false, false, false);
        emit Received(Constants.STG_CHAIN_ID_ARBITRUM, packet.srcAddress, packet.nonce, Constants.TOKEN_USDT_ARB, 0, "");
        arbStgBridge.lzReceive(packet.srcChainId, packet.srcAddress, packet.nonce, packet.payload);

        vm.stopPrank();
    }
}

contract SwapAndBridge is ZapTest {
    function test_RevertIf_TokenIsZero() public {
        vm.mockCall(address(0), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.expectRevert(Error.ZeroAddress.selector);
        zap.bridge(address(0), STAKE_AMOUNT, STAKE_AMOUNT, 1, 1, 1, address(this));
    }

    function test_RevertIf_AmountIsZero() public {
        vm.mockCall(address(sellToken), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.expectRevert(Error.ZeroAmount.selector);
        zap.bridge(address(sellToken), 0, STAKE_AMOUNT, 1, 1, 1, address(this));
    }

    function test_RevertIf_ReceiverIsZero() public {
        vm.mockCall(address(sellToken), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.expectRevert(IZap.InvalidChainId.selector);
        zap.bridge(address(sellToken), STAKE_AMOUNT, STAKE_AMOUNT, 9, 1, 1, address(this));
    }

    function test_RevertIf_DestinationAccountIsZero() public {
        vm.mockCall(address(sellToken), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.expectRevert(Error.ZeroAddress.selector);
        zap.bridge(address(sellToken), STAKE_AMOUNT, STAKE_AMOUNT, 1, 1, 1, address(0));
    }
}

contract SwapAndBridgeInt is ZapTest {
    address public constant ZERO_EX_MAINNET = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    address public constant CVX_MAINNET = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    bytes public constant DATA =
        hex"d9627aa400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000008ac7230489e800000000000000000000000000000000000000000000000000000000000001a38d26000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000030000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000a99fc86cc392845d32a086464e0ed638";

    function test_SwapNoOverwriteZapOwner() public {
        vm.selectFork(mainnetFork);

        AsyncSwapper adapter = new AsyncSwapper(ZERO_EX_MAINNET);

        deal(user, 100e18);
        deal(CVX_MAINNET, user, 10e18);

        Zap mainnetZap = new Zap(
            address(adapter),
            address(registry),
            Constants.STG_ROUTER_MAINNET,
            address(tokenKeeper),
            address(this)
        );

        uint16[] memory chainIds = new uint16[](1);
        chainIds[0] = Constants.STG_CHAIN_ID_ARBITRUM;
        address[] memory destinations = new address[](1);
        destinations[0] = address(receiverArb);

        mainnetZap.setStargateDestinations(chainIds, destinations);

        vm.startPrank(user);
        IERC20(CVX_MAINNET).approve(address(mainnetZap), 10e18);

        // Start recording the logs so we can find the LayerZero Packet
        // and forward it on
        vm.recordLogs();

        mainnetZap.swapAndBridge{ value: 1e18 }(
            SwapParams(CVX_MAINNET, 10e18, Constants.TOKEN_USDC_MAINNET, 1e6, DATA),
            1e6,
            Constants.STG_CHAIN_ID_ARBITRUM,
            Constants.STG_POOL_ID_MAINNET_USDC,
            Constants.STG_POOL_ID_ARB_USDT,
            user
        );
        vm.stopPrank();

        assertEq(mainnetZap.owner(), address(this));
    }

    function test_BridgeAndSwapTokensTransfers() public {
        vm.selectFork(mainnetFork);

        AsyncSwapper adapter = new AsyncSwapper(ZERO_EX_MAINNET);

        deal(user, 100e18);
        deal(CVX_MAINNET, user, 10e18);

        Zap mainnetZap = new Zap(
            address(adapter),
            address(registry),
            Constants.STG_ROUTER_MAINNET,
            address(tokenKeeper),
            address(this)
        );

        uint16[] memory chainIds = new uint16[](1);
        chainIds[0] = Constants.STG_CHAIN_ID_ARBITRUM;
        address[] memory destinations = new address[](1);
        destinations[0] = address(receiverArb);

        mainnetZap.setStargateDestinations(chainIds, destinations);

        vm.startPrank(user);
        IERC20(CVX_MAINNET).approve(address(mainnetZap), 10e18);

        // Start recording the logs so we can find the LayerZero Packet
        // and forward it on
        vm.recordLogs();

        mainnetZap.swapAndBridge{ value: 1e18 }(
            SwapParams(CVX_MAINNET, 10e18, Constants.TOKEN_USDC_MAINNET, 1e6, DATA),
            1e6,
            Constants.STG_CHAIN_ID_ARBITRUM,
            Constants.STG_POOL_ID_MAINNET_USDC,
            Constants.STG_POOL_ID_ARB_USDT,
            user
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

        LayerZeroPacket.Packet memory packet = LayerZeroPacket.getPacketV3(lzPacket, 20);

        // Now we deliver the packet to the Arbitrum STG Bridge
        vm.selectFork(arbitrumFork);
        IStargateBridge arbStgBridge = IStargateBridge(packet.dstAddress);

        // Bridge only accepts messages from LayerZero so figure out who we
        // need to impersonate
        address lzEndpoint = arbStgBridge.layerZeroEndpoint();

        vm.startPrank(lzEndpoint);

        vm.expectEmit(false, false, false, false);
        emit Received(Constants.STG_CHAIN_ID_ARBITRUM, packet.srcAddress, packet.nonce, Constants.TOKEN_USDT_ARB, 0, "");
        arbStgBridge.lzReceive(packet.srcChainId, packet.srcAddress, packet.nonce, packet.payload);

        vm.stopPrank();
    }
}
