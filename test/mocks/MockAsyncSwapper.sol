// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Error } from "src/librairies/Error.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { SwapParams } from "src/interfaces/swapper/IAsyncSwapper.sol";

contract MockAsyncSwapper {
    function swap(SwapParams memory swapParams) public returns (uint256 buyTokenAmountReceived) {
        if (swapParams.sellAmount == 0) revert Error.ZeroAmount();

        // send it to oblivion to pretend we swapped
        MockERC20(swapParams.sellTokenAddress).burn(address(this), swapParams.sellAmount);

        // mint the buy token to pretend we received it
        MockERC20(swapParams.buyTokenAddress).mint(address(this), swapParams.buyAmount);

        return swapParams.buyAmount;
    }
}
