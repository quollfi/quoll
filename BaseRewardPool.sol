// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
/**
 *Submitted for verification at Etherscan.io on 2020-07-17
 */

/*
   ____            __   __        __   _
  / __/__ __ ___  / /_ / /  ___  / /_ (_)__ __
 _\ \ / // // _ \/ __// _ \/ -_)/ __// / \ \ /
/___/ \_, //_//_/\__//_//_/\__/ \__//_/ /_\_\
     /___/

* Synthetix: BaseRewardPool.sol
*
* Docs: https://docs.synthetix.io/
*
*
* MIT License
* ===========
*
* Copyright (c) 2020 Synthetix
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./Interfaces/IBaseRewardPool.sol";
import "./Interfaces/IWombatBooster.sol";

contract BaseRewardPool is IBaseRewardPool, OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public operator;
    address public booster;
    uint256 public pid;

    IERC20 public override stakingToken;
    address[] public rewardTokens;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    struct Reward {
        uint256 rewardPerTokenStored;
        uint256 queuedRewards;
    }

    struct UserReward {
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
    }

    mapping(address => Reward) public rewards;
    mapping(address => bool) public isRewardToken;

    mapping(address => mapping(address => UserReward)) public userRewards;

    mapping(address => bool) public access;

    function initialize(address _operator) public initializer {
        __Ownable_init();

        operator = _operator;

        emit OperatorUpdated(_operator);
    }

    function setParams(
        address _booster,
        uint256 _pid,
        address _stakingToken,
        address _rewardToken
    ) external override {
        require(msg.sender == owner() || msg.sender == operator, "!auth");

        require(address(booster) == address(0), "params has already been set");

        booster = _booster;

        pid = _pid;
        stakingToken = IERC20(_stakingToken);

        addRewardToken(_rewardToken);

        setAccess(_booster, true);

        emit BoosterUpdated(_booster);
    }

    function addRewardToken(address _rewardToken) internal {
        if (isRewardToken[_rewardToken]) {
            return;
        }
        rewardTokens.push(_rewardToken);
        isRewardToken[_rewardToken] = true;

        emit RewardTokenAdded(_rewardToken);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    modifier updateReward(address _account) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            UserReward storage userReward = userRewards[_account][rewardToken];
            userReward.rewards = earned(_account, rewardToken);
            userReward.userRewardPerTokenPaid = rewards[rewardToken]
                .rewardPerTokenStored;
        }

        _;
    }

    function getRewardTokensLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    function earned(address _account, address _rewardToken)
        public
        view
        override
        returns (uint256)
    {
        Reward memory reward = rewards[_rewardToken];
        UserReward memory userReward = userRewards[_account][_rewardToken];
        return
            balanceOf(_account)
                .mul(
                    reward.rewardPerTokenStored.sub(
                        userReward.userRewardPerTokenPaid
                    )
                )
                .div(1e18)
                .add(userReward.rewards);
    }

    function stake(uint256 _amount) public override updateReward(msg.sender) {
        require(_amount > 0, "RewardPool : Cannot stake 0");

        _totalSupply = _totalSupply.add(_amount);
        _balances[msg.sender] = _balances[msg.sender].add(_amount);

        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    function stakeAll() external override {
        uint256 balance = stakingToken.balanceOf(msg.sender);
        stake(balance);
    }

    function stakeFor(address _for, uint256 _amount)
        external
        override
        updateReward(_for)
    {
        require(_amount > 0, "RewardPool : Cannot stake 0");

        //give to _for
        _totalSupply = _totalSupply.add(_amount);
        _balances[_for] = _balances[_for].add(_amount);

        //take away from sender
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(_for, _amount);
    }

    function withdraw(uint256 amount) public override updateReward(msg.sender) {
        require(amount > 0, "RewardPool : Cannot withdraw 0");

        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);

        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);

        getReward(msg.sender);
    }

    function withdrawAll() external override {
        withdraw(_balances[msg.sender]);
    }

    function withdrawAndUnwrap(uint256 amount) public updateReward(msg.sender) {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);

        //tell booster to withdraw from here directly to user
        IWombatBooster(booster).withdrawTo(pid, amount, msg.sender);
        emit Withdrawn(msg.sender, amount);

        //get rewards too
        getReward(msg.sender);
    }

    function withdrawAllAndUnwrap() external {
        withdrawAndUnwrap(_balances[msg.sender]);
    }

    function getReward(address _account)
        public
        override
        updateReward(_account)
    {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            uint256 reward = earned(_account, rewardToken);
            if (reward > 0) {
                userRewards[_account][rewardToken].rewards = 0;
                IERC20(rewardToken).safeTransfer(_account, reward);
                IWombatBooster(booster).rewardClaimed(
                    pid,
                    _account,
                    rewardToken,
                    reward
                );
                emit RewardPaid(_account, rewardToken, reward);
            }
        }
    }

    function donate(address _rewardToken, uint256 _amount) external override {
        require(isRewardToken[_rewardToken], "invalid token");
        IERC20(_rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        rewards[_rewardToken].queuedRewards = rewards[_rewardToken]
            .queuedRewards
            .add(_amount);
    }

    function queueNewRewards(address _rewardToken, uint256 _rewards)
        external
        override
    {
        require(access[msg.sender], "!auth");

        addRewardToken(_rewardToken);

        Reward storage rewardInfo = rewards[_rewardToken];

        if (totalSupply() == 0) {
            rewardInfo.queuedRewards = rewardInfo.queuedRewards.add(_rewards);
            return;
        }

        _rewards = _rewards.add(rewardInfo.queuedRewards);
        rewardInfo.queuedRewards = 0;

        rewardInfo.rewardPerTokenStored = rewardInfo.rewardPerTokenStored.add(
            _rewards.mul(1e18).div(totalSupply())
        );
        emit RewardAdded(_rewardToken, _rewards);
    }

    function setAccess(address _address, bool _status) public override {
        require(msg.sender == owner() || msg.sender == booster, "!auth");
        access[_address] = _status;
    }
}
