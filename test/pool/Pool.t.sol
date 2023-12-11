// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase,contract-name-camelcase,one-contract-per-file */
pragma solidity 0.8.19;

import { IERC20Errors } from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

import { Test } from "forge-std/Test.sol";
import { Pool, IPool } from "src/pool/Pool.sol";

import { Error } from "src/librairies/Error.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";

contract PoolTest is Test {
    address public registry;
    address public staker;
    Pool public pool;
    MockERC20 public token;

    uint256 public constant SEEDING_PERIOD = 10 days;
    uint256 public constant LOCK_PERIOD = 10 days;
    uint256 public constant MAX_STAKE_PER_ADDRESS = 500 * 1e18;
    uint256 public constant MAX_STAKE_PER_POOL = MAX_STAKE_PER_ADDRESS * 10;

    // 100 tokens with 18 decimals
    uint256 public constant DEFAULT_AMOUNT = 100 * 1e18;
    uint256 public constant DEFAULT_REWARD_AMOUNT = 100 * 1e18;
    uint256 public constant DEFAULT_PROTOCOL_FEE = 500;

    /// @notice The maximum amount the protocol fee can be set to. 10,000 bps is 100%.
    uint256 public constant MAX_PCT = 10_000;

    event PoolInitialized(
        address indexed token,
        address indexed creator,
        uint256 seedingPeriod,
        uint256 lockPeriod,
        uint256 amount,
        uint256 fee,
        uint256 maxStakePerAddress,
        uint256 maxStakePerPool
    );
    event PoolApproved();
    event PoolRejected();
    event PoolStarted(uint256 seedingStart, uint256 periodFinish);
    event RewardsRetrieved(address indexed creator, uint256 amount);
    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    event RewardPaid(address indexed account, uint256 amount);
    event ProtocolFeePaid(address indexed treasury, uint256 amount);

    function setUp() public {
        registry = vm.addr(1);
        staker = vm.addr(2);
        token = new MockERC20("CRYSTALIZE", "CRYSTL");

        token.mint(staker, DEFAULT_AMOUNT);
        token.mint(address(this), DEFAULT_AMOUNT);

        pool = new Pool(registry);
        token.transfer(address(pool), DEFAULT_AMOUNT);
        pool.initialize(
            address(this),
            address(this),
            address(token),
            SEEDING_PERIOD,
            LOCK_PERIOD,
            MAX_STAKE_PER_ADDRESS,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_POOL
        );

        vm.label(registry, "registry");
        vm.label(address(pool), "pool");
        vm.label(address(token), "token");
        vm.label(address(this), "test");
    }

    /// @dev A helper function to stake tokens in the pool.
    function _stake(address account, uint256 amount) internal {
        vm.startPrank(account);
        token.approve(address(pool), amount);
        pool.stake(amount);
        vm.stopPrank();
    }

    function _goToUnlockedPeriod() internal {
        vm.warp(block.timestamp + SEEDING_PERIOD + LOCK_PERIOD + 1 days);
    }
}

contract Constructor is PoolTest {
    function test_RevertIf_RegistryIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroAddress.selector));
        new Pool(address(0));
    }

    function test_SetsRegistryIf_Deployed() public {
        Pool pool = new Pool(registry);
        assertTrue(pool.registry() == registry);
    }
}

