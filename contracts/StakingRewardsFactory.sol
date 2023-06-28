// SPDX-License-Identifier: MIT

/*
使用说明
1.设置stakingToken和rewardToken
2.调用initial函数设置，传入时间和数量
3.调用stake可以得到reward
*/
pragma solidity ^0.8;

contract StakingRewardsFactory {

    struct StakingModel{
        IERC20   stakingToken;
        IERC20   rewardsToken;
        //uint duration;
        //uint rewardAmount;
        address  owner;

        // Duration of rewards to be paid out (in seconds)
        uint  duration;
        // Timestamp of when the rewards finish
        uint  finishAt;
        // Minimum of last updated time and reward finish time
        uint  updatedAt;
        // Reward to be paid out per second
        uint  rewardRate;
        // Sum of (reward rate * dt * 1e18 / total supply)
        uint  rewardPerTokenStored;
        // User address => rewardPerTokenStored
        mapping(address => uint)  userRewardPerTokenPaid;
        // User address => rewards to be claimed
        mapping(address => uint)  rewards;

        // Total staked
        uint  totalSupply;
        // User address => staked amount
        mapping(address => uint)  balanceOf;
    }

    mapping (uint => StakingModel) public dataInfo;

    address public owner;


    uint public totalPool;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not authorized");
        _;
    }

    modifier updateReward(uint _poolNum ,address _account) {
        dataInfo[_poolNum].rewardPerTokenStored = rewardPerToken(_poolNum);
        dataInfo[_poolNum].updatedAt = lastTimeRewardApplicable(_poolNum);

        if (_account != address(0)) {
            dataInfo[_poolNum].rewards[_account] = earned(_account,_poolNum);
            dataInfo[_poolNum].userRewardPerTokenPaid[_account] = dataInfo[_poolNum].rewardPerTokenStored;
        }

        _;
    }

    function createStakingRewards(
        address _stakingToken,
        address _rewardToken,
        uint _duration,
        uint _amount,
        address _owner 
    ) public onlyOwner {
        dataInfo[totalPool].stakingToken = IERC20(_stakingToken);
        dataInfo[totalPool].rewardsToken = IERC20(_rewardToken);
        dataInfo[totalPool].owner = _owner;
        initial(_amount, _duration, totalPool);
        totalPool ++;


    }

    function initial(uint _amount, uint _duration,uint _poolNum) public onlyOwner{
        setRewardsDuration(_duration,_poolNum);
        dataInfo[_poolNum].rewardsToken.transferFrom(msg.sender, address(this), _amount);
        notifyRewardAmount(_amount,_poolNum);


    }

    function lastTimeRewardApplicable(uint _poolNum) public view returns (uint) {
        return _min(dataInfo[_poolNum].finishAt, block.timestamp);
    }

    function rewardPerToken(uint _poolNum) public view returns (uint) {
        if (dataInfo[_poolNum].totalSupply == 0) {
            return dataInfo[_poolNum].rewardPerTokenStored;
        }

        return
            dataInfo[_poolNum].rewardPerTokenStored +
            (dataInfo[_poolNum].rewardRate * (lastTimeRewardApplicable(_poolNum) - dataInfo[_poolNum].updatedAt) * 1e18) /
            dataInfo[_poolNum].totalSupply;
    }

    function resetToken(address _stakingToken, address _rewardToken, uint _poolNum) public onlyOwner{
        dataInfo[_poolNum].stakingToken = IERC20(_stakingToken);
        dataInfo[_poolNum].rewardsToken = IERC20(_rewardToken);

    }

    function stake(uint _amount,uint _poolNum) public updateReward(_poolNum,msg.sender) {
        require(_amount > 0, "amount = 0");
        dataInfo[_poolNum].stakingToken.transferFrom(msg.sender, address(this), _amount);
        dataInfo[_poolNum].balanceOf[msg.sender] += _amount;
        dataInfo[_poolNum].totalSupply += _amount;
    }

    function withdraw(uint _amount,uint _poolNum) public updateReward(_poolNum,msg.sender) {
        require(_amount > 0, "amount = 0");
        dataInfo[_poolNum].balanceOf[msg.sender] -= _amount;
        dataInfo[_poolNum].totalSupply -= _amount;
        dataInfo[_poolNum].stakingToken.transfer(msg.sender, _amount);
    }

    function earned(address _account,uint _poolNum) public view returns (uint) {
        return
            ((dataInfo[_poolNum].balanceOf[_account] *
                (rewardPerToken(_poolNum) - dataInfo[_poolNum].userRewardPerTokenPaid[_account])) / 1e18) +
            dataInfo[_poolNum].rewards[_account];
    }

    function getReward(uint _poolNum) external updateReward(_poolNum,msg.sender) {
        uint reward = dataInfo[_poolNum].rewards[msg.sender];
        if (reward > 0) {
            dataInfo[_poolNum].rewards[msg.sender] = 0;
            dataInfo[_poolNum].rewardsToken.transfer(msg.sender, reward);
        }
    }
    //设置可以挖矿的时间，单位s
    function setRewardsDuration(uint _duration,uint _poolNum) internal  {
        require(dataInfo[_poolNum].finishAt < block.timestamp, "reward duration not finished");
        dataInfo[_poolNum].duration = _duration;
    }
    //可获取的ERC20数量
    function notifyRewardAmount(
        uint _amount,
        uint _poolNum
    ) internal  updateReward(_poolNum,address(0)) {
        if (block.timestamp >= dataInfo[_poolNum].finishAt) {
            dataInfo[_poolNum].rewardRate = _amount / dataInfo[_poolNum].duration;
        } else {
            uint remainingRewards = (dataInfo[_poolNum].finishAt - block.timestamp) * dataInfo[_poolNum].rewardRate;
            dataInfo[_poolNum].rewardRate = (_amount + remainingRewards) / dataInfo[_poolNum].duration;
        }

        require(dataInfo[_poolNum].rewardRate > 0, "reward rate = 0");
        require(
            dataInfo[_poolNum].rewardRate * dataInfo[_poolNum].duration <= dataInfo[_poolNum].rewardsToken.balanceOf(address(this)),
            "reward amount > balance"
        );

        dataInfo[_poolNum].finishAt = block.timestamp + dataInfo[_poolNum].duration;
        dataInfo[_poolNum].updatedAt = block.timestamp;


    }

    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }

    function getBalanceOfContract(uint _poolNum) public view returns (uint) {
        return dataInfo[_poolNum].rewardsToken.balanceOf(address(this));
    }

    function withdrawRewardToken(uint _poolNum) external onlyOwner {
        require(block.timestamp >= dataInfo[_poolNum].finishAt, "still product rewardToken");
        dataInfo[_poolNum].rewardsToken.transfer(msg.sender, getBalanceOfContract(_poolNum));
    }

}

interface IERC20 {
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}
