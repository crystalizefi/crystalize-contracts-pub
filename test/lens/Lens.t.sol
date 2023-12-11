// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase,contract-name-camelcase,one-contract-per-file */
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";

import { Registry } from "src/pool/Registry.sol";
import { Lens } from "src/lens/Lens.sol";
import { Pool } from "src/pool/Pool.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract LensTest is Test {
    address public poolFactory;
    address public owner;
    address public user;

    address public poolCreator;

    Registry public registry;
    Pool public pool1;
    Pool public pool2;
    Lens public lens;

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
        pool1 = new Pool(address(registry));
        pool2 = new Pool(address(registry));
        vm.prank(owner);
        registry.setFactory(poolFactory);

        lens = new Lens(registry);

        poolCreator = vm.addr(9);
    }
}

contract Constructor is LensTest {
    function test_RegistryIsConfigured() public {
        assertTrue(address(lens.registry()) == address(registry));
    }
}

contract QueryPoolData is LensTest {
    function setUp() public virtual override {
        super.setUp();

        pool1.initialize(
            poolCreator, vm.addr(10), address(new MockERC20("1name", "1")), 10_000, 10_000, 10e18, 500, 900e18
        );

        pool2.initialize(
            poolCreator, vm.addr(10), address(new MockERC20("2name", "2")), 10_000, 10_000, 10e18, 500, 900e18
        );

        vm.startPrank(poolFactory);
        registry.registerPool(address(pool1));
        registry.registerPool(address(pool2));
        vm.stopPrank();
    }

    function test_QueriesPendingPoolData() public {
        Lens.PoolData[] memory poolData = lens.getPoolData(true);
        assertEq(poolData.length, 2);

        Lens.PoolData[] memory approvedPoolData = lens.getPoolData(false);
        assertEq(approvedPoolData.length, 0);
    }

    function test_QueriesApprovedPoolData() public {
        vm.prank(owner);
        registry.approvePool(address(pool1));

        vm.prank(poolCreator);
        pool1.start();

        Lens.PoolData[] memory poolData = lens.getPoolData(true);
        assertEq(poolData.length, 1);
        assertEq(poolData[0].tokenSymbol, "2");

        Lens.PoolData[] memory approvedPoolData = lens.getPoolData(false);
        assertEq(approvedPoolData.length, 1);
        assertEq(approvedPoolData[0].tokenSymbol, "1");
    }
}

contract UserQueryDataTests is LensTest {
    function setUp() public virtual override {
        super.setUp();

        pool1.initialize(
            poolCreator, vm.addr(10), address(new MockERC20("1name", "1")), 10_000, 10_000, 10e18, 500, 900e18
        );

        pool2.initialize(
            poolCreator, vm.addr(10), address(new MockERC20("2name", "2")), 10_000, 10_000, 10e18, 500, 900e18
        );

        vm.startPrank(poolFactory);
        registry.registerPool(address(pool1));
        registry.registerPool(address(pool2));
        vm.stopPrank();

        vm.prank(owner);
        registry.approvePool(address(pool1));

        vm.prank(poolCreator);
        pool1.start();

        address pool1Token = address(pool1.token());
        deal(pool1Token, user, 100);

        vm.startPrank(user);
        MockERC20(pool1Token).approve(address(pool1), 100);
        pool1.stake(100);
        vm.stopPrank();
    }

    function test_PoolDataIncludesUserData() public {
        Lens.PoolData[] memory approvedPoolData = lens.getPoolData(false, user);
        assertEq(approvedPoolData.length, 1);
        assertEq(approvedPoolData[0].queriedUserBalance, 100);
        assertEq(approvedPoolData[0].queriedUserBalanceLocked, 100);
    }

    function test_PoolDataIsEmptyWhenPendingUserData() public {
        Lens.PoolData[] memory approvedPoolData = lens.getPoolData(true, user);
        assertEq(approvedPoolData.length, 1);
        assertEq(approvedPoolData[0].queriedUserBalance, 0);
        assertEq(approvedPoolData[0].queriedUserBalanceLocked, 0);
    }

    function test_PoolDataIncludesUserDataUserZero() public {
        Lens.PoolData[] memory approvedPoolData = lens.getPoolData(false, address(0));
        assertEq(approvedPoolData.length, 1);
        assertEq(approvedPoolData[0].queriedUserBalance, 0);
        assertEq(approvedPoolData[0].queriedUserBalanceLocked, 0);
    }

    function test_PoolDataIsEmptyWhenPendingUserDataUserZero() public {
        Lens.PoolData[] memory approvedPoolData = lens.getPoolData(true, address(0));
        assertEq(approvedPoolData.length, 1);
        assertEq(approvedPoolData[0].queriedUserBalance, 0);
        assertEq(approvedPoolData[0].queriedUserBalanceLocked, 0);
    }
}