contract Initialize is PoolTest {
    function test_RevertIf_CreatorIsZeroAddress() public {
        Pool _pool = new Pool(registry);
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroAddress.selector));
        _pool.initialize(
            address(0),
            address(this),
            address(token),
            SEEDING_PERIOD,
            LOCK_PERIOD,
            MAX_STAKE_PER_ADDRESS,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_POOL
        );
    }

    function test_RevertIf_TreasuryIsZeroAddress() public {
        Pool _pool = new Pool(registry);
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroAddress.selector));
        _pool.initialize(
            address(this),
            address(0),
            address(token),
            SEEDING_PERIOD,
            LOCK_PERIOD,
            MAX_STAKE_PER_ADDRESS,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_POOL
        );
    }

    function test_RevertIf_TokenIsZeroAddress() public {
        Pool _pool = new Pool(registry);
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroAddress.selector));
        _pool.initialize(
            address(this),
            registry,
            address(0),
            SEEDING_PERIOD,
            LOCK_PERIOD,
            MAX_STAKE_PER_ADDRESS,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_POOL
        );
    }

    function test_RevertIf_SeedingPeriodIsZero() public {
        Pool _pool = new Pool(registry);
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroAmount.selector));
        _pool.initialize(
            address(this),
            registry,
            address(token),
            0,
            LOCK_PERIOD,
            MAX_STAKE_PER_ADDRESS,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_POOL
        );
    }

    function test_RevertIf_LockPeriodIsZero() public {
        Pool _pool = new Pool(registry);
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroAmount.selector));
        _pool.initialize(
            address(this),
            registry,
            address(token),
            SEEDING_PERIOD,
            0,
            MAX_STAKE_PER_ADDRESS,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_POOL
        );
    }

    function test_RevertIf_MaxStakePerAddressIsZero() public {
        Pool _pool = new Pool(registry);
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroAmount.selector));
        _pool.initialize(
            address(this),
            registry,
            address(token),
            SEEDING_PERIOD,
            LOCK_PERIOD,
            0,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_POOL
        );
    }

    function test_RevertIf_MaxStakePerPoolIsLowerThanMaxStakePerAddress() public {
        Pool _pool = new Pool(registry);
        vm.expectRevert(abi.encodeWithSelector(IPool.StakeLimitMismatch.selector));
        _pool.initialize(
            address(this),
            registry,
            address(token),
            SEEDING_PERIOD,
            LOCK_PERIOD,
            MAX_STAKE_PER_ADDRESS,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_ADDRESS - 1
        );
    }

    function test_EmitPoolInitializedEvent() public {
        token.mint(address(this), DEFAULT_REWARD_AMOUNT);
        Pool _pool = new Pool(registry);
        token.transfer(address(_pool), DEFAULT_REWARD_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit PoolInitialized(
            address(token),
            address(this),
            SEEDING_PERIOD,
            LOCK_PERIOD,
            DEFAULT_REWARD_AMOUNT,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_ADDRESS,
            MAX_STAKE_PER_POOL
        );
        _pool.initialize(
            address(this),
            address(this),
            address(token),
            SEEDING_PERIOD,
            LOCK_PERIOD,
            MAX_STAKE_PER_ADDRESS,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_POOL
        );
    }

    function test_SetCreatedStatus() public {
        token.mint(address(this), DEFAULT_REWARD_AMOUNT);
        Pool _pool = new Pool(registry);
        token.transfer(address(_pool), DEFAULT_REWARD_AMOUNT);
        _pool.initialize(
            address(this),
            address(this),
            address(token),
            SEEDING_PERIOD,
            LOCK_PERIOD,
            MAX_STAKE_PER_ADDRESS,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_POOL
        );
        assertTrue(_pool.status() == IPool.Status.Created);
    }

    function test_SetRewardAmount() public {
        token.mint(address(this), DEFAULT_REWARD_AMOUNT);
        Pool _pool = new Pool(registry);
        token.transfer(address(_pool), DEFAULT_REWARD_AMOUNT);
        _pool.initialize(
            address(this),
            address(this),
            address(token),
            SEEDING_PERIOD,
            LOCK_PERIOD,
            MAX_STAKE_PER_ADDRESS,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_POOL
        );
        uint256 rewardAmount = DEFAULT_REWARD_AMOUNT - ((DEFAULT_REWARD_AMOUNT * DEFAULT_PROTOCOL_FEE) / MAX_PCT);
        assertTrue(_pool.rewardAmount() == rewardAmount);
    }

    function test_SetFeeAmount() public {
        token.mint(address(this), DEFAULT_REWARD_AMOUNT);
        Pool _pool = new Pool(registry);
        token.transfer(address(_pool), DEFAULT_REWARD_AMOUNT);
        _pool.initialize(
            address(this),
            address(this),
            address(token),
            SEEDING_PERIOD,
            LOCK_PERIOD,
            MAX_STAKE_PER_ADDRESS,
            DEFAULT_PROTOCOL_FEE,
            MAX_STAKE_PER_POOL
        );
        uint256 feeAmount = (DEFAULT_REWARD_AMOUNT * DEFAULT_PROTOCOL_FEE) / MAX_PCT;
        assertTrue(_pool.feeAmount() == feeAmount);
    }
}

