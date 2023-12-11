// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase,contract-name-camelcase,one-contract-per-file */
pragma solidity 0.8.19;

import { IERC20Errors } from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Test } from "forge-std/Test.sol";

import { IPool } from "src/interfaces/pool/IPool.sol";
import { Pool } from "src/pool/Pool.sol";
import { PoolFactory } from "src/pool/PoolFactory.sol";
import { Registry } from "src/pool/Registry.sol";

import { Error } from "src/librairies/Error.sol";

contract PoolFactoryTest is Test {
    address public owner;
    address public treasury;
    address public deployer;
    address public user;

    MockERC20 public token;

    Pool public poolTemplate;
    Pool public poolTemplateOddRegistry;
    PoolFactory public factory;
    PoolFactory public factoryReady;
    Registry public registry;

    uint256 public constant MAX_PCT = 10_000;
    uint256 public constant DEFAULT_FEE_BPS = 1000;
    uint256 public constant DEFAULT_REWARD_AMOUNT = 100 * 1e18;
    uint256 public constant DEFAULT_SEEDING_PERIOD = 1 weeks;
    uint256 public constant DEFAULT_LOCK_PERIOD = 1 weeks;
    uint256 public constant DEFAULT_MAX_STAKE_PER_ADDRESS = 500 * 1e18;
    uint256 public constant DEFAULT_MAX_STAKE_PER_POOL = 5000 * 1e18;

    event PoolFactoryCreated(address indexed owner, address indexed registry, address treasury, uint256 protocolFee);
    event DeployerAdded(address indexed account, address indexed token);
    event DeployerRemoved(address indexed account, address indexed token);
    event PoolCreated(address indexed pool);
    event TemplateAdded(address indexed template);
    event TemplateRemoved(address indexed template);
    event TreasurySet(address indexed oldTreasury, address indexed newTreasury);
    event ProtocolFeeSet(uint256 oldFee, uint256 newFee);
    event Transfer(address indexed from, address indexed to, uint256 value);
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
    event PoolPending(address indexed pool);

    function setUp() public {
        owner = vm.addr(1);
        treasury = vm.addr(2);
        deployer = vm.addr(3);
        user = vm.addr(4);

        token = new MockERC20("CRYSTALIZE", "CRY");

        registry = new Registry(owner);
        poolTemplate = new Pool(address(registry));
        poolTemplateOddRegistry = new Pool(address(4));
        factory = new PoolFactory(owner, address(registry), treasury, DEFAULT_FEE_BPS);
        factoryReady = new PoolFactory(owner, address(registry), treasury, DEFAULT_FEE_BPS);

        vm.startPrank(owner);
        // we add the factory to the register
        registry.setFactory(address(factoryReady));
        // we add a deployer first
        factoryReady.addDeployer(deployer, address(token));
        // we then add a template
        factoryReady.addTemplate(address(poolTemplate));
        vm.stopPrank();

        vm.prank(deployer);
        // we set the token allowance
        token.approve(address(factoryReady), DEFAULT_REWARD_AMOUNT);
    }
}

contract Constructor is PoolFactoryTest {
    function test_RevertIf_RegistryIsZero() public {
        vm.expectRevert(Error.ZeroAddress.selector);
        new PoolFactory(owner, address(0), treasury, 0);
    }

    function test_RevertIf_TreasuryIsZero() public {
        vm.expectRevert(Error.ZeroAddress.selector);
        new PoolFactory(owner, owner, address(0), 0);
    }

    function testFuzz_RevertIf_ProtocolFeeIsTooHigh(uint256 _fee) public {
        vm.assume(_fee > MAX_PCT);
        vm.expectRevert(Error.FeeTooHigh.selector);
        new PoolFactory(owner, owner, owner, _fee);
    }

    function test_SetsRegistryWhen_Deployed() public {
        PoolFactory _factory = new PoolFactory(owner, address(registry), treasury, 0);
        assertTrue(_factory.registry() == address(registry));
    }

    function test_SetsTreasuryWhen_Deployed() public {
        PoolFactory _factory = new PoolFactory(owner, address(registry), treasury, 0);
        assertTrue(_factory.treasury() == treasury);
    }

    function testFuzz_SetsProtocolFeeWhen_Deployed(uint256 _fee) public {
        vm.assume(_fee <= MAX_PCT);
        PoolFactory _factory = new PoolFactory(owner, address(registry), treasury, _fee);
        assertTrue(_factory.protocolFeeBps() == _fee);
    }

    function testFuzz_EmitsPoolFactoryCreatedWhen_Deployed(uint256 _fee) public {
        vm.assume(_fee <= MAX_PCT);
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit PoolFactoryCreated(owner, address(registry), treasury, _fee);
        new PoolFactory(owner, address(registry), treasury, _fee);
    }
}

