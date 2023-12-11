// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

library Constants {
    error NetworkNotConfigured();

    struct External {
        address zeroExProxy;
        address stargateRouter;
        uint16 stargateChainId;
    }

    struct Config {
        uint256 defaultFeeBps;
        uint256 defaultSeedingPeriod;
    }

    struct Values {
        External ext;
        Config cfg;
        string deployerPrivateKeyEnvVar;
    }

    function get(uint256 chainId) external pure returns (Values memory) {
        if (chainId == 5) {
            return getGoerli();
        } else if (chainId == 421_613) {
            return getArbGoerli();
        } else {
            revert NetworkNotConfigured();
        }
    }

    function getGoerli() private pure returns (Values memory) {
        return Values({
            ext: External({
                zeroExProxy: 0xF91bB752490473B8342a3E964E855b9f9a2A668e,
                stargateRouter: 0x7612aE2a34E5A363E137De748801FB4c86499152,
                stargateChainId: 10_121
            }),
            cfg: Config({ defaultFeeBps: 500, defaultSeedingPeriod: 1 weeks }),
            deployerPrivateKeyEnvVar: "DEPLOYER_PRIVATE_KEY"
        });
    }

    function getArbGoerli() private pure returns (Values memory) {
        return Values({
            ext: External({
                zeroExProxy: address(1),
                stargateRouter: 0xb850873f4c993Ac2405A1AdD71F6ca5D4d4d6b4f,
                stargateChainId: 10_143
            }),
            cfg: Config({ defaultFeeBps: 500, defaultSeedingPeriod: 1 weeks }),
            deployerPrivateKeyEnvVar: "DEPLOYER_PRIVATE_KEY"
        });
    }
}