contract ApprovePool is PoolTest {
    function test_RevertIf_CallerIsNotRegistry() public {
        vm.expectRevert(abi.encodeWithSelector(Error.Unauthorized.selector));
        pool.approvePool();
    }

    function test_RevertIf_PoolIsNotInitialized() public {
        Pool p = new Pool(registry);
        assertEq(uint256(p.status()), uint256(IPool.Status.Uninitialized));

        vm.startPrank(registry);
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidStatus.selector));
        p.approvePool();
        vm.stopPrank();
    }

    function test_RevertIf_PoolAlreadyApproved() public {
        vm.startPrank(registry);
        pool.approvePool();

        assertEq(uint256(pool.status()), uint256(IPool.Status.Approved));
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidStatus.selector));
        pool.approvePool();
        vm.stopPrank();
    }

    function test_RevertIf_AlreadyRejected() public {
        vm.startPrank(registry);
        pool.rejectPool();

        assertEq(uint256(pool.status()), uint256(IPool.Status.Rejected));
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidStatus.selector));
        pool.approvePool();
        vm.stopPrank();
    }

    function test_RevertIf_SeedingAlreadyStarted() public {
        vm.prank(registry);
        pool.approvePool();

        pool.start();

        vm.startPrank(registry);
        assertEq(uint256(pool.status()), uint256(IPool.Status.Seeding));
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidStatus.selector));
        pool.approvePool();
        vm.stopPrank();
    }

    function test_RevertIf_DuringLockPeriod() public {
        vm.prank(registry);
        pool.approvePool();

        pool.start();

        vm.warp(block.timestamp + SEEDING_PERIOD + (LOCK_PERIOD / 2));

        vm.startPrank(registry);
        assertEq(uint256(pool.status()), uint256(IPool.Status.Locked));
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidStatus.selector));
        pool.approvePool();
        vm.stopPrank();
    }

    function test_RevertIf_DuringUnlockedPeriod() public {
        vm.prank(registry);
        pool.approvePool();

        pool.start();

        vm.warp(block.timestamp + SEEDING_PERIOD + LOCK_PERIOD * 2);

        vm.startPrank(registry);
        assertEq(uint256(pool.status()), uint256(IPool.Status.Unlocked));
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidStatus.selector));
        pool.approvePool();
        vm.stopPrank();
    }

    function test_UpdatePoolStatus() public {
        assertEq(uint256(pool.status()), uint256(IPool.Status.Created));

        vm.prank(registry);
        pool.approvePool();

        assertTrue(pool.status() == IPool.Status.Approved);
    }

    function test_EmitPoolApprovedEvent() public {
        vm.prank(registry);

        vm.expectEmit(true, true, true, true);
        emit PoolApproved();

        pool.approvePool();
    }
}

