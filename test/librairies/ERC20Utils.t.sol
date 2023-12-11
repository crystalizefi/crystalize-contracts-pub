// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase,contract-name-camelcase,no-console,one-contract-per-file */
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { ERC20Utils } from "src/librairies/ERC20Utils.sol";

contract ERC20UtilsTests is Test {
    MockERC20 internal token;

    function setUp() public virtual {
        token = new MockERC20("token", "token");
    }
}

contract ERC20UtilsIncreaseTests is ERC20UtilsTests {
    function setUp() public override {
        super.setUp();
    }

    function test_ApproveFromZeroToGreaterThanZero() public {
        address wallet = vm.addr(1);
        ERC20Utils._approve(token, wallet, 20);

        uint256 allowance = token.allowance(address(this), wallet);

        assertEq(allowance, 20);
    }

    function test_AllowanceGreaterThanZeroButLessThanAmount() public {
        address wallet = vm.addr(1);
        ERC20Utils._approve(token, wallet, 20);
        ERC20Utils._approve(token, wallet, 40);

        uint256 allowance = token.allowance(address(this), wallet);

        assertEq(allowance, 40);
    }

    function test_AllowanceGreaterThanZeroGreaterThanAmount() public {
        address wallet = vm.addr(1);
        ERC20Utils._approve(token, wallet, 100);
        ERC20Utils._approve(token, wallet, 20);

        uint256 allowance = token.allowance(address(this), wallet);

        assertEq(allowance, 20);
    }

    function test_AllowanceIncreasing() public {
        address wallet = vm.addr(1);
        ERC20Utils._approve(token, wallet, 100);
        ERC20Utils._approve(token, wallet, 200);

        uint256 allowance = token.allowance(address(this), wallet);

        assertEq(allowance, 200);
    }
}

contract ERC20UtilsDecreasingTests is ERC20UtilsTests {
    address private wallet;

    function setUp() public override {
        super.setUp();

        wallet = vm.addr(1);
        ERC20Utils._approve(token, wallet, 100);
    }

    function test_AllowanceGreaterThanZeroToZero() public {
        ERC20Utils._approve(token, wallet, 20);
        ERC20Utils._approve(token, wallet, 0);

        uint256 allowance = token.allowance(address(this), wallet);

        assertEq(allowance, 0);
    }
}
