// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

library Constants {
    bytes32 public constant LZ_PACKET_EVT_SELECTOR = 0xe9bded5f24a4168e4f3bf44e00298c993b22376aad8c58c7dda9718a54cbea82;

    // Tokens - Mainnet
    address public constant TOKEN_USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Stargate - Mainnet
    uint16 public constant STG_CHAIN_ID_MAINNET = 101;

    address public constant STG_ROUTER_MAINNET = 0x8731d54E9D02c286767d56ac03e8037C07e01e98;
    address public constant STG_BRIDGE_MAINNET = 0x296F55F8Fb28E498B858d0BcDA06D955B2Cb3f97;

    uint256 public constant STG_POOL_ID_MAINNET_USDC = 1;
    uint256 public constant STG_POOL_ID_MAINNET_USDT = 2;

    // Tokens - Arbitrum
    address public constant TOKEN_USDT_ARB = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    // Stargate - Arbitrum
    uint16 public constant STG_CHAIN_ID_ARBITRUM = 110;

    address public constant STG_ROUTER_ARB = 0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614;
    address public constant STG_BRIDGE_ARB = 0x352d8275AAE3e0c2404d9f68f6cEE084B5bEB3DD;

    uint256 public constant STG_POOL_ID_ARB_USDC = 1;
    uint256 public constant STG_POOL_ID_ARB_USDT = 2;
}