contract RejectPool is PoolTest {
    function test_RevertIf_CallerIsNotRegistry() public {
        vm.expectRevert(abi.encodeWithSelector(Error.Unauthorized.selector));
        pool.rejectPool();
    }

    function test_RevertIf_PoolIsNotInitialized() public {
        Pool p = new Pool(registry);
        assertEq(uint256(p.status()), uint256(IPool.Status.Uninitialized));

        vm.startPrank(registry);
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidStatus.selector));
        p.rejectPool();
        vm.stopPrank();
    }

    function test_RevertIf_PoolAlreadyRejected() public {
        vm.startPrank(registry);
        pool.rejectPool();

        assertEq(uint256(pool.status()), uint256(IPool.Status.Rejected));
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidStatus.selector));
        pool.rejectPool();
        vm.stopPrank();
    }

    function test_RevertIf_AlreadyApproved() public {
        vm.startPrank(registry);
        pool.approvePool();

        assertEq(uint256(pool.status()), uint256(IPool.Status.Approved));
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidStatus.selector));
        pool.rejectPool();
        vm.stopPrank();
    }

    function test_RevertIf_SeedingAlreadyStarted() public {
        vm.prank(registry);
        pool.approvePool();

        pool.start();

        vm.startPrank(registry);
        assertEq(uint256(pool.status()), uint256(IPool.Status.Seeding));
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidStatus.selector));
        pool.rejectPool();
        vm.stopPrank();
    }

    function test_RevertIf_DuringLockPeriod() public {
        vm.prank(registry);
        pool.approvePool();

        pool.start();

        vm.warp(block.timestamp + SEEDING_PERIOD + (LOCK_PERIOD / 2));

        vm.startPrank(registry);
        assertEq(uint256(pool.status()), uint256(IPool.Status.Locked));
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidStatus.selector));
        pool.rejectPool();
        vm.stopPrank();
    }

    function test_RevertIf_DuringUnlockedPeriod() public {
        vm.prank(registry);
        pool.approvePool();

        pool.start();

        vm.warp(block.timestamp + SEEDING_PERIOD + LOCK_PERIOD * 2);

        vm.startPrank(registry);
        assertEq(uint256(pool.status()), uint256(IPool.Status.Unlocked));
        vm.expectRevert(abi.encodeWithSelector(Error.InvalidStatus.selector));
        pool.rejectPool();
        vm.stopPrank();
    }

    function test_UpdatePoolStatus() public {
        vm.prank(registry);
        pool.rejectPool();

        assertTrue(pool.status() == IPool.Status.Rejected);
    }

    function test_EmitPoolRejectedEvent() public {
        vm.prank(registry);

        vm.expectEmit(true, true, true, true);
        emit PoolRejected();

        pool.rejectPool();
    }
}

contract RetrieveRewardToken is PoolTest {
    function test_RevertIf_CallerIsNotCreator() public {
        vm.expectRevert(abi.encodeWithSelector(Error.Unauthorized.selector));
        vm.prank(address(0));
        pool.retrieveRewardToken();
    }

    function test_RevertIf_PoolNotRejected() public {
        vm.expectRevert(abi.encodeWithSelector(Error.PoolNotRejected.selector));
        pool.retrieveRewardToken();
    }

    function test_TransferRewardTokensToCreator() public {
        vm.prank(registry);
        pool.rejectPool();

        uint256 balanceBefore = token.balanceOf(address(this));
        pool.retrieveRewardToken();
        uint256 balanceAfter = token.balanceOf(address(this));

        assertTrue(balanceAfter - balanceBefore == DEFAULT_AMOUNT);
    }

    function test_EmitRewardsRetrievedEvent() public {
        vm.prank(registry);
        pool.rejectPool();

        vm.expectEmit(true, true, true, true);
        emit RewardsRetrieved(address(this), DEFAULT_AMOUNT);

        pool.retrieveRewardToken();
    }

    function test_ResetFeeAndRewardAmount() public {
        vm.prank(registry);
        pool.rejectPool();

        assertFalse(pool.feeAmount() == 0);
        assertFalse(pool.rewardAmount() == 0);

        pool.retrieveRewardToken();

        assertTrue(pool.feeAmount() == 0);
        assertTrue(pool.rewardAmount() == 0);
    }
}

