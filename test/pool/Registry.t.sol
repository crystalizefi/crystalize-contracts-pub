// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase,contract-name-camelcase,one-contract-per-file */
pragma solidity 0.8.19;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Test } from "forge-std/Test.sol";

import { Registry } from "src/pool/Registry.sol";
import { Pool } from "src/pool/Pool.sol";
import { Error } from "src/librairies/Error.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract RegistryTest is Test {
    address public poolFactory;
    address public owner;
    address public user;

    Registry public registry;
    Pool public pool;

    event FactorySet(address indexed oldFactory, address indexed newFactory);
    event PoolApproved(address indexed pool);
    event PoolPending(address indexed pool);
    event PoolRejected(address indexed pool);
    event PoolRemoved(address indexed pool);

    function setUp() public virtual {
        poolFactory = vm.addr(1);
        owner = vm.addr(2);
        user = vm.addr(3);

        registry = new Registry(owner);
        pool = new Pool(address(registry));
        vm.prank(owner);
        registry.setFactory(poolFactory);

        pool.initialize(
            address(1), address(2), address(new MockERC20("a", "aa")), 1 days, 1 days, 100e18, 1000, 1000e18
        );
    }
}

contract Constructor is RegistryTest {
    function test_SetsOwner() public {
        Registry _registry = new Registry(owner);
        assertTrue(_registry.owner() == owner);
    }

    function test_FactoryIsZero() public {
        Registry _registry = new Registry(owner);
        assertTrue(_registry.factory() == address(0));
    }
}

contract RegisterPool is RegistryTest {
    function test_RevertIf_FactoryNotSet() public {
        Registry _registry = new Registry(owner);
        vm.prank(user);
        vm.expectRevert(Error.Unauthorized.selector);
        _registry.registerPool(address(pool));
    }

    function test_RevertIf_CallerNotFactory() public {
        vm.prank(user);
        vm.expectRevert(Error.Unauthorized.selector);
        registry.registerPool(address(pool));
    }

    function test_RevertIf_PoolIsZero() public {
        vm.prank(poolFactory);
        vm.expectRevert(Error.ZeroAddress.selector);
        registry.registerPool(address(0));
    }

    function test_RevertIf_PoolAlreadyExists() public {
        vm.startPrank(poolFactory);
        registry.registerPool(address(pool));

        vm.expectRevert(Error.AddFailed.selector);
        registry.registerPool(address(pool));
        vm.stopPrank();
    }

    function test_EmitsPoolPendingWhen_PoolIsRegistered() public {
        vm.startPrank(poolFactory);
        vm.expectEmit(true, false, false, false);
        emit PoolPending(address(pool));
        registry.registerPool(address(pool));
        vm.stopPrank();
    }

    function test_SetsPendingPoolsWhen_PoolIsRegistered() public {
        vm.prank(poolFactory);
        registry.registerPool(address(pool));
        assertTrue(registry.hasPool(address(pool), true));
    }
}

contract ApprovePool is RegistryTest {
    function test_RevertIf_CallerNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        registry.approvePool(address(pool));
    }

    function test_RevertIf_PoolIsNotPendingForApproval() public {
        vm.prank(owner);
        vm.expectRevert(Error.RemoveFailed.selector);
        registry.approvePool(address(pool));
    }

    function test_RevertIf_PoolAlreadyApprovedButInTheSystem() public {
        // we register the pool first
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        // then we approve the pool
        vm.prank(owner);
        registry.approvePool(address(pool));

        // then we re-register the same pool
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        // and now approval should revert
        vm.prank(owner);
        vm.expectRevert(Error.AddFailed.selector);
        registry.approvePool(address(pool));
    }

    function test_RevertIf_PoolAlreadyApprovedButRemoved() public {
        // we register the pool first
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        // then we approve the pool
        vm.startPrank(owner);
        registry.approvePool(address(pool));
        registry.removePool(address(pool));
        vm.stopPrank();

        // then we re-register the same pool
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        // and now approval should revert
        vm.prank(owner);
        vm.expectRevert(Error.InvalidStatus.selector);
        registry.approvePool(address(pool));
    }

    function test_EmitsPoolApprovedWhen_PoolIsApproved() public {
        // we register the pool first
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        // then we approve the pool
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit PoolApproved(address(pool));
        registry.approvePool(address(pool));
    }

    function test_SetsPoolsWhen_PoolIsApproved() public {
        // we register the pool first
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        // then we approve the pool
        vm.prank(owner);
        registry.approvePool(address(pool));
        assertTrue(registry.hasPool(address(pool), false));
    }
}

contract RejectPool is RegistryTest {
    function test_RevertIf_CallerNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        registry.rejectPool(address(pool));
    }

    function test_RevertIf_PoolIsNotPendingForApproval() public {
        vm.prank(owner);
        vm.expectRevert(Error.RemoveFailed.selector);
        registry.rejectPool(address(pool));
    }

    function test_RevertIf_PoolAlreadyApprovedButRemoved() public {
        // we register the pool first
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        // then we approve the pool
        vm.startPrank(owner);
        registry.approvePool(address(pool));
        registry.removePool(address(pool));
        vm.stopPrank();

        // then we re-register the same pool
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        // and now approval should revert
        vm.prank(owner);
        vm.expectRevert(Error.InvalidStatus.selector);
        registry.rejectPool(address(pool));
    }

    function test_EmitsPoolRejectedWhen_PoolIsRejected() public {
        // we register the pool first
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        // then we reject the pool
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit PoolRejected(address(pool));
        registry.rejectPool(address(pool));
    }

    function test_SetsPendingPoolsWhen_PoolIsRejected() public {
        // we register the pool first
        vm.prank(poolFactory);
        registry.registerPool(address(pool));
        assertTrue(registry.hasPool(address(pool), true));

        // then we reject the pool
        vm.prank(owner);
        registry.rejectPool(address(pool));
        assertFalse(registry.hasPool(address(pool), true));
    }
}

