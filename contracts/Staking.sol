// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "hardhat/console.sol";

contract Staking is AccessControl, ReentrancyGuard {
    struct UserStake {
        uint256 staked;
        uint256 stakedAt;
        uint256 totalReward;
        uint256 claimed;
        uint256 claimedAt;
    }

    struct StakingProgram {
        uint256 duration;
        uint256 apyRate;
        uint256 minStaking;
        uint256 maxStaking;
        uint256 start;
        uint256 end;
        uint256 totalStaked;
        uint256 totalUsers;
        uint256 totalRewards;
        uint256 pendingRewards;
        uint256 claimedRewards;
    }
    uint256 public constant APY_DENOMINATOR = 10000;

    mapping(address => UserStake[]) private userStakes;

    uint256[] private stakingProgramIds;
    mapping(uint256 => StakingProgram) private stakingPrograms;

    IERC20 public stakingToken;

    // New stake from user
    event Stake(
        address indexed user,
        uint256 indexed programID,
        uint256 indexed stakeID,
        uint256 amount
    );
    // New claim from user
    event Claim(
        address indexed user,
        uint256 indexed programID,
        uint256 indexed stakeID,
        uint256 amount
    );

    /**
    ////////////////////////////////////////////////////
    // Admin Functions 
    ///////////////////////////////////////////////////
    */
    constructor(address _initialOwner, address _token) {
        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);
        stakingPrograms[6] = StakingProgram({
            minStaking: 0.1 ether,
            maxStaking: 100 ether,
            start: block.timestamp,
            end: block.timestamp + 30 days,
            totalStaked: 0,
            totalUsers: 0,
            totalRewards: 0,
            pendingRewards: 0,
            claimedRewards: 0,
            apyRate: 1000,
            duration: 6 * 30 days
        });
        stakingProgramIds.push(6);
        stakingToken = IERC20(_token);
    }

    // Add new stake program
    function addStakingProgram(
        uint256 _programID,
        uint256 _durationDays,
        uint256 _apyRate,
        uint256 _minStaking,
        uint256 _maxStaking,
        uint256 _start,
        uint256 _end
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            stakingPrograms[_programID].start == 0,
            "STAKING_PROGRAM_ALREADY_EXISTS"
        );
        stakingPrograms[_programID] = StakingProgram({
            minStaking: _minStaking,
            maxStaking: _maxStaking,
            start: _start,
            end: _end,
            totalStaked: 0,
            totalUsers: 0,
            totalRewards: 0,
            pendingRewards: 0,
            claimedRewards: 0,
            apyRate: _apyRate,
            duration: _durationDays * 1 days
        });
        stakingProgramIds.push(_programID);
    }

    // Update existing stake program
    function updateStakingProgram(
        uint256 _programID,
        uint256 _durationDays,
        uint256 _apyRate,
        uint256 _minStaking,
        uint256 _maxStaking,
        uint256 _start,
        uint256 _end
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            stakingPrograms[_programID].start != 0,
            "STAKING_PROGRAM_NOT_EXISTS"
        );
        stakingPrograms[_programID].duration = _durationDays * 1 days;
        stakingPrograms[_programID].apyRate = _apyRate;
        stakingPrograms[_programID].minStaking = _minStaking;
        stakingPrograms[_programID].maxStaking = _maxStaking;
        stakingPrograms[_programID].start = _start;
        stakingPrograms[_programID].end = _end;
    }

    // Update staking token
    function updateStakingToken(
        address _token
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingToken = IERC20(_token);
    }

    // Withdraw tokens from contract by owner
    function withdrawStuckedFunds(
        address _token,
        address _treasury
    ) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        require(_amount > 0, "ZERO_BALANCE");
        IERC20(_token).transfer(_treasury, _amount);
    }

    /**
    ////////////////////////////////////////////////////
    // Public Functions 
    ///////////////////////////////////////////////////
     */
    // Stake tokens
    function stake(
        uint256 _programID,
        uint256 _amount
    ) external nonReentrant returns (uint256) {
        return _stake(_programID, msg.sender, _amount);
    }

    function _stake(
        uint256 _programID,
        address _user,
        uint256 _amount
    ) private returns (uint256) {
        require(
            _amount >= stakingPrograms[_programID].minStaking,
            "MIN_STAKING_AMOUNT_EXCEEDED"
        );
        require(
            _amount <= stakingPrograms[_programID].maxStaking,
            "MAX_STAKING_AMOUNT_EXCEEDED"
        );
        require(
            stakingPrograms[_programID].start <= block.timestamp,
            "STAKING_NOT_STARTED"
        );
        require(
            stakingPrograms[_programID].end >= block.timestamp,
            "STAKING_ENDED"
        );
        // Update User Info
        uint256 totalReward = ((_amount *
            stakingPrograms[_programID].duration *
            stakingPrograms[_programID].apyRate) / 365 days) / APY_DENOMINATOR;

        userStakes[_user].push(
            UserStake({
                staked: _amount,
                totalReward: totalReward,
                stakedAt: block.timestamp,
                claimed: 0,
                claimedAt: 0
            })
        );

        // Update stake info
        stakingPrograms[_programID].totalStaked += _amount;

        uint256 stakeID = userStakes[msg.sender].length;
        if (stakeID == 0) {
            stakingPrograms[_programID].totalUsers += 1;
        }
        stakingPrograms[_programID].pendingRewards += totalReward;
        stakingPrograms[_programID].totalRewards += totalReward;

        // Transfer tokens to contract
        stakingToken.transferFrom(_user, address(this), _amount);

        // emit Stake event
        emit Stake(_user, _programID, stakeID, _amount);

        return stakeID;
    }

    // Claim rewards
    function claim(uint256 _programID, uint256 _stakeID) external nonReentrant {
        _claim(_programID, _stakeID, msg.sender);
    }

    function _claim(
        uint256 _programID,
        uint256 _stakeID,
        address _user
    ) private {
        require(userStakes[_user][_stakeID].staked > 0, "NO_STAKED_AMOUNT");
        require(
            userStakes[_user][_stakeID].stakedAt +
                stakingPrograms[_programID].duration <=
                block.timestamp,
            "STAKING_DURATION_NOT_COMPLETED"
        );
        require(
            userStakes[_user][_stakeID].claimed <
                userStakes[_user][_stakeID].totalReward,
            "ALREADY_CLAIMED"
        );

        // Update stake info
        stakingPrograms[_programID].totalStaked -= userStakes[_user][_stakeID]
            .staked;
        stakingPrograms[_programID].totalUsers -= 1;
        stakingPrograms[_programID].pendingRewards -= userStakes[_user][
            _stakeID
        ].totalReward;
        stakingPrograms[_programID].claimedRewards += userStakes[_user][
            _stakeID
        ].totalReward;

        // Update user stakes info
        userStakes[_user][_stakeID].claimed = userStakes[_user][_stakeID]
            .totalReward;
        userStakes[_user][_stakeID].claimedAt = block.timestamp;

        // Transfer tokens to user
        uint256 claimableAmount = userStakes[_user][_stakeID].totalReward +
            userStakes[_user][_stakeID].staked;
        stakingToken.transfer(_user, claimableAmount);

        // emit Claim event
        emit Claim(_user, _programID, _stakeID, claimableAmount);
    }

    /**
    ////////////////////////////////////////////////////
    // View functions
    ///////////////////////////////////////////////////
     */

    // Get pending rewards
    function getPendingRewards(
        address _user,
        uint256 _programID,
        uint256 _stakeID
    ) external view returns (uint256 reward, uint256 duration) {
        require(userStakes[_user][_stakeID].staked > 0, "NO_STAKED_AMOUNT");

        uint256 stakedDuration = block.timestamp -
            userStakes[_user][_stakeID].stakedAt;

        if (stakedDuration > stakingPrograms[_programID].duration) {
            return (userStakes[_user][_stakeID].totalReward, stakedDuration);
        }

        uint256 pendingReward = ((userStakes[_user][_stakeID].staked *
            stakedDuration *
            stakingPrograms[_programID].apyRate) / 365 days) / APY_DENOMINATOR;
        return (pendingReward, stakedDuration);
    }

    // Get user stakes by stakeID
    function getUserStake(
        address _user,
        uint256 _stakeID
    ) external view returns (UserStake memory) {
        return userStakes[_user][_stakeID];
    }

    // Get user stakes
    function getUserStakes(
        address _user
    ) external view returns (UserStake[] memory) {
        return userStakes[_user];
    }

    // Get user stakes count
    function getUserStakesCount(address user_) external view returns (uint256) {
        return userStakes[user_].length;
    }

    // Get stake program info
    function getStakingProgram(
        uint256 programID_
    ) external view returns (StakingProgram memory) {
        return stakingPrograms[programID_];
    }

    // Get stake program ids
    function getStakingProgramIds() external view returns (uint256[] memory) {
        return stakingProgramIds;
    }
}