contract Start is PoolTest {
    function test_RevertIf_CallerIsNotCreator() public {
        vm.expectRevert(abi.encodeWithSelector(Error.Unauthorized.selector));
        vm.prank(address(0));
        pool.start();
    }

    function test_RevertIf_PoolNotApproved() public {
        vm.expectRevert(abi.encodeWithSelector(Error.PoolNotApproved.selector));
        pool.start();
    }

    function test_EmitPoolStartedEvent() public {
        vm.prank(registry);
        pool.approvePool();

        vm.expectEmit(true, true, true, true);
        emit PoolStarted(block.timestamp, block.timestamp + SEEDING_PERIOD + LOCK_PERIOD);

        pool.start();
    }

    function test_TransferProtocolFee() public {
        vm.prank(registry);
        pool.approvePool();

        vm.expectEmit(true, false, false, true);

        assertTrue(token.balanceOf(address(this)) == 0);
        uint256 rewardAmount = (DEFAULT_REWARD_AMOUNT * DEFAULT_PROTOCOL_FEE) / MAX_PCT;
        emit ProtocolFeePaid(address(this), rewardAmount);
        pool.start();
        assertTrue(token.balanceOf(address(this)) == rewardAmount);
    }
}

contract Stake is PoolTest {
    function test_RevertIf_NotInSeedingPeriod() public {
        vm.expectRevert(abi.encodeWithSelector(Error.DepositsDisabled.selector));

        pool.stake(10);
    }

    function test_RevertIf_AmountIsZero() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        vm.expectRevert(abi.encodeWithSelector(Error.ZeroAmount.selector));
        pool.stake(0);
    }

    function test_RevertIf_NotAllowance() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(pool), 0, DEFAULT_AMOUNT)
        );
        pool.stake(DEFAULT_AMOUNT);
    }

    function test_RevertIf_MaxStakePerPoolExceeded() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        // max out the pool
        uint256 stakersCount = MAX_STAKE_PER_POOL / MAX_STAKE_PER_ADDRESS;
        for (uint256 i = 0; i < stakersCount; i++) {
            address tempStaker = vm.addr(10_000 + i);
            token.mint(tempStaker, MAX_STAKE_PER_ADDRESS);

            vm.startPrank(tempStaker);
            token.approve(address(pool), MAX_STAKE_PER_ADDRESS);
            pool.stake(MAX_STAKE_PER_ADDRESS);
            vm.stopPrank();
        }

        // try to stake more than max stake per pool
        vm.startPrank(staker);
        token.approve(address(pool), DEFAULT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(Error.MaxStakePerPoolExceeded.selector));
        pool.stake(DEFAULT_AMOUNT);
        vm.stopPrank();
    }

    function test_RevertIf_MaxStakePerAddressExceeded() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        vm.startPrank(staker);
        token.approve(address(pool), DEFAULT_AMOUNT);

        // start with staking a small amount
        pool.stake(DEFAULT_AMOUNT);

        // try to stake more than max stake per address
        vm.expectRevert(abi.encodeWithSelector(Error.MaxStakePerAddressExceeded.selector));
        pool.stake(MAX_STAKE_PER_ADDRESS);
        vm.stopPrank();
    }

    function test_EmitStakedEvent() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        vm.startPrank(staker);
        token.approve(address(pool), DEFAULT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit Staked(staker, DEFAULT_AMOUNT);

        pool.stake(DEFAULT_AMOUNT);
        vm.stopPrank();
    }

    function test_OnlyUpdateStakersCountForNewStakers() public {
        // send more tokens to staker
        token.mint(staker, DEFAULT_AMOUNT);

        // start the pool
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        // stake
        vm.startPrank(staker);
        token.approve(address(pool), DEFAULT_AMOUNT);
        pool.stake(DEFAULT_AMOUNT);
        vm.stopPrank();

        // check stakers count has increased
        assertTrue(pool.stakersCount() == 1);

        // try to stake again
        vm.startPrank(staker);
        token.approve(address(pool), DEFAULT_AMOUNT);
        pool.stake(DEFAULT_AMOUNT);
        vm.stopPrank();

        // check stakers count is still the same
        assertTrue(pool.stakersCount() == 1);

        // stake with another address
        address staker2 = vm.addr(3);
        token.mint(staker2, DEFAULT_AMOUNT);
        vm.startPrank(staker2);
        token.approve(address(pool), DEFAULT_AMOUNT);
        pool.stake(DEFAULT_AMOUNT);
        vm.stopPrank();

        // check stakers count has increased
        assertTrue(pool.stakersCount() == 2);
    }

    function test_UpdateTotalSupplyAndUserBalance() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        uint256 balanceBefore = token.balanceOf(staker);

        vm.startPrank(staker);
        token.approve(address(pool), DEFAULT_AMOUNT);
        pool.stake(DEFAULT_AMOUNT);
        vm.stopPrank();

        uint256 balanceAfter = token.balanceOf(staker);

        assertTrue(pool.totalSupply() == DEFAULT_AMOUNT);
        assertTrue(pool.balances(staker) == DEFAULT_AMOUNT);
        assertTrue(balanceBefore - balanceAfter == DEFAULT_AMOUNT);
    }
}

