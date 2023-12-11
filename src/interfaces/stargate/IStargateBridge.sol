// SPDX-License-Identifier: BUSL-1.1
// Ref'd from: https://etherscan.io/address/0x296f55f8fb28e498b858d0bcda06d955b2cb3f97#code

pragma solidity 0.8.19;

interface IStargateBridge {
    function lzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) external;

    function layerZeroEndpoint() external view returns (address);
}