contract CreatePool is PoolFactoryTest {
    function test_RevertIf_CallerNotDeployer() public {
        vm.expectRevert(Error.Unauthorized.selector);
        factory.createPool(address(0), address(0), 0, 0, 0, 0, DEFAULT_MAX_STAKE_PER_POOL);
    }

    function testFuzz_RevertIf_DeployerWithWrongToken(address _token) public {
        vm.assume(_token != address(token));
        // we add a deployer first
        vm.prank(owner);
        factory.addDeployer(deployer, address(token));

        vm.expectRevert(Error.Unauthorized.selector);
        factory.createPool(address(0), _token, 0, 0, 0, 0, DEFAULT_MAX_STAKE_PER_POOL);
    }

    function testFuzz_RevertIf_TemplateNotFound(address _template) public {
        vm.assume(_template != address(poolTemplate));
        // we add a deployer first
        vm.startPrank(owner);
        factory.addDeployer(deployer, address(token));

        // we then add a template
        factory.addTemplate(address(poolTemplate));
        vm.stopPrank();

        vm.prank(deployer);
        vm.expectRevert(Error.UnknownTemplate.selector);
        factory.createPool(_template, address(token), 0, 0, 0, 0, DEFAULT_MAX_STAKE_PER_POOL);
    }

    function test_RevertIf_InsufficientAllowance() public {
        // we add a deployer first
        vm.startPrank(owner);
        factory.addDeployer(deployer, address(token));

        // we then add a template
        factory.addTemplate(address(poolTemplate));
        vm.stopPrank();

        vm.startPrank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, DEFAULT_REWARD_AMOUNT
            )
        );
        factory.createPool(
            address(poolTemplate), address(token), 0, 0, DEFAULT_REWARD_AMOUNT, 0, DEFAULT_MAX_STAKE_PER_POOL
        );
        vm.stopPrank();
    }

    function test_RevertIf_TokenBalanceTooLow() public {
        // we add a deployer first
        vm.startPrank(owner);
        factory.addDeployer(deployer, address(token));

        // we then add a template
        factory.addTemplate(address(poolTemplate));
        vm.stopPrank();

        vm.startPrank(deployer);
        // we set the token allowance
        token.approve(address(factory), DEFAULT_REWARD_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                deployer,
                token.balanceOf(deployer),
                DEFAULT_REWARD_AMOUNT
            )
        );
        factory.createPool(
            address(poolTemplate), address(token), 0, 0, DEFAULT_REWARD_AMOUNT, 0, DEFAULT_MAX_STAKE_PER_POOL
        );
    }

    function test_EmitsTransferWhen_PoolCreated() public {
        // we distribute the tokens to the deployer
        deal(address(token), deployer, DEFAULT_REWARD_AMOUNT);
        vm.startPrank(deployer);

        // we compute what the pool address will be
        address pool = computeCreateAddress(address(factoryReady), 1);

        assertTrue(token.balanceOf(deployer) == DEFAULT_REWARD_AMOUNT);
        assertTrue(token.balanceOf(pool) == 0);

        vm.expectEmit(true, true, false, true);
        emit Transfer(deployer, pool, DEFAULT_REWARD_AMOUNT);

        factoryReady.createPool(
            address(poolTemplate),
            address(token),
            DEFAULT_SEEDING_PERIOD,
            DEFAULT_LOCK_PERIOD,
            DEFAULT_REWARD_AMOUNT,
            DEFAULT_MAX_STAKE_PER_ADDRESS,
            DEFAULT_MAX_STAKE_PER_POOL
        );
        assertTrue(token.balanceOf(deployer) == 0);
        assertTrue(token.balanceOf(pool) == DEFAULT_REWARD_AMOUNT);
        vm.stopPrank();
    }

    function test_EmitsPoolInitializedWhen_PoolCreated() public {
        // we distribute the tokens to the deployer
        deal(address(token), deployer, DEFAULT_REWARD_AMOUNT);
        vm.startPrank(deployer);

        vm.expectEmit(true, false, false, true);
        emit PoolInitialized(
            address(token),
            deployer,
            DEFAULT_SEEDING_PERIOD,
            DEFAULT_LOCK_PERIOD,
            DEFAULT_REWARD_AMOUNT,
            DEFAULT_FEE_BPS,
            DEFAULT_MAX_STAKE_PER_ADDRESS,
            DEFAULT_MAX_STAKE_PER_POOL
        );

        factoryReady.createPool(
            address(poolTemplate),
            address(token),
            DEFAULT_SEEDING_PERIOD,
            DEFAULT_LOCK_PERIOD,
            DEFAULT_REWARD_AMOUNT,
            DEFAULT_MAX_STAKE_PER_ADDRESS,
            DEFAULT_MAX_STAKE_PER_POOL
        );

        vm.stopPrank();
    }

    function test_EmitsPoolCreatedWhen_PoolCreated() public {
        // we distribute the tokens to the deployer
        deal(address(token), deployer, DEFAULT_REWARD_AMOUNT);
        vm.startPrank(deployer);

        // we compute what the pool address will be
        address pool = computeCreateAddress(address(factoryReady), 1);

        vm.expectEmit(true, false, false, false);
        emit PoolCreated(pool);

        factoryReady.createPool(
            address(poolTemplate),
            address(token),
            DEFAULT_SEEDING_PERIOD,
            DEFAULT_LOCK_PERIOD,
            DEFAULT_REWARD_AMOUNT,
            DEFAULT_MAX_STAKE_PER_ADDRESS,
            DEFAULT_MAX_STAKE_PER_POOL
        );

        vm.stopPrank();
    }

    function test_EmitsPoolPending_PoolCreated() public {
        // we distribute the tokens to the deployer
        deal(address(token), deployer, DEFAULT_REWARD_AMOUNT);
        vm.startPrank(deployer);

        // we compute what the pool address will be
        address pool = computeCreateAddress(address(factoryReady), 1);

        vm.expectEmit(true, false, false, false);
        emit PoolPending(pool);

        factoryReady.createPool(
            address(poolTemplate),
            address(token),
            DEFAULT_SEEDING_PERIOD,
            DEFAULT_LOCK_PERIOD,
            DEFAULT_REWARD_AMOUNT,
            DEFAULT_MAX_STAKE_PER_ADDRESS,
            DEFAULT_MAX_STAKE_PER_POOL
        );

        vm.stopPrank();
    }
}

