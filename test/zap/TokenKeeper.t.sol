// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase,contract-name-camelcase,one-contract-per-file */
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";

import { TokenKeeper } from "src/zap/TokenKeeper.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

import { Error } from "src/librairies/Error.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";

contract TokenKeeperTest is Test {
    TokenKeeper public tokenKeeper;

    address public user;
    address public zap;
    address public receiver;

    MockERC20 public token;

    uint256 public constant BRIDGED_AMOUNT = 100e18;

    event BridgedTokensReceived(address indexed account, address indexed token, uint256 amount);
    event ZapSet(address indexed zap);
    event StargateReceiverSet(address indexed receiver);
    event TokenTransferred(address indexed from, address indexed to, address indexed token, uint256 amount);

    function setUp() public {
        user = vm.addr(1);
        zap = vm.addr(2);
        receiver = vm.addr(3);

        token = new MockERC20("CRYSTALIZE", "CRYSTL");
        token.mint(receiver, BRIDGED_AMOUNT);

        tokenKeeper = new TokenKeeper(address(this));
        tokenKeeper.setZapAndStargateReceiver(zap, receiver);
    }
}

/// No need to add more usecases for this function as
/// they are fully tested in setZap and SetStargateReceiver below
contract setZapAndStargateReceiver is TokenKeeperTest {
    function test_revertIf_NotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        tokenKeeper.setZapAndStargateReceiver(zap, receiver);
    }
}

contract setZap is TokenKeeperTest {
    function test_revertIf_NotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        tokenKeeper.setZap(zap);
    }

    function test_EmitsZapSetEvent() public {
        vm.expectEmit(true, false, false, false);
        emit ZapSet(user);
        tokenKeeper.setZap(user);
    }

    function test_SetsZap() public {
        tokenKeeper.setZap(user);
        assertTrue(tokenKeeper.zap() == user);
    }
}

contract SetStargateReceiver is TokenKeeperTest {
    function test_revertIf_NotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        tokenKeeper.setStargateReceiver(receiver);
    }

    function test_EmitsStargateReceiverSetEvent() public {
        vm.expectEmit(true, false, false, false);
        emit StargateReceiverSet(user);
        tokenKeeper.setStargateReceiver(user);
    }

    function test_SetsStargateReceiver() public {
        tokenKeeper.setStargateReceiver(user);
        assertTrue(tokenKeeper.stargateReceiver() == user);
    }
}

