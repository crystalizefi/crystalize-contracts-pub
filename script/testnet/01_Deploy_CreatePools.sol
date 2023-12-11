// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// solhint-disable no-console

import { IPool } from "src/pool/Pool.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IRegistry } from "src/pool/Registry.sol";
import { DeployScript } from "script/01_Deploy.s.sol";
import { IPoolFactory } from "src/pool/PoolFactory.sol";
import { Constants } from "script/utils/Constants.sol";
import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract CreatePoolScript is Script {
    address public constant ADDITIONAL_DEPLOYER = 0x157D6970e3aA628Ab43D28c609C847D25493A3d2;

    uint256 public constant DEFAULT_SEEDING_PERIOD = 1 weeks;
    uint256 public constant DEFAULT_LOCK_PERIOD = 1 weeks;
    uint256 public constant DEFAULT_REWARD_AMOUNT = 100e18;
    uint256 public constant DEFAULT_MAX_STAKE = 500e18;
    uint256 public constant DEFAULT_MAX_POOL = 5000e18;
    uint256 public constant DEFAULT_STAKE_AMOUNT = 100e18;

    function run() external {
        DeployScript deploy = new DeployScript();
        DeployScript.DeployedContracts memory sys = deploy.deploy();
        deploy.outputDeployerContracts(sys);
        setupPools(sys);
    }

    function setupPools(DeployScript.DeployedContracts memory sys) public {
        /*///////////////////////////////////////////////////////////////
                             SETUP
        ///////////////////////////////////////////////////////////////*/

        Constants.Values memory constants = Constants.get(block.chainid);

        uint256 deployerPrivateKey = vm.envUint(constants.deployerPrivateKeyEnvVar);
        address owner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        ERC20Mock token = new ERC20Mock();
        token.mint(ADDITIONAL_DEPLOYER, 200_000e18);
        token.mint(owner, 200_000e18);

        IRegistry registry = IRegistry(sys.poolRegistry);
        IPoolFactory poolFactory = IPoolFactory(sys.poolFactory);

        // we authorise a (deployer, token) pair
        poolFactory.addDeployer(owner, address(token));
        poolFactory.addDeployer(ADDITIONAL_DEPLOYER, address(token));

        // we approve the contract to spend the token
        token.approve(sys.poolFactory, DEFAULT_REWARD_AMOUNT * 5);

        /*///////////////////////////////////////////////////////////////
                            POOL CREATION
        ///////////////////////////////////////////////////////////////*/

        address unapprovedPoolAddr = poolFactory.createPool(
            sys.poolTemplate,
            address(token),
            DEFAULT_SEEDING_PERIOD,
            DEFAULT_LOCK_PERIOD,
            DEFAULT_REWARD_AMOUNT,
            DEFAULT_MAX_STAKE,
            DEFAULT_MAX_POOL
        );
        address approvedPoolAddr = poolFactory.createPool(
            sys.poolTemplate,
            address(token),
            DEFAULT_SEEDING_PERIOD,
            DEFAULT_LOCK_PERIOD,
            DEFAULT_REWARD_AMOUNT,
            DEFAULT_MAX_STAKE,
            DEFAULT_MAX_POOL
        );
        address startedPoolAddr = poolFactory.createPool(
            sys.poolTemplate,
            address(token),
            DEFAULT_SEEDING_PERIOD,
            DEFAULT_LOCK_PERIOD,
            DEFAULT_REWARD_AMOUNT,
            DEFAULT_MAX_STAKE,
            DEFAULT_MAX_POOL
        );
        address lockedPoolAddr = poolFactory.createPool(
            sys.poolTemplate,
            address(token),
            200,
            DEFAULT_LOCK_PERIOD,
            DEFAULT_REWARD_AMOUNT,
            DEFAULT_MAX_STAKE,
            DEFAULT_MAX_POOL
        );
        address unlockedPoolAddr = poolFactory.createPool(
            sys.poolTemplate, address(token), 200, 200, DEFAULT_REWARD_AMOUNT, DEFAULT_MAX_STAKE, DEFAULT_MAX_POOL
        );

        IPool startedPool = IPool(startedPoolAddr);
        IPool lockedPool = IPool(lockedPoolAddr);
        IPool unlockedPool = IPool(unlockedPoolAddr);

        /*///////////////////////////////////////////////////////////////
                            POOL APPROVAL
        ///////////////////////////////////////////////////////////////*/

        registry.approvePool(approvedPoolAddr);
        registry.approvePool(startedPoolAddr);
        registry.approvePool(lockedPoolAddr);
        registry.approvePool(unlockedPoolAddr);

        /*///////////////////////////////////////////////////////////////
                            POOL START
        ///////////////////////////////////////////////////////////////*/

        startedPool.start();
        lockedPool.start();
        unlockedPool.start();

        /*///////////////////////////////////////////////////////////////
                            POOL STAKING
        ///////////////////////////////////////////////////////////////*/

        // we approve the contract to spend the token
        token.approve(startedPoolAddr, DEFAULT_STAKE_AMOUNT);
        startedPool.stake(DEFAULT_STAKE_AMOUNT);

        token.approve(lockedPoolAddr, DEFAULT_STAKE_AMOUNT);
        lockedPool.stake(DEFAULT_STAKE_AMOUNT);

        token.approve(unlockedPoolAddr, DEFAULT_STAKE_AMOUNT);
        unlockedPool.stake(DEFAULT_STAKE_AMOUNT);

        console.log("Token: %s", address(token));
        console.log("Unapproved Pool: %s", unapprovedPoolAddr);
        console.log("Approved Pool: %s", approvedPoolAddr);
        console.log("Started Pool: %s", startedPoolAddr);
        console.log("Locked Pool: %s", lockedPoolAddr);
        console.log("Unlocked Pool: %s", unlockedPoolAddr);

        vm.stopBroadcast();
    }
}
