// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

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

contract Staking is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable
{
    using MerkleProof for bytes32[];

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

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
    uint256 private constant APY_DENOMINATOR = 10000;

    bytes32 private merkleRoot;

    IERC20 private stakingToken;

    uint256[] private stakingProgramIds;

    mapping(uint256 => StakingProgram) private stakingPrograms;

    mapping(address => mapping(uint256 => UserStake[])) private userStakes;

    event Stake(
        address indexed user,
        uint256 indexed programID,
        uint256 indexed stakeID,
        uint256 amount
    );

    event Claim(
        address indexed user,
        uint256 indexed programID,
        uint256 indexed stakeID,
        uint256 amount,
        uint256 reward
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the given token and merkle root.
     * @param _token Address of the staking token.
     * @param _manager Address of the manager.
     */
    function initialize(address _token, address _manager) public initializer {
        __ERC20_init("StakingToken", "sTKN");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, _manager);
        stakingToken = IERC20(_token);
    }

    /**
     * @dev Updates the merkle root for whitelisted users.
     * @param _merkleRoot New merkle root.
     */
    function updateMerkleRoot(
        bytes32 _merkleRoot
    ) external onlyRole(MANAGER_ROLE) {
        if (merkleRoot == _merkleRoot) revert INVALID_MERKLE_ROOT();
        if (_merkleRoot == bytes32(0)) revert INVALID_MERKLE_ROOT();
        merkleRoot = _merkleRoot;
    }

    /**
     * @dev Adds a new staking program.
     * @param _programID ID of the staking program.
     * @param _durationDays Duration of the staking program in days.
     * @param _apyRate Annual percentage yield rate.
     * @param _minStaking Minimum staking amount.
     * @param _maxStaking Maximum staking amount.
     * @param _start Start time of the staking program.
     * @param _end End time of the staking program.
     */
    function addStakingProgram(
        uint256 _programID,
        uint256 _durationDays,
        uint256 _apyRate,
        uint256 _minStaking,
        uint256 _maxStaking,
        uint256 _start,
        uint256 _end
    ) external onlyRole(MANAGER_ROLE) {
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

    /**
     * @dev Updates an existing staking program.
     * @param _programID ID of the staking program.
     * @param _durationDays Duration of the staking program in days.
     * @param _apyRate Annual percentage yield rate.
     * @param _minStaking Minimum staking amount.
     * @param _maxStaking Maximum staking amount.
     * @param _start Start time of the staking program.
     * @param _end End time of the staking program.
     */
    function updateStakingProgram(
        uint256 _programID,
        uint256 _durationDays,
        uint256 _apyRate,
        uint256 _minStaking,
        uint256 _maxStaking,
        uint256 _start,
        uint256 _end
    ) external onlyRole(MANAGER_ROLE) {
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

    /**
     * @dev Updates the staking token.
     * @param _token Address of the new staking token.
     */
    function updateStakingToken(
        address _token
    ) external onlyRole(MANAGER_ROLE) {
        stakingToken = IERC20(_token);
    }

    /**
     * @dev Withdraws tokens from the contract to the treasury.
     * @param _token Address of the token to withdraw.
     * @param _treasury Address of the treasury.
     */
    function withdrawFunds(
        address _token,
        address _treasury
    ) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        if (_amount == 0) revert ZERO_BALANCE();
        IERC20(_token).transfer(_treasury, _amount);
    }

    /**
     * @dev Stakes tokens in a staking program.
     * @param _programID ID of the staking program.
     * @param _amount Amount of tokens to stake.
     * @param _merkleProof Merkle proof for whitelisted users.
     * @return stakeID ID of the created stake.
     */
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

    /**
     * @dev Internal function to handle staking logic.
     * @param _programID ID of the staking program.
     * @param _user Address of the user staking tokens.
     * @param _amount Amount of tokens to stake.
     * @return stakeID ID of the created stake.
     */
    function _stake(
        uint256 _programID,
        address _user,
        uint256 _amount
    ) internal returns (uint256) {
        if (_amount < stakingPrograms[_programID].minStaking)
            revert MIN_STAKING_AMOUNT_EXCEEDED();

        if (_amount > stakingPrograms[_programID].maxStaking)
            revert MAX_STAKING_AMOUNT_EXCEEDED();

        if (stakingPrograms[_programID].start > block.timestamp)
            revert STAKING_NOT_STARTED();

        if (stakingPrograms[_programID].end < block.timestamp)
            revert STAKING_ENDED();

        uint256 durationInDays = stakingPrograms[_programID].duration / 1 days;
        uint256 userReward = ((_amount *
            durationInDays *
            stakingPrograms[_programID].apyRate) / 365) / APY_DENOMINATOR;

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

        stakingPrograms[_programID].totalStaked += _amount;
        stakingPrograms[_programID].staked += _amount;
        stakingPrograms[_programID].pendingRewards += userReward;
        stakingPrograms[_programID].totalRewards += userReward;

        _mint(msg.sender, _amount + userReward);

        stakingToken.transferFrom(_user, address(this), _amount);

        emit Stake(_user, _programID, stakeID, _amount);

        return stakeID;
    }

    /**
     * @dev Claims rewards for a specific stake.
     * @param _programID ID of the staking program.
     * @param _stakeID ID of the stake.
     * @param _merkleProof Merkle proof for whitelisted users.
     */
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

    /**
     * @dev Internal function to handle claim logic.
     * @param _programID ID of the staking program.
     * @param _stakeID ID of the stake.
     * @param _user Address of the user claiming rewards.
     */
    function _claim(
        uint256 _programID,
        uint256 _stakeID,
        address _user
    ) internal {
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

        stakingPrograms[_programID].staked -= userStakes[_user][_programID][
            _stakeID
        ].staked;

        stakingPrograms[_programID].pendingRewards -= userStakes[_user][
            _programID
        ][_stakeID].reward;

        stakingPrograms[_programID].claimedRewards += userStakes[_user][
            _programID
        ][_stakeID].reward;

        userStakes[_user][_programID][_stakeID].claimed = userStakes[_user][
            _programID
        ][_stakeID].reward;

        userStakes[_user][_programID][_stakeID].claimedAt = block.timestamp;

        uint256 claimableAmount = userStakes[_user][_programID][_stakeID]
            .reward + userStakes[_user][_programID][_stakeID].staked;

        _burn(msg.sender, claimableAmount);

        stakingToken.transfer(_user, claimableAmount);

        emit Claim(
            _user,
            _programID,
            _stakeID,
            claimableAmount,
            userStakes[_user][_programID][_stakeID].reward
        );
    }

    /**
     * @dev Overrides the _update function to disable token transfers.
     * @param from Address of the sender.
     * @param to Address of the receiver.
     * @param value Amount of tokens to transfer.
     */
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
     * @dev Authorizes the upgrade of the contract.
     * @param newImplementation Address of the new implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @dev Returns the pending rewards for a specific stake.
     * @param _user Address of the user.
     * @param _programID ID of the staking program.
     * @param _stakeID ID of the stake.
     * @return reward Pending reward amount.
     * @return duration Duration of the stake.
     */
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

    /**
     * @dev Returns the details of a specific user stake.
     * @param _user Address of the user.
     * @param _programID ID of the staking program.
     * @param _stakeID ID of the stake.
     * @return UserStake Details of the user stake.
     */
    function getUserStake(
        address _user,
        uint256 _programID,
        uint256 _stakeID
    ) external view returns (UserStake memory) {
        return userStakes[_user][_programID][_stakeID];
    }

    /**
     * @dev Returns all stakes of a user in a specific staking program.
     * @param _user Address of the user.
     * @param _programID ID of the staking program.
     * @return UserStake[] Array of user stakes.
     */
    function getUserStakes(
        address _user,
        uint256 _programID
    ) external view returns (UserStake[] memory) {
        return userStakes[_user][_programID];
    }

    /**
     * @dev Returns the count of stakes of a user in a specific staking program.
     * @param user_ Address of the user.
     * @param _programID ID of the staking program.
     * @return uint256 Count of user stakes.
     */
    function getUserStakesCount(
        address user_,
        uint256 _programID
    ) external view returns (uint256) {
        return userStakes[user_][_programID].length;
    }

    /**
     * @dev Returns the details of a specific staking program.
     * @param programID_ ID of the staking program.
     * @return StakingProgram Details of the staking program.
     */
    function getStakingProgram(
        uint256 programID_
    ) external view returns (StakingProgram memory) {
        return stakingPrograms[programID_];
    }

    /**
     * @dev Returns the address of the staking token.
     * @return address Address of the staking token.
     */
    function getStakingToken() external view returns (address) {
        return address(stakingToken);
    }

    /**
     * @dev Returns the IDs of all staking programs.
     * @return uint256[] Array of staking program IDs.
     */
    function getStakingProgramIds() external view returns (uint256[] memory) {
        return stakingProgramIds;
    }
}