contract TransferFromStargateReceiver is TokenKeeperTest {
    function test_RevertIf_NotReceiver() public {
        vm.expectRevert(Error.Unauthorized.selector);
        tokenKeeper.transferFromStargateReceiver(user, address(token), BRIDGED_AMOUNT);
    }

    function test_RevertIf_AccountIsZero() public {
        vm.prank(receiver);
        vm.expectRevert(Error.ZeroAddress.selector);
        tokenKeeper.transferFromStargateReceiver(address(0), address(token), BRIDGED_AMOUNT);
    }

    function test_RevertIf_TokenIsZero() public {
        vm.prank(receiver);
        vm.expectRevert(Error.ZeroAddress.selector);
        tokenKeeper.transferFromStargateReceiver(user, address(0), BRIDGED_AMOUNT);
    }

    function test_RevertIf_AmountIsZero() public {
        vm.prank(receiver);
        vm.expectRevert(Error.ZeroAmount.selector);
        tokenKeeper.transferFromStargateReceiver(user, address(token), 0);
    }

    function test_EmitsBridgedTokensReceivedEvent() public {
        vm.startPrank(receiver);

        // we approve the token transfer
        token.approve(address(tokenKeeper), BRIDGED_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit BridgedTokensReceived(user, address(token), BRIDGED_AMOUNT);
        tokenKeeper.transferFromStargateReceiver(user, address(token), BRIDGED_AMOUNT);

        vm.stopPrank();
    }

    function test_SetsBalances() public {
        vm.startPrank(receiver);

        // we approve the token transfer
        token.approve(address(tokenKeeper), BRIDGED_AMOUNT);

        // receiver holds the balance
        assertTrue(token.balanceOf(receiver) == BRIDGED_AMOUNT);
        assertTrue(token.balanceOf(address(tokenKeeper)) == 0);

        tokenKeeper.transferFromStargateReceiver(user, address(token), BRIDGED_AMOUNT);

        // tokenKeeper now holds the tokens
        assertTrue(token.balanceOf(receiver) == 0);
        assertTrue(token.balanceOf(address(tokenKeeper)) == BRIDGED_AMOUNT);

        // balances storage variable is set
        assertTrue(tokenKeeper.balances(user, address(token)) == BRIDGED_AMOUNT);

        vm.stopPrank();
    }
}

contract PullToken is TokenKeeperTest {
    function test_RevertIf_NotZap() public {
        vm.expectRevert(Error.Unauthorized.selector);
        tokenKeeper.pullToken(address(token), user);
    }

    function test_RevertIf_TokenIsZero() public {
        vm.prank(zap);
        vm.expectRevert(Error.ZeroAddress.selector);
        tokenKeeper.pullToken(address(0), user);
    }

    function test_RevertIf_AccountIsZero() public {
        vm.prank(zap);
        vm.expectRevert(Error.ZeroAddress.selector);
        tokenKeeper.pullToken(address(token), address(0));
    }

    function test_RevertIf_AmountIsZero() public {
        vm.prank(zap);
        vm.expectRevert(Error.ZeroAmount.selector);
        tokenKeeper.pullToken(address(token), user);
    }

    function test_EmitsTokenTransferredEvent() public {
        // first we get the tokens from the receiver
        vm.startPrank(receiver);

        token.approve(address(tokenKeeper), BRIDGED_AMOUNT);
        tokenKeeper.transferFromStargateReceiver(user, address(token), BRIDGED_AMOUNT);

        vm.stopPrank();

        // then we pull the tokens to zap
        vm.prank(zap);
        vm.expectEmit(true, true, true, true);
        emit TokenTransferred(user, address(zap), address(token), BRIDGED_AMOUNT);
        tokenKeeper.pullToken(address(token), user);
    }

    function test_SetsBalances() public {
        // first we get the tokens from the receiver
        vm.startPrank(receiver);

        token.approve(address(tokenKeeper), BRIDGED_AMOUNT);
        tokenKeeper.transferFromStargateReceiver(user, address(token), BRIDGED_AMOUNT);

        vm.stopPrank();

        assertTrue(token.balanceOf(address(tokenKeeper)) == BRIDGED_AMOUNT);
        assertTrue(token.balanceOf(zap) == 0);
        assertTrue(tokenKeeper.balances(user, address(token)) == BRIDGED_AMOUNT);

        // then we pull the tokens to zap
        vm.prank(zap);
        tokenKeeper.pullToken(address(token), user);

        assertTrue(token.balanceOf(address(tokenKeeper)) == 0);
        assertTrue(token.balanceOf(zap) == BRIDGED_AMOUNT);
        assertTrue(tokenKeeper.balances(user, address(token)) == 0);
    }
}

contract Withdraw is TokenKeeperTest {
    function test_RevertIf_TokenIsZero() public {
        vm.expectRevert(Error.ZeroAddress.selector);
        tokenKeeper.withdraw(address(0));
    }

    function test_RevertIf_AmountIsZero() public {
        vm.prank(user);
        vm.expectRevert(Error.ZeroAmount.selector);
        tokenKeeper.withdraw(address(token));
    }

    function test_EmitsTokenWithdrawnEvent() public {
        // first we get the tokens from the receiver
        vm.startPrank(receiver);

        token.approve(address(tokenKeeper), BRIDGED_AMOUNT);
        tokenKeeper.transferFromStargateReceiver(user, address(token), BRIDGED_AMOUNT);

        vm.stopPrank();

        // then user withdraws
        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit TokenTransferred(user, user, address(token), BRIDGED_AMOUNT);
        tokenKeeper.withdraw(address(token));
    }

    function test_SetsBalances() public {
        // first we get the tokens from the receiver
        vm.startPrank(receiver);

        token.approve(address(tokenKeeper), BRIDGED_AMOUNT);
        tokenKeeper.transferFromStargateReceiver(user, address(token), BRIDGED_AMOUNT);

        vm.stopPrank();

        assertTrue(token.balanceOf(address(tokenKeeper)) == BRIDGED_AMOUNT);
        assertTrue(token.balanceOf(user) == 0);
        assertTrue(tokenKeeper.balances(user, address(token)) == BRIDGED_AMOUNT);

        // then user withdraws
        vm.prank(user);
        tokenKeeper.withdraw(address(token));

        assertTrue(token.balanceOf(address(tokenKeeper)) == 0);
        assertTrue(token.balanceOf(user) == BRIDGED_AMOUNT);
        assertTrue(tokenKeeper.balances(user, address(token)) == 0);
    }
}
