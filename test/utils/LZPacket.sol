// SPDX-License-Identifier: BUSL-1.1
// solhint-disable func-name-mixedcase,contract-name-camelcase,max-line-length,no-inline-assembly,custom-errors
// Ref'd from:
// https://github.com/LayerZero-Labs/LayerZero/blob/48c21c3921931798184367fc02d3a8132b041942/contracts/proof/utility/LayerZeroPacket.sol

pragma solidity 0.8.19;

import { Buffer } from "./Buffer.sol";

library LayerZeroPacket {
    using Buffer for Buffer.buffer;

    struct Packet {
        uint16 srcChainId;
        uint16 dstChainId;
        uint64 nonce;
        address dstAddress;
        bytes srcAddress;
        bytes payload;
    }

    function getPacketV3(
        bytes memory data,
        uint256 sizeOfSrcAddress
    ) internal pure returns (LayerZeroPacket.Packet memory) {
        // data def: abi.encodePacked(nonce, srcChain, srcAddress, dstChain, dstAddress, payload);
        //              if from EVM
        // 0 - 31       0 - 31          |  total bytes size
        // 32 - 39      32 - 39         |  nonce
        // 40 - 41      40 - 41         |  srcChainId
        // 42 - P       42 - 61         |  srcAddress, where P = 41 + sizeOfSrcAddress,
        // P+1 - P+2    62 - 63         |  dstChainId
        // P+3 - P+22   64 - 83         |  dstAddress
        // P+23 - END   84 - END        |  payload

        // decode the packet
        uint256 realSize = data.length;
        uint256 nonPayloadSize = sizeOfSrcAddress + 32 + sizeOfSrcAddress; // 2 + 2 + 8 + 20, 32 + 20 = 52 if
            // sizeOfSrcAddress == 20
        require(realSize >= nonPayloadSize, "LayerZeroPacket: invalid packet");
        uint256 payloadSize = realSize - nonPayloadSize;

        uint64 nonce;
        uint16 srcChain;
        uint16 dstChain;
        address dstAddress;
        assembly {
            nonce := mload(add(data, 8)) // 40 - 32
            srcChain := mload(add(data, 10)) // 42 - 32
            dstChain := mload(add(data, add(12, sizeOfSrcAddress))) // P + 3 - 32 = 41 + size + 3 - 32 = 12 + size
            dstAddress := mload(add(data, add(32, sizeOfSrcAddress))) // P + 23 - 32 = 41 + size + 23 - 32 = 32 + size
        }

        require(srcChain != 0, "LayerZeroPacket: invalid packet");

        Buffer.buffer memory srcAddressBuffer;
        srcAddressBuffer.init(sizeOfSrcAddress * 2);

        srcAddressBuffer.writeRawBytes(0, data, 42, sizeOfSrcAddress);
        srcAddressBuffer.writeRawBytes(sizeOfSrcAddress, data, 64, sizeOfSrcAddress);

        Buffer.buffer memory payloadBuffer;
        if (payloadSize > 0) {
            payloadBuffer.init(payloadSize + sizeOfSrcAddress);
            payloadBuffer.writeRawBytes(sizeOfSrcAddress, data, nonPayloadSize + 32, payloadSize);
        }

        return LayerZeroPacket.Packet(srcChain, dstChain, nonce, dstAddress, srcAddressBuffer.buf, payloadBuffer.buf);
    }
}
