# Crystalize

[![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![semantic-release: convential commits][commits-badge]][commits] [![License: MIT][license-badge]][license]

[gha]: https://github.com/crystalizefi/crystalize-contracts/actions
[gha-badge]: https://github.com/crystalizefi/crystalize-contracts/actions/workflows/ci.yml/badge.svg
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[commits]: https://github.com/semantic-release/semantic-release
[commits-badge]: https://img.shields.io/badge/semantic--release-conventialcommits-e10079?logo=semantic-release
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

## Contracts

A high level goal for the contracts that will power this protocol is that they are as simple and straightforward as possible with minimal extensibility.

### Terminology

-   Pool - A staking contract that will house user deposits and rewards
-   Deployer - A DAO or protocol who is spinning up a new pool
-   Staker - User depositing tokens, claim rewards, etc

### Deployer flows

-   Deployer is connected to the same chain as the token they are creating a Pool for

### Staking flows we’re supporting

-   Staker is connected to the same chain as the Pool and already owns the token to stake
-   Staker is connected to the same chain as the Pool and does not own the token to stake
-   Staker is connected to a different chain from the Pool and is spending a Stargate-compatible token to purchase the token to stake
-   Staker is connected to a different chain from the Pool and is spending a token incompatible with Stargate

### Contracts

#### Deployer Flow

Deployer will utilize a factory contract to create their pool. The factory contract will register the new Pool in a registry.

![flow-1.svg](docs/images/flow-1.svg)

-   Registry will whitelist one Factory to be able to write to it. Factory is able to be updated via permissioned setter. Only one Factory is supported at a time.
-   Factory will allow multiple types of templates to be created from it.
-   Deployers + token they’re creating the pool for will need to be whitelisted as a pair by the Factory owner before they are able to deploy.

Staker Flows

The simplest of flows, user is on the same chain and owns the token. Staker interacts with the Zap to deposit

-   Approvals go to the Zap

When the user is on the same chain, but doesn’t own the token, we introduce the Zap contract. The Zap contract will assist in purchasing the token, and staking it, in one transaction. To do this the Zap will track whitelisted Swapper contract that we write that can interact with various DEX’s.

For this first iteration, given the chains we are targeting and DEXs we’d like to integrate with, we should only need a single swapper which interacts with the 0x Swap Aggregator. This will require just the most bare minimum swapper contract.

![flow-2.svg](docs/images/flow-2.svg)

Next, we layer on cross-chain. In this scenario the user has the assets they want to use to purchase the token on another chain. In this case, we introduce Stargate Finance. Stargate will allow us to bridge common pair tokens we can use to make the purchase we need.

For this we need a receiver on the destination chain that acts as a callback from Stargate. We’ll likely bridge ETH/sgETH as the pair tokens will likely be ETH/WETH.

The SGTReceiver should send the tokens to on-chain wallet to hold on behalf of the user. The user will then be prompted in the UI to switch chains and complete their purchase. This largely alleviates the issue of partial failures for the user and creates a consistent experience. From the contract side it means we don’t have to pass pricing data across chain and means we only need one swapper, 0x

![flow-3.svg](docs/images/flow-3.svg)

And finally, the most complicated, where the user doesn’t have an SGT compatible input token. Luckily in this scenario, we can re-use most of the functionality from our Zap contract. We will utilize the very first same-chain-doesn’t-own-token flow, but instead of depositing to the pool after we swap with 0x, we will deposit into SGT.

![flow-3.svg](docs/images/flow-4.svg)