/// Since stake() and stakeFor() are using the same internal stake function,
/// there is no need to duplicate the tests here
contract StakeFor is PoolTest {
    function test_RevertIf_StakerIsZero() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        vm.expectRevert(abi.encodeWithSelector(Error.ZeroAddress.selector));
        pool.stakeFor(address(0), DEFAULT_AMOUNT);
    }

    function test_UpdateTotalSupplyAndUserBalance() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        token.mint(address(this), DEFAULT_AMOUNT);
        uint256 balanceBefore = token.balanceOf(address(this));

        vm.startPrank(address(this));
        token.approve(address(pool), DEFAULT_AMOUNT);
        pool.stakeFor(staker, DEFAULT_AMOUNT);
        vm.stopPrank();

        uint256 balanceAfter = token.balanceOf(address(this));

        assertTrue(pool.totalSupply() == DEFAULT_AMOUNT);
        assertTrue(pool.balances(staker) == DEFAULT_AMOUNT);
        assertTrue(balanceBefore - balanceAfter == DEFAULT_AMOUNT);
    }
}

contract Unstake is PoolTest {
    function test_RevertIf_NotInUnlockedPeriod() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        vm.startPrank(staker);
        token.approve(address(pool), DEFAULT_AMOUNT);
        pool.stake(DEFAULT_AMOUNT);

        uint256 blockTime = block.timestamp;

        // try unstakeAll during seeding period
        vm.warp(blockTime + SEEDING_PERIOD - 1 days);
        vm.expectRevert(abi.encodeWithSelector(Error.WithdrawalsDisabled.selector));
        pool.unstakeAll();

        // try unstakeAll during locking period
        vm.warp(blockTime + SEEDING_PERIOD + 1 days);
        vm.expectRevert(abi.encodeWithSelector(Error.WithdrawalsDisabled.selector));
        pool.unstakeAll();

        vm.stopPrank();
    }

    function test_RevertIf_StakedAmountIsZero() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        _goToUnlockedPeriod();

        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroAmount.selector));
        pool.unstakeAll();
    }

    function test_TransferTokensAfterLockingPeriod() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        vm.startPrank(staker);
        token.approve(address(pool), DEFAULT_AMOUNT);
        pool.stake(DEFAULT_AMOUNT);

        _goToUnlockedPeriod();

        uint256 balanceBefore = token.balanceOf(staker);
        pool.unstakeAll();
        uint256 balanceAfter = token.balanceOf(staker);

        assertTrue(balanceAfter - balanceBefore == DEFAULT_AMOUNT);
        vm.stopPrank();
    }

    function test_DoNotUpdateLockedTotalSupplyAndUserBalanceWhen_InUnlockedPeriod() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        vm.startPrank(staker);
        token.approve(address(pool), DEFAULT_AMOUNT);
        pool.stake(DEFAULT_AMOUNT);

        _goToUnlockedPeriod();

        uint256 totalSupplyLockedBefore = pool.totalSupplyLocked();
        uint256 totalSupplyBefore = pool.totalSupply();

        uint256 balanceLockedBefore = pool.balancesLocked(staker);
        uint256 balanceBefore = pool.balances(staker);

        pool.unstakeAll();

        uint256 totalSupplyLockedAfter = pool.totalSupplyLocked();
        uint256 totalSupplyAfter = pool.totalSupply();

        uint256 balanceLockedAfter = pool.balancesLocked(staker);
        uint256 balanceAfter = pool.balances(staker);

        vm.stopPrank();

        assertTrue(totalSupplyLockedBefore == totalSupplyLockedAfter);
        assertTrue(totalSupplyBefore - DEFAULT_AMOUNT == totalSupplyAfter);

        assertTrue(balanceLockedBefore == balanceLockedAfter);
        assertTrue(balanceBefore - DEFAULT_AMOUNT == balanceAfter);
    }

    function test_EmitUnstakedEvent() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        vm.startPrank(staker);
        token.approve(address(pool), DEFAULT_AMOUNT);
        pool.stake(DEFAULT_AMOUNT);

        _goToUnlockedPeriod();

        vm.expectEmit(true, true, true, true);
        emit Unstaked(staker, DEFAULT_AMOUNT);
        pool.unstakeAll();

        vm.stopPrank();
    }
}

