// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IRewarder} from "./interfaces/tokemak/IRewarder.sol";

import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

import {TokemakStrategy, ERC20} from "./TokemakStrategy.sol";

contract TokemakStrategyFactory {
    event NewStrategy(address indexed strategy, address indexed asset, address indexed autoPool);
    event AddressesUpdated(address indexed management, address indexed performanceFeeRecipient, address indexed keeper);

    address public immutable emergencyAdmin;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    /// @notice Track the deployments. asset => pool => strategy
    mapping(address => address) public deployments;

    constructor(address _management, address _performanceFeeRecipient, address _keeper, address _emergencyAdmin) {
        require(_management != address(0), "!_management");
        require(_performanceFeeRecipient != address(0), "!_performanceFeeRecipient");
        require(_keeper != address(0), "!_keeper");
        require(_emergencyAdmin != address(0), "!_emergencyAdmin");

        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    modifier onlyManagement() {
        require(msg.sender == management, "!management");
        _;
    }

    /**
     * @notice Deploy a new Strategy.
     * @param _asset The underlying asset for the strategy to use.
     * @param _autoPool The Tokemak auto pool address.
     * @param _rewarder The rewarder address where we stake the autoPool receipt tokens.
     * @return . The address of the new strategy.
     */
    function newStrategy(
        address _asset,
        address _autoPool,
        address _rewarder
    )
        external
        onlyManagement
        returns (address)
    {
        require(deployments[_asset] == address(0), "deployed");
        require(IERC4626(_autoPool).asset() == _asset, "!asset");
        require(IRewarder(_rewarder).stakingToken() == _autoPool, "!rewarder");

        // tokenized strategies available setters.
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(new TokemakStrategy(
                _asset,
                _autoPool,
                _rewarder,
                string(abi.encodePacked("Tokemak Strategy: ", IERC4626(_autoPool).symbol()))
            ))
        );

        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        _newStrategy.setKeeper(keeper);

        _newStrategy.setPendingManagement(management);

        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        // slither-disable-next-line reentrancy-events
        emit NewStrategy(address(_newStrategy), _asset, _autoPool);

        // slither-disable-next-line reentrancy-no-eth
        deployments[_asset] = address(_newStrategy);
        return address(_newStrategy);
    }

    function setAddresses(address _management, address _performanceFeeRecipient, address _keeper) external {
        require(msg.sender == management, "!management");
        require(_management != address(0), "!_management");
        require(_performanceFeeRecipient != address(0), "!_performanceFeeRecipient");
        require(_keeper != address(0), "!_keeper");

        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;

        emit AddressesUpdated(_management, _performanceFeeRecipient, _keeper);
    }

    function isDeployedStrategy(address _strategy) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        return deployments[_asset] == _strategy;
    }
}
