// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "hardhat/console.sol";

error MIN_STAKING_AMOUNT_EXCEEDED();
error MAX_STAKING_AMOUNT_EXCEEDED();
error STAKING_NOT_STARTED();
error STAKING_ENDED();
error INVALID_STAKE_ID();
error STAKING_PROGRAM_ALREADY_EXISTS();
error STAKING_PROGRAM_DOES_NOT_EXISTS();
error ZERO_BALANCE();
error ZERO_STAKED();
error STAKING_DURATION_NOT_COMPLETED();
error ALREADY_CLAIMED();
error INVALID_MERKLE_ROOT();
error INVALID_MERKLE_PROOF();
error MERKLE_ROOT_NOT_SET();
error TOKEN_TRANSFER_DISABLED();
error STAKING_START_IN_PAST();
error MIN_STAKING_GREATER_THAN_MAX();

contract Staking is AccessControl, ReentrancyGuard, ERC20 {
    using MerkleProof for bytes32[];

    struct UserStake {
        uint256 staked;
        uint256 stakedAt;
        uint256 reward;
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
        uint256 staked;
        uint256 totalUsers;
        uint256 totalRewards;
        uint256 pendingRewards;
        uint256 claimedRewards;
    }
    uint256 public constant APY_DENOMINATOR = 10000;

    bytes32 private merkleRoot;

    mapping(address user => mapping(uint256 programID => UserStake[] stakes))
        private userStakes;

    uint256[] private stakingProgramIds;
    mapping(uint256 programID => StakingProgram program)
        private stakingPrograms;

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
    constructor(
        address _token,
        bytes32 _merkleRoot
    ) ERC20("StakingToken", "sTKN") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        stakingProgramIds.push(6);
        stakingToken = IERC20(_token);
        merkleRoot = _merkleRoot;
    }

    // Update whitelisted users
    function updateMerkleRoot(
        bytes32 _merkleRoot
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (merkleRoot == _merkleRoot) revert INVALID_MERKLE_ROOT();
        merkleRoot = _merkleRoot;
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
        if (stakingPrograms[_programID].start != 0)
            revert STAKING_PROGRAM_ALREADY_EXISTS();

        if (_start < block.timestamp) revert STAKING_START_IN_PAST();
        if (_minStaking > _maxStaking) revert MIN_STAKING_GREATER_THAN_MAX();

        stakingPrograms[_programID] = StakingProgram({
            minStaking: _minStaking,
            maxStaking: _maxStaking,
            start: _start,
            end: _end,
            staked: 0,
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
        if (stakingPrograms[_programID].start == 0)
            revert STAKING_PROGRAM_DOES_NOT_EXISTS();

        if (_start < block.timestamp) revert STAKING_START_IN_PAST();
        if (_minStaking > _maxStaking) revert MIN_STAKING_GREATER_THAN_MAX();

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
        if (_amount == 0) revert ZERO_BALANCE();
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
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) external nonReentrant returns (uint256) {
        if (merkleRoot == bytes32(0)) revert MERKLE_ROOT_NOT_SET();
        if (
            !MerkleProof.verify(
                _merkleProof,
                merkleRoot,
                keccak256(abi.encodePacked(msg.sender))
            )
        ) revert INVALID_MERKLE_PROOF();

        return _stake(_programID, msg.sender, _amount);
    }

    function _stake(
        uint256 _programID,
        address _user,
        uint256 _amount
    ) private returns (uint256) {
        if (_amount < stakingPrograms[_programID].minStaking)
            revert MIN_STAKING_AMOUNT_EXCEEDED();

        if (_amount > stakingPrograms[_programID].maxStaking)
            revert MAX_STAKING_AMOUNT_EXCEEDED();

        if (stakingPrograms[_programID].start > block.timestamp)
            revert STAKING_NOT_STARTED();

        if (stakingPrograms[_programID].end < block.timestamp)
            revert STAKING_ENDED();

        // Update User Info
        uint256 userReward = ((_amount *
            stakingPrograms[_programID].duration *
            stakingPrograms[_programID].apyRate) / 365 days) / APY_DENOMINATOR;

        uint256 stakeID = userStakes[msg.sender][_programID].length;
        if (stakeID == 0) {
            stakingPrograms[_programID].totalUsers += 1;
        }

        userStakes[_user][_programID].push(
            UserStake({
                staked: _amount,
                reward: userReward,
                stakedAt: block.timestamp,
                claimed: 0,
                claimedAt: 0
            })
        );

        // Update stake info
        stakingPrograms[_programID].totalStaked += _amount;
        stakingPrograms[_programID].staked += _amount;
        stakingPrograms[_programID].pendingRewards += userReward;
        stakingPrograms[_programID].totalRewards += userReward;

        // Transfer tokens to contract
        stakingToken.transferFrom(_user, address(this), _amount);

        // Mint staking tokens to user
        _mint(msg.sender, _amount + userReward);

        // emit Stake event
        emit Stake(_user, _programID, stakeID, _amount);

        return stakeID;
    }

    // Claim rewards
    function claim(
        uint256 _programID,
        uint256 _stakeID,
        bytes32[] calldata _merkleProof
    ) external nonReentrant {
        if (merkleRoot == bytes32(0)) revert MERKLE_ROOT_NOT_SET();
        if (
            !MerkleProof.verify(
                _merkleProof,
                merkleRoot,
                keccak256(abi.encodePacked(msg.sender))
            )
        ) revert INVALID_MERKLE_PROOF();
        _claim(_programID, _stakeID, msg.sender);
    }

    function _claim(
        uint256 _programID,
        uint256 _stakeID,
        address _user
    ) private {
        // check array
        if (userStakes[_user][_programID].length <= _stakeID)
            revert INVALID_STAKE_ID();

        if (userStakes[_user][_programID][_stakeID].staked == 0)
            revert ZERO_STAKED();

        if (userStakes[_user][_programID][_stakeID].claimed > 0)
            revert ALREADY_CLAIMED();

        if (
            userStakes[_user][_programID][_stakeID].stakedAt +
                stakingPrograms[_programID].duration >
            block.timestamp
        ) revert STAKING_DURATION_NOT_COMPLETED();

        // Update staking program info
        stakingPrograms[_programID].staked -= userStakes[_user][_programID][
            _stakeID
        ].staked;
        stakingPrograms[_programID].pendingRewards -= userStakes[_user][
            _programID
        ][_stakeID].reward;
        stakingPrograms[_programID].claimedRewards += userStakes[_user][
            _programID
        ][_stakeID].reward;

        // Update user stakes info
        userStakes[_user][_programID][_stakeID].claimed = userStakes[_user][
            _programID
        ][_stakeID].reward;
        userStakes[_user][_programID][_stakeID].claimedAt = block.timestamp;

        // Transfer tokens to user
        uint256 claimableAmount = userStakes[_user][_programID][_stakeID]
            .reward + userStakes[_user][_programID][_stakeID].staked;

        stakingToken.transfer(_user, claimableAmount);

        // Burn staking token
        _burn(msg.sender, claimableAmount);

        // emit Claim event
        emit Claim(_user, _programID, _stakeID, claimableAmount);
    }

    // Override the _update function to disable token transfers
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        if (!(from == address(0) || to == address(0))) {
            revert TOKEN_TRANSFER_DISABLED();
        }
        super._update(from, to, value);
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
        if (userStakes[_user][_programID][_stakeID].staked == 0)
            revert ZERO_STAKED();

        uint256 stakedDuration = block.timestamp -
            userStakes[_user][_programID][_stakeID].stakedAt;

        if (stakedDuration > stakingPrograms[_programID].duration) {
            return (
                userStakes[_user][_programID][_stakeID].reward,
                stakedDuration
            );
        }

        uint256 pendingReward = ((userStakes[_user][_programID][_stakeID]
            .staked *
            stakedDuration *
            stakingPrograms[_programID].apyRate) / 365 days) / APY_DENOMINATOR;
        return (pendingReward, stakedDuration);
    }

    // Get user stakes by stakeID
    function getUserStake(
        address _user,
        uint256 _programID,
        uint256 _stakeID
    ) external view returns (UserStake memory) {
        return userStakes[_user][_programID][_stakeID];
    }

    // Get user stakes
    function getUserStakes(
        address _user,
        uint256 _programID
    ) external view returns (UserStake[] memory) {
        return userStakes[_user][_programID];
    }

    // Get user stakes count
    function getUserStakesCount(
        address user_,
        uint256 _programID
    ) external view returns (uint256) {
        return userStakes[user_][_programID].length;
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