contract Status is PoolTest {
    function test_ReturnsUninitializedWhen_PoolIsNotInitializedYet() public {
        Pool _pool = new Pool(registry);
        assertTrue(_pool.status() == IPool.Status.Uninitialized);
    }

    function test_ReturnsCreatedWhen_PoolIsInitializedYet() public {
        assertTrue(pool.status() == IPool.Status.Created);
    }

    function test_ReturnsApprovedWhen_PoolIsApproved() public {
        vm.prank(registry);
        pool.approvePool();
        assertTrue(pool.status() == IPool.Status.Approved);
    }

    function test_ReturnsRejectedWhen_PoolIsRejected() public {
        vm.prank(registry);
        pool.rejectPool();
        assertTrue(pool.status() == IPool.Status.Rejected);
    }

    function test_ReturnsSeedingWhen_PoolIsStarted() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();
        assertTrue(pool.status() == IPool.Status.Seeding);
    }

    function test_ReturnsLockedWhen_PoolIsAfterSeedingPeriod() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();
        vm.warp(block.timestamp + SEEDING_PERIOD + 1 days);
        assertTrue(pool.status() == IPool.Status.Locked);
    }

    function test_ReturnsUnlockedWhen_PoolIsAfterLockPeriod() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();
        vm.warp(block.timestamp + SEEDING_PERIOD + LOCK_PERIOD + 1 days);
        assertTrue(pool.status() == IPool.Status.Unlocked);
    }
}

contract LastTimeRewardApplicable is PoolTest {
    function test_ReturnsPeriodFinishTimestampIf_PoolIsAfterLockedPeriod() public {
        uint256 periodFinish = block.timestamp + SEEDING_PERIOD + LOCK_PERIOD;

        vm.prank(registry);
        pool.approvePool();
        pool.start();

        vm.warp(block.timestamp + 100 days);

        assertTrue(pool.lastTimeRewardApplicable() == periodFinish);
    }

    function test_ReturnsCurrentTimestampIf_PoolIsAfterLockedPeriod() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        assertTrue(pool.lastTimeRewardApplicable() == block.timestamp);
    }

    function test_ZeroIf_PoolIsNotApproved() public {
        assertTrue(pool.lastTimeRewardApplicable() == 0);
    }

    function test_ZeroIf_PoolIsNotStarted() public {
        vm.prank(registry);
        pool.approvePool();

        assertTrue(pool.lastTimeRewardApplicable() == 0);
    }
}