contract RemovePool is RegistryTest {
    function test_RevertIf_CallerNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        registry.removePool(address(pool));
    }

    function test_RevertIf_PoolIsNotApproved() public {
        vm.prank(owner);
        vm.expectRevert(Error.RemoveFailed.selector);
        registry.removePool(address(pool));
    }

    function test_EmitsPoolRemovedWhen_PoolIsRemoved() public {
        // we register the pool first
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        // then we approve the pool
        vm.startPrank(owner);
        registry.approvePool(address(pool));

        // then we remove the pool
        vm.expectEmit(true, false, false, false);
        emit PoolRemoved(address(pool));
        registry.removePool(address(pool));
        vm.stopPrank();
    }

    function test_SetsPoolsWhen_PoolIsRemoved() public {
        // we register the pool first
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        // then we approve the pool
        vm.startPrank(owner);
        registry.approvePool(address(pool));
        assertTrue(registry.hasPool(address(pool), false));

        // then we remove the pool
        registry.removePool(address(pool));
        assertFalse(registry.hasPool(address(pool), false));
        vm.stopPrank();
    }
}

contract SetFactory is RegistryTest {
    function test_RevertIf_CallerNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        registry.setFactory(poolFactory);
    }

    function test_RevertIf_PoolIsZero() public {
        vm.prank(owner);
        vm.expectRevert(Error.ZeroAddress.selector);
        registry.setFactory(address(0));
    }

    function testFuzz_EmitsFactorySetWhen_FactoryIsSet(address _newFactory) public {
        vm.assume(_newFactory != address(0));
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit FactorySet(poolFactory, _newFactory);
        registry.setFactory(_newFactory);
    }

    function testFuzz_SetsFactoryAddressWhen_FactoryIsSet(address _newFactory) public {
        vm.assume(_newFactory != address(0));
        vm.assume(_newFactory != poolFactory);
        assertTrue(registry.factory() == poolFactory);
        vm.prank(owner);
        registry.setFactory(_newFactory);
        assertTrue(registry.factory() == _newFactory);
    }
}

contract GetPoolAt is RegistryTest {
    function testFuzz_RevertIf_WrongIndexInPendingPools(uint256 _index) public {
        vm.expectRevert();
        registry.getPoolAt(_index, true);
    }

    function testFuzz_RevertIf_WrongIndexInPools(uint256 _index) public {
        vm.expectRevert();
        registry.getPoolAt(_index, false);
    }

    function test_ReturnsPendingPoolAddressWhen_CorrectIndex() public {
        // we register the pool first
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        assertTrue(registry.getPoolAt(0, true) == address(pool));
    }

    function test_ReturnsPoolAddressWhen_CorrectIndex() public {
        // we register the pool first
        vm.prank(poolFactory);
        registry.registerPool(address(pool));

        // then we approve the pool
        vm.startPrank(owner);
        registry.approvePool(address(pool));

        assertTrue(registry.getPoolAt(0, false) == address(pool));
    }
}

contract GetPoolCount is RegistryTest {
    function test_ReturnsZeroWhen_NoPendingPools() public {
        assertTrue(registry.getPoolCount(true) == 0);
    }

    function test_ReturnsZeroWhen_NoPools() public {
        assertTrue(registry.getPoolCount(false) == 0);
    }

    function test_ReturnsPoolCountWhen_PendingPoolExists() public {
        // we register two pools
        vm.startPrank(poolFactory);
        registry.registerPool(address(pool));
        registry.registerPool(vm.addr(4));

        assertTrue(registry.getPoolCount(true) == 2);
        assertTrue(registry.getPoolCount(false) == 0);

        vm.stopPrank();
    }

    function test_ReturnsPoolCountWhen_PoolExists() public {
        // we register one pool
        vm.startPrank(poolFactory);
        registry.registerPool(address(pool));
        // we approve the pool
        vm.stopPrank();
        vm.startPrank(owner);
        registry.approvePool(address(pool));

        assertTrue(registry.getPoolCount(true) == 0);
        assertTrue(registry.getPoolCount(false) == 1);

        vm.stopPrank();
    }
}

contract HasPool is RegistryTest {
    function test_ReturnsFalseWhen_PendingPoolIsNotFound() public {
        assertFalse(registry.hasPool(address(pool), true));
    }

    function test_ReturnsFalseWhen_PoolIsNotFound() public {
        assertFalse(registry.hasPool(address(pool), false));
    }

    function test_ReturnsTrueWhen_PendingPoolIsFound() public {
        // we register one pool
        vm.prank(poolFactory);
        registry.registerPool(address(pool));
        assertTrue(registry.hasPool(address(pool), true));
        assertFalse(registry.hasPool(address(pool), false));
    }

    function test_ReturnsTrueWhen_PoolIsFound() public {
        // we register one pool
        vm.prank(poolFactory);
        registry.registerPool(address(pool));
        // we approve the pool
        vm.prank(owner);
        registry.approvePool(address(pool));

        assertTrue(registry.hasPool(address(pool), false));
        assertFalse(registry.hasPool(address(pool), true));
    }
}
