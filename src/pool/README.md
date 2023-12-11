# Pool Contract

The Pool contract is a smart contract built on the Ethereum blockchain. It allows users to "stake" their ERC20 tokens and earn rewards in the form of additional tokens. The contract goes through different phases, each representing a specific stage in the pool's lifecycle.

## Lifecycle of a Pool

Here's a basic timeline of a pool's lifecycle:

```
Created -> Approved -> Seeding -> Locked -> Unlocked.
```

### Uninitialized

Triggered by the following function call:

```
constructor(address _registry)
```

At this stage, the pool contract has been deployed but not yet set up. It doesn't yet have the necessary information like the treasury address, the specific token to be staked, the length of the lock period, and the amount of rewards.

### Created

Triggered by the following function call:

```
initialize(address _creator, address _treasury, address _token, uint256 _seedingPeriod, uint256 _lockPeriod, uint256 _maxStakePerAddress, uint256 _protocolFeeBps, uint256 _maxStakePerPool)
```

Now, the pool has been set up with all the necessary details. These include the treasury address (which holds the pool's funds), the specific ERC20 token to be staked, the length of the lock period, and the amount of rewards that will be shared among the stakers. The pool is now ready but not yet open for staking.

### Approved

Triggered by the following function call:

```
approvePool() onlyRegistry;
```

Once the pool has been checked and confirmed to be good, it can be approved by the registry. After it's approved, the pool's creator can start the seeding phase, which means the pool is now open for deposits.

### Rejected

Triggered by the following function call:

```
rejectPool() onlyRegistry;
```

However, if the pool doesn't meet the necessary standards or criteria, the registry can choose to reject it. When a pool is rejected, it cannot start the seeding phase, and it will not accept any deposits. At this point, the creator of the pool can retrieve the reward tokens they initially deposited. This is done by calling the `retrieveRewardToken` function which transfers the tokens back to the creator's address. This retrieval is only allowed when the pool is in the "Rejected" stage.

### Seeding

Triggered by the following function call:

```
start() external onlyCreator
```

Once the pool is activated, we're in the "seeding" phase. During this period, users can deposit their tokens into the pool. The seeding period lasts for a specific length of time (for example, it might last for 1 week). The goal is to gather a large amount of tokens in the pool before the lock period starts.

### Locked

The lock phase starts right after the seeding phase ends. During this time, users can't deposit any more tokens and all the tokens currently in the pool are locked for a certain time (like 30, 60, or 90 days, etc.). While the tokens are locked, they earn rewards.

### Unlocked

Once the lock period ends, the pool moves into the "unlocked" state. Now, users can take their funds out of the pool. They can take out not just the tokens they initially staked, but also the extra tokens they earned as rewards during the lock period.

## Interactions

Throughout the pool's lifecycle, users can do several things:

1. **Stake Tokens**: Users can deposit their tokens into the pool during the **seeding** phase.

2. **Unstake Tokens**: Users can take out their tokens after the entire lock period is over, the **unlocked** period.

3. **Claim Rewards**: After the **locked** period starts, users can claim their earned rewards at any time. How many rewards a user gets depends on how many tokens they staked.

## Underlying Status

In the Pool contract, we use a hidden state variable named `_underlyingStatus` instead of a status property. This hidden variable keeps track of the pool's status, which is based on predefined actions. But, the `_underlyingStatus` doesn't always show the actual current status of the pool.

To solve this issue, we provide a public function called `status` that works out the dynamic status. That