contract Earned is PoolTest {
    function test_ZeroIf_PoolIsNotInLockedPeriod() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        // we need to stake some tokens to make sure that the pool is not empty
        _stake(staker, DEFAULT_AMOUNT);

        // ⌛️ got to the middle of the seeding period
        vm.warp(block.timestamp + (SEEDING_PERIOD / 2));

        assertTrue(pool.earned(staker) == 0);
    }

    /**
     * @dev Running the following scenario:
     * 0. The pool is initialized with 100 reward tokens
     * 1. Staker1 stakes 100 tokens
     * 2. Staker2 stakes 100 tokens
     * 3. Total supply is 200 tokens
     * 4. Halfway through the lock period
     * 5. At this point, Staker1 should have half of half of the rewards
     *    (Each staker has half of the total supply, and we are at the midpoint of the lock period)
     */

    function test_ReturnEarnedRewards() public {
        vm.prank(registry);
        pool.approvePool();
        pool.start();

        // first staker
        _stake(staker, DEFAULT_AMOUNT);

        // second staker
        address staker2 = address(10);
        token.mint(staker2, DEFAULT_AMOUNT);
        _stake(staker2, DEFAULT_AMOUNT);

        // ⌛️ go to the middle of the locked period
        vm.warp(block.timestamp + SEEDING_PERIOD + (LOCK_PERIOD / 2));

        uint256 earned = pool.earned(staker);
        uint256 rewardAmount = DEFAULT_REWARD_AMOUNT - ((DEFAULT_REWARD_AMOUNT * DEFAULT_PROTOCOL_FEE) / MAX_PCT);
        assertTrue(earned == (rewardAmount / 2 / 2));
    }
}

contract Claim is PoolTest {
    /**
     * @dev Executing the following scenario:
     * 0. The pool is initialized with 100 reward tokens.
     * 1. Staker stakes 100 tokens.
     * 2. Staker2 stakes 100 tokens.
     * 3. The total supply is 200 tokens.
     * 4. Time progresses to the middle of the lock period.
     * 5. Staker claims rewards and should receive half of the total rewards at this point
     *    (Since each staker has half of the total supply, and we are at the midpoint of the locked period).
     * 6. Time progresses to the end of the locked period.
     * 7. Staker claims rewards again and should finally receive the remaining half of the rewards
     *    (As each staker has half of the total supply, and we are at the end of the locked period).
     */
    function test_ClaimRewards() public {
        vm.prank(registry);
        pool.approvePool();

        pool.start();

        // first staker
        _stake(staker, DEFAULT_AMOUNT);

        // second staker
        address staker2 = address(10);
        token.mint(staker2, DEFAULT_AMOUNT);
        _stake(staker2, DEFAULT_AMOUNT);

        uint256 blockTime = block.timestamp;
        uint256 balanceStart = token.balanceOf(staker);

        // ⌛️ go to the middle of the locked period
        vm.warp(blockTime + SEEDING_PERIOD + (LOCK_PERIOD / 2));

        vm.prank(staker);
        pool.claim();
        uint256 balanceAtTheMiddle = token.balanceOf(staker);

        // ⌛️ go beyond the end of the locked period
        vm.warp(blockTime + SEEDING_PERIOD + LOCK_PERIOD + 1 days);

        vm.prank(staker);
        pool.claim();

        uint256 balanceAtTheEnd = token.balanceOf(staker);
        uint256 rewardAmount = DEFAULT_REWARD_AMOUNT - ((DEFAULT_REWARD_AMOUNT * DEFAULT_PROTOCOL_FEE) / MAX_PCT);

        assertTrue(balanceAtTheMiddle - balanceStart == (rewardAmount / 2 / 2));
        assertTrue(balanceAtTheEnd - balanceAtTheMiddle == (rewardAmount / 2 / 2));
        assertTrue(balanceAtTheEnd - balanceStart == (rewardAmount / 2));
    }

    function test_EmitRewardPaidEvent() public {
        vm.prank(registry);
        pool.approvePool();

        pool.start();

        // first staker
        _stake(staker, DEFAULT_AMOUNT);

        // ⌛️ go beyond the end of the locked period
        vm.warp(block.timestamp + SEEDING_PERIOD + LOCK_PERIOD + 1 days);

        uint256 rewardAmount = DEFAULT_REWARD_AMOUNT - ((DEFAULT_REWARD_AMOUNT * DEFAULT_PROTOCOL_FEE) / MAX_PCT);

        vm.expectEmit(true, true, true, true);
        emit RewardPaid(staker, rewardAmount);

        vm.prank(staker);
        pool.claim();
    }
}