contract AddTemplate is PoolFactoryTest {
    function test_RevertIf_CallerNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        factory.addTemplate(address(0));
    }

    function test_RevertIf_TemplateIsZero() public {
        vm.prank(owner);
        vm.expectRevert(Error.ZeroAddress.selector);
        factory.addTemplate(address(0));
    }

    function test_RevertIf_TemplateAlreadyExists() public {
        vm.startPrank(owner);
        // we then add a template
        factory.addTemplate(address(poolTemplate));
        // we try to add the same template
        vm.expectRevert(Error.AddFailed.selector);
        factory.addTemplate(address(poolTemplate));
        vm.stopPrank();
    }

    function test_RevertIf_RegistriesDontMatchBetweenTemplateAndFactor() public {
        vm.startPrank(owner);
        vm.expectRevert(Error.MismatchRegistry.selector);
        factory.addTemplate(address(poolTemplateOddRegistry));
    }

    function test_EmitsTemplateAddedWhen_TemplateAdded() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit TemplateAdded(address(poolTemplate));
        factory.addTemplate(address(poolTemplate));
    }

    function test_SetsTemplatesWhen_TemplateAdded() public {
        vm.startPrank(owner);
        assertFalse(factory.hasTemplate(address(poolTemplate)));
        factory.addTemplate(address(poolTemplate));
        assertTrue(factory.hasTemplate(address(poolTemplate)));
        vm.stopPrank();
    }
}

