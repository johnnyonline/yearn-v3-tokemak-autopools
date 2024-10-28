// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
// import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";

import {IRewarder} from "./interfaces/tokemak/IRewarder.sol";

/**
 * The `TokenizedStrategy` variable can be used to retrieve the strategies
 * specific storage data your contract.
 *
 *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
 *
 * This can not be used for write functions. Any TokenizedStrategy
 * variables that need to be updated post deployment will need to
 * come from an external call from the strategies specific `management`.
 */

// NOTE: To implement permissioned functions you can use the onlyManagement, onlyEmergencyAuthorized and onlyKeepers modifiers

contract TokemakStrategy is BaseStrategy, TradeFactorySwapper {

    event SlippageAdjusted(uint256 _slippage);

    using SafeERC20 for ERC20;

    uint256 public slippage = 5000; // 0.5%

    uint256 public constant MAX_SLIPPAGE = 50000; // 5%
    uint256 public constant SLIPPAGE_PRECISION = 100000;

    IERC4626 public immutable autoPool;

    IRewarder public immutable rewarder;

    constructor(
        address _asset,
        address _autoPool,
        address _rewarder,
        string memory _name
    ) BaseStrategy(_asset, _name) {
        autoPool = IERC4626(_autoPool);
        rewarder = IRewarder(_rewarder);

        ERC20(_asset).forceApprove(_autoPool, type(uint256).max);
        ERC20(_autoPool).forceApprove(_rewarder, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function adjustSlippage(uint256 _slippage) external onlyManagement {
        require(_slippage <= MAX_SLIPPAGE, "!max");
        slippage = _slippage;
        emit SlippageAdjusted(_slippage);
    }

    function setTradeFactory(address _tradeFactory) external onlyManagement {
        _setTradeFactory(_tradeFactory, address(asset));
    }

    function addToken(
        address _from,
        address _to
    ) external onlyManagement {
        require(_from != address(asset), "!asset");
        _addToken(_from, _to);
    }

    function removeToken(
        address _from,
        address _to
    ) external onlyManagement {
        _removeToken(_from, _to);
    }

    function claimRewards() external override onlyKeepers {
        _claimRewards();
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Can deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        rewarder.stake(
            address(this),
            autoPool.deposit(_amount, address(this))
        ); // @todo - consider not deploying anything here, only in harvest
    }

    /**
     * @dev Should attempt to free the '_amount' of 'asset'.
     *
     * NOTE: The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        uint256 _shares = autoPool.convertToShares(_amount);
        // uint256 _shares = autoPool.convertToShares(Math.min(_amount, _redeemableForShares()));
        rewarder.withdraw(address(this), _shares, false);
        autoPool.redeem(_shares, address(this), address(this));
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // @todo - claim rewards etc
        // @todo - check if not paused

        _totalAssets = _redeemableForShares() + asset.balanceOf(address(this));
    }

    function _claimRewards() internal override {
        // @todo - claim rewards
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies.
     *
     *   EX:
     *       return asset.balanceOf(yieldSource);
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(address /*_owner*/ ) public view override returns (uint256) {
        // return asset.balanceOf(address(this)) + autoPool.maxWithdraw(address(this));
        // @todo - add slipage
        return asset.balanceOf(address(this)) + _redeemableForShares();
        // return asset.balanceOf(address(this)) + _applySlippage(_redeemableForShares());
    }

    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     *
     */
    function availableDepositLimit(address _owner) public view override returns (uint256) {
        return autoPool.maxDeposit(_owner); // @todo - fix
    }

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * This will have no effect on PPS of the strategy till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     *
     * function _tend(uint256 _totalIdle) internal override {}
     */

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
     * function _tendTrigger() internal view override returns (bool) {}
     */

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     *
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(
            Math.min(
                _amount,
                _redeemableForShares()
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _redeemableForShares() private view returns (uint256) {
        return autoPool.convertToAssets(rewarder.balanceOf(address(this)));
    }

    function _applySlippage(uint256 _amount) private view returns (uint256) {
        return (_amount * (SLIPPAGE_PRECISION - slippage)) / SLIPPAGE_PRECISION;
    }
}
