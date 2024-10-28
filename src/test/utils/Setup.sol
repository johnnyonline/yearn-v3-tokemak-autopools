// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {TokemakStrategy, ERC20} from "../../TokemakStrategy.sol";
import {TokemakStrategyFactory} from "../../TokemakStrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

interface IOracle {
    enum Denomination {
        ETH,
        USD
    }
    struct OracleInfo {
        address oracle;
        uint32 pricingTimeout;
        Denomination denomination;
        uint8 decimals;
    }
    function getOracleInfo(address token) external view returns (OracleInfo memory);
    function removeOracleRegistration(address token) external returns (address oracleBeforeDeletion);
    function registerOracle(address token, address oracle, Denomination denomination, uint32 pricingTimeout) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instances that we will use repeatedly.
    address public rewarder = 0x60882D6f70857606Cdd37729ccCe882015d1755E; // autopoolETH Rewarder
    address public autoPool = 0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56; // autopoolETH
    ERC20 public asset;
    IStrategyInterface public strategy;

    TokemakStrategyFactory public strategyFactory;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 10_000;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["WETH"]);

        // Set decimals
        decimals = asset.decimals();

        strategyFactory = new TokemakStrategyFactory(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin
        );

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");

        // tests fail when the oracle is called because of the time delay. we extend that time delay here
        _updateOracleInfo();
    }

    function _updateOracleInfo() internal {

        address oracleDaddy = 0x8b4334d4812C530574Bd4F2763FcD22dE94A969B;
        uint32 pricingTimeout = 5 weeks;

        // steth
        {
            IOracle oracle = IOracle(0x701F115a4d58a44d9e4e437d136DD9fA7b1B6C3f);
            address asset = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
            IOracle.OracleInfo memory info = oracle.getOracleInfo(asset);

            vm.prank(oracleDaddy);
            oracle.removeOracleRegistration(asset);

            vm.prank(oracleDaddy);
            oracle.registerOracle(asset, info.oracle, info.denomination, pricingTimeout);
        }

        // ethx
        {
            IOracle oracle = IOracle(0xe1aDb6967e1dBD5332d499dFA2f42377d1DA5913);
            address asset = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
            IOracle.OracleInfo memory info = oracle.getOracleInfo(asset);

            vm.prank(oracleDaddy);
            oracle.removeOracleRegistration(asset);

            vm.prank(oracleDaddy);
            oracle.registerOracle(asset, info.oracle, info.denomination, pricingTimeout);
        }

        // reth
        {
            IOracle oracle = IOracle(0x701F115a4d58a44d9e4e437d136DD9fA7b1B6C3f);
            address asset = 0xae78736Cd615f374D3085123A210448E74Fc6393;
            IOracle.OracleInfo memory info = oracle.getOracleInfo(asset);

            vm.prank(oracleDaddy);
            oracle.removeOracleRegistration(asset);

            vm.prank(oracleDaddy);
            oracle.registerOracle(asset, info.oracle, info.denomination, pricingTimeout);
        }

        // oseth
        {
            IOracle oracle = IOracle(0xe1aDb6967e1dBD5332d499dFA2f42377d1DA5913);
            address asset = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
            IOracle.OracleInfo memory info = oracle.getOracleInfo(asset);

            vm.prank(oracleDaddy);
            oracle.removeOracleRegistration(asset);

            vm.prank(oracleDaddy);
            oracle.registerOracle(asset, info.oracle, info.denomination, pricingTimeout);
        }

        // apxeth
        {
            IOracle oracle = IOracle(0xe1aDb6967e1dBD5332d499dFA2f42377d1DA5913);
            address asset = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;
            IOracle.OracleInfo memory info = oracle.getOracleInfo(asset);

            vm.prank(oracleDaddy);
            oracle.removeOracleRegistration(asset);

            vm.prank(oracleDaddy);
            oracle.registerOracle(asset, info.oracle, info.denomination, pricingTimeout);
        }
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        vm.prank(management);
        IStrategyInterface _strategy =
            IStrategyInterface(address(strategyFactory.newStrategy(address(asset), autoPool, rewarder, "Tokenized Strategy")));

        vm.prank(management);
        _strategy.acceptManagement();

        return address(_strategy);
    }

    function depositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }
}
