// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {TokemakStrategy, ERC20} from "./TokemakStrategy.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract TokemakStrategyFactory {
    event NewStrategy(address indexed strategy, address indexed asset, address indexed autoPool);

    address public immutable emergencyAdmin;

    address public immutable lendingPool;
    address public immutable router;
    address public immutable base;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    /// @notice Track the deployments. asset => pool => strategy
    mapping(address => address) public deployments;

    constructor(address _management, address _performanceFeeRecipient, address _keeper, address _emergencyAdmin) {
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
        address _rewarder,
        string calldata _name
    )
        external
        onlyManagement
        returns (address)
    {
        // @todo - sanity check asset
        // @todo - sanity check autopool
        // @todo - sanity check name

        // tokenized strategies available setters.
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(new TokemakStrategy(_asset, _autoPool, _rewarder, _name))
        );

        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        _newStrategy.setKeeper(keeper);

        _newStrategy.setPendingManagement(management);

        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewStrategy(address(_newStrategy), _asset, _autoPool);

        deployments[_asset] = address(_newStrategy);
        return address(_newStrategy);
    }

    function setAddresses(address _management, address _performanceFeeRecipient, address _keeper) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    function isDeployedStrategy(address _strategy) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        return deployments[_asset] == _strategy;
    }
}