contract RemoveTemplate is PoolFactoryTest {
    function test_RevertIf_CallerNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        factory.removeTemplate(address(0));
    }

    function test_RevertIf_TemplateNotFound() public {
        vm.prank(owner);
        vm.expectRevert(Error.RemoveFailed.selector);
        factory.removeTemplate(address(poolTemplate));
    }

    function test_EmitsTemplateRemovedWhen_TemplateRemoved() public {
        vm.startPrank(owner);
        // we add a template
        factory.addTemplate(address(poolTemplate));

        vm.expectEmit(true, false, false, false);
        emit TemplateRemoved(address(poolTemplate));
        factory.removeTemplate(address(poolTemplate));
        vm.stopPrank();
    }

    function test_SetsTemplatesWhen_TemplateRemoved() public {
        vm.startPrank(owner);
        // we add a template
        factory.addTemplate(address(poolTemplate));
        assertTrue(factory.hasTemplate(address(poolTemplate)));

        factory.removeTemplate(address(poolTemplate));
        assertFalse(factory.hasTemplate(address(poolTemplate)));
        vm.stopPrank();
    }
}

contract AddDeployer is PoolFactoryTest {
    function test_RevertIf_CallerNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        factory.addDeployer(address(0), address(0));
    }

    function test_RevertIf_AccountIsZero() public {
        vm.prank(owner);
        vm.expectRevert(Error.ZeroAddress.selector);
        factory.addDeployer(address(0), address(0));
    }

    function test_RevertIf_TokenIsZero() public {
        vm.prank(owner);
        vm.expectRevert(Error.ZeroAddress.selector);
        factory.addDeployer(deployer, address(0));
    }

    function test_EmitsDeployerAddedWhen_DeployerAdded() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit DeployerAdded(deployer, address(token));
        factory.addDeployer(deployer, address(token));
    }

    function test_SetsDeployersWhen_DeployerAdded() public {
        vm.startPrank(owner);
        assertFalse(factory.canDeploy(deployer, address(token)));
        factory.addDeployer(deployer, address(token));
        assertTrue(factory.canDeploy(deployer, address(token)));
        vm.stopPrank();
    }
}

contract RemoveDeployer is PoolFactoryTest {
    function test_RevertIf_CallerNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        factory.removeDeployer(address(0), address(0));
    }

    function test_RevertIf_DeployerNotFound() public {
        // we add a deployer first
        vm.startPrank(owner);
        factory.addDeployer(deployer, address(token));

        vm.expectRevert(Error.DeployerNotFound.selector);
        factory.removeDeployer(deployer, owner);
        vm.stopPrank();
    }

    function test_EmitsDeployerRemovedWhen_DeployerRemoved() public {
        // we add a deployer first
        vm.startPrank(owner);
        factory.addDeployer(deployer, address(token));

        vm.expectEmit(true, true, false, false);
        emit DeployerRemoved(deployer, address(token));
        factory.removeDeployer(deployer, address(token));
        vm.stopPrank();
    }

    function test_SetsDeployersWhen_DeployerRemoved() public {
        // we add a deployer first
        vm.startPrank(owner);
        factory.addDeployer(deployer, address(token));

        assertTrue(factory.canDeploy(deployer, address(token)));
        factory.removeDeployer(deployer, address(token));
        assertFalse(factory.canDeploy(deployer, address(token)));
        vm.stopPrank();
    }
}

contract SetTreasury is PoolFactoryTest {
    function test_RevertIf_CallerNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        factory.setTreasury(address(0));
    }

    function test_RevertIf_TreasuryIsZero() public {
        vm.prank(owner);
        vm.expectRevert(Error.ZeroAddress.selector);
        factory.setTreasury(address(0));
    }

    function testFuzz_EmitsTreasurySetWhen_TreasurySet(address _treasury) public {
        vm.assume(_treasury != address(0));
        vm.assume(_treasury != factory.treasury());
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, false);
        emit TreasurySet(factory.treasury(), _treasury);
        factory.setTreasury(_treasury);
        vm.stopPrank();
    }

    function testFuzz_SetsTreasuryWhen_TreasurySet(address _treasury) public {
        vm.assume(_treasury != address(0));
        vm.assume(_treasury != factory.treasury());
        vm.prank(owner);
        factory.setTreasury(_treasury);
        assertTrue(factory.treasury() == _treasury);
    }
}

