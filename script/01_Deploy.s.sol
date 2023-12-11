// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// solhint-disable no-console

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Registry } from "src/pool/Registry.sol";
import { Pool } from "src/pool/Pool.sol";
import { PoolFactory } from "src/pool/PoolFactory.sol";
import { Lens } from "src/lens/Lens.sol";
import { AsyncSwapper } from "src/swapper/AsyncSwapper.sol";
import { Zap } from "src/zap/Zap.sol";
import { TokenKeeper } from "src/zap/TokenKeeper.sol";
import { StargateReceiver } from "src/stargate/StargateReceiver.sol";
import { Constants } from "script/utils/Constants.sol";

contract DeployScript is Script {
    struct DeployedContracts {
        address poolTemplate;
        address poolRegistry;
        address poolFactory;
        address lens;
        address swapper;
        address zap;
        address tokenKeeper;
        address stargateReceiver;
    }

    function run() external {
        DeployedContracts memory deployed = deploy();
        outputDeployerContracts(deployed);
    }

    function deploy() public returns (DeployedContracts memory) {
        Constants.Values memory constants = Constants.get(block.chainid);

        uint256 deployerPrivateKey = vm.envUint(constants.deployerPrivateKeyEnvVar);
        address owner = vm.addr(vm.envUint(constants.deployerPrivateKeyEnvVar));

        vm.startBroadcast(deployerPrivateKey);

        /// contracts deployment
        Registry registry = new Registry(owner);
        Pool pool = new Pool(address(registry));
        PoolFactory poolFactory = new PoolFactory(owner, address(registry), owner, constants.cfg.defaultFeeBps );

        /// contracts setup

        /// we register the new factory into the Registry
        registry.setFactory(address(poolFactory));

        /// we add the new pool template to the factory
        poolFactory.addTemplate(address(pool));

        // Deploy Lens
        Lens lens = new Lens(registry);

        // Deploy Swapper
        AsyncSwapper swapper = new AsyncSwapper(constants.ext.zeroExProxy);

        // Deploy Token Keeper
        TokenKeeper keeper = new TokenKeeper(owner);

        // Deploy Zap
        Zap zap = new Zap(address(swapper), address(registry), constants.ext.stargateRouter, address(keeper), owner);

        // Stargate Receiver
        StargateReceiver rcv = new StargateReceiver(constants.ext.stargateRouter, address(keeper));

        keeper.setZapAndStargateReceiver(address(zap), address(rcv));

        vm.stopBroadcast();

        return DeployedContracts({
            poolTemplate: address(pool),
            poolRegistry: address(registry),
            poolFactory: address(poolFactory),
            lens: address(lens),
            swapper: address(swapper),
            zap: address(zap),
            tokenKeeper: address(keeper),
            stargateReceiver: address(rcv)
        });
    }

    function outputDeployerContracts(DeployedContracts memory deployed) public view {
        console.log("chainId: %s", block.chainid);
        console.log("poolTemplate: %s", address(deployed.poolTemplate));
        console.log("poolRegistry: %s", address(deployed.poolRegistry));
        console.log("poolFactory: %s", address(deployed.poolFactory));
        console.log("lens: %s", address(deployed.lens));
        console.log("swapper: %s", address(deployed.swapper));
        console.log("zap: %s", address(deployed.zap));
        console.log("tokenKeeper: %s", address(deployed.tokenKeeper));
        console.log("stargateReceiver: %s", address(deployed.stargateReceiver));
    }
}