contract SetProtocolFee is PoolFactoryTest {
    function test_RevertIf_CallerNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        factory.setProtocolFee(0);
    }

    function testFuzz_RevertIf_FeeTooHigh(uint256 _fee) public {
        vm.assume(_fee > MAX_PCT);
        vm.prank(owner);
        vm.expectRevert(Error.FeeTooHigh.selector);
        factory.setProtocolFee(_fee);
    }

    function testFuzz_EmitsProtocolFeeSetWhen_ProtocolFeeSet(uint256 _fee) public {
        vm.assume(_fee <= MAX_PCT);
        vm.startPrank(owner);
        vm.expectEmit(false, false, false, true);
        emit ProtocolFeeSet(factory.protocolFeeBps(), _fee);
        factory.setProtocolFee(_fee);
        vm.stopPrank();
    }

    function testFuzz_SetsProtocolFeeWhen_ProtocolFeeSet(uint256 _fee) public {
        vm.assume(_fee <= MAX_PCT);
        vm.startPrank(owner);
        factory.setProtocolFee(_fee);
        assertTrue(factory.protocolFeeBps() == _fee);
        vm.stopPrank();
    }
}

contract GetTemplateAt is PoolFactoryTest {
    function test_RevertIf_WrongIndex() public {
        vm.expectRevert();
        factory.getTemplateAt(0);
    }

    function test_ReturnsTemplateWhen_CorrectIndex() public {
        vm.prank(owner);
        factory.addTemplate(address(poolTemplate));
        assertTrue(factory.getTemplateAt(0) == address(poolTemplate));
    }
}

contract GetTemplateCount is PoolFactoryTest {
    function test_ReturnsZeroWhen_NoTemplates() public {
        assertTrue(factory.getTemplateCount() == 0);
    }

    function test_ReturnsZeroWhen_AllTemplatesDeleted() public {
        vm.startPrank(owner);
        factory.addTemplate(address(poolTemplate));
        assertTrue(factory.getTemplateCount() == 1);
        factory.removeTemplate(address(poolTemplate));
        assertTrue(factory.getTemplateCount() == 0);
        vm.stopPrank();
    }

    function testFuzz_ReturnsTemplateCountWhen_TemplateExists(address _template1, address _template2) public {
        vm.assume(_template1 != _template2);
        vm.assume(_template1 != address(0));
        vm.assume(_template2 != address(0));

        vm.startPrank(owner);

        _mockRegistry(_template1);
        factory.addTemplate(_template1);
        assertTrue(factory.getTemplateCount() == 1);

        _mockRegistry(_template2);
        factory.addTemplate(_template2);
        assertTrue(factory.getTemplateCount() == 2);

        vm.stopPrank();
    }

    function _mockRegistry(address template) private {
        vm.mockCall(address(template), abi.encodeWithSelector(IPool.registry.selector), abi.encode(registry));
    }
}

contract HasTemplate is PoolFactoryTest {
    function test_ReturnsFalseWhen_NoTemplates() public {
        assertFalse(factory.hasTemplate(address(poolTemplate)));
    }

    function test_ReturnsFalseWhen_TemplateIsNotFound() public {
        vm.prank(owner);
        factory.addTemplate(address(poolTemplate));
        assertFalse(factory.hasTemplate(owner));
    }

    function test_ReturnsTrueWhen_TemplateIsFound() public {
        vm.prank(owner);
        factory.addTemplate(address(poolTemplate));
        assertTrue(factory.hasTemplate(address(poolTemplate)));
    }
}

contract CanDeploy is PoolFactoryTest {
    function test_ReturnsFalseWhen_DeployerNotFound() public {
        assertFalse(factory.canDeploy(deployer, address(0)));
    }

    function test_ReturnsFalseWhen_TokenNotFound() public {
        vm.prank(owner);
        factory.addDeployer(deployer, address(token));
        assertFalse(factory.canDeploy(deployer, owner));
    }

    function testFuzz_ReturnsTrueWhen_DeployerAndTokenFound(address _token1, address _token2) public {
        vm.assume(_token1 != _token2);
        vm.assume(_token1 != address(0));
        vm.assume(_token2 != address(0));

        vm.startPrank(owner);
        factory.addDeployer(deployer, _token1);
        factory.addDeployer(deployer, _token2);
        assertTrue(factory.canDeploy(deployer, _token1));
        assertTrue(factory.canDeploy(deployer, _token2));
        vm.stopPrank();
    }
}
