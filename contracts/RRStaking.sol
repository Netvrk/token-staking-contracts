// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

error STAKING_NOT_STARTED();
error STAKING_RANGE_INVALID();
error STAKING_ENDED();
error TOKEN_TRANSFER_DISABLED();
error STAKING_START_IN_PAST();
error MIN_STAKING_AMOUNT_EXCEEDED();
error MAX_STAKING_AMOUNT_EXCEEDED();
error MIN_STAKING_GREATER_THAN_MAX();
error INVALID_STAKED_AMOUNT();
error STAKING_LOCK_PERIOD_NOT_OVER();

contract RRStaking is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable
{
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    struct StakingProgram {
        uint256 minStaking;
        uint256 maxStaking;
        uint256 start;
        uint256 end;
        uint256 totalStaked;
        uint256 staked;
    }

    IERC20 private stakingToken;

    StakingProgram private stakingProgram;

    uint256 private lockPeriod;

    mapping(address => uint256) private stakingTimestamps;

    event Stake(address indexed user, uint256 amount, uint256 stakedAt);

    event Unstake(address indexed user, uint256 amount, uint256 unstakedAt);

    /**
     * @dev Initializes the contract with the given token and default staking program parameters.
     * @param _token Address of the staking token.
     */
    function initialize(address _token, address _manager) public initializer {
        __ERC20_init("StakingToken", "sTKN");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, _manager);
        stakingToken = IERC20(_token);

        stakingProgram = StakingProgram({
            minStaking: 1 ether,
            maxStaking: 10000000 ether,
            start: block.timestamp,
            end: block.timestamp + 365 days,
            staked: 0,
            totalStaked: 0
        });

        lockPeriod = 30 days; // Default lock period in days
    }

    /**
     * @dev Set the lock period for the staked tokens.
     * @param _lockPeriodInDays Lock period in days
     */
    function setLockPeriod(
        uint256 _lockPeriodInDays
    ) external onlyRole(MANAGER_ROLE) {
        lockPeriod = _lockPeriodInDays * 1 days;
    }

    /**
     * @dev Updates the staking program parameters.
     * @param _minStaking Minimum staking amount.
     * @param _maxStaking Maximum staking amount.
     * @param _start Start time of the staking program.
     * @param _end End time of the staking program.
     */
    function updateStakingProgram(
        uint256 _minStaking,
        uint256 _maxStaking,
        uint256 _start,
        uint256 _end
    ) external onlyRole(MANAGER_ROLE) {
        if (_start <= block.timestamp) revert STAKING_START_IN_PAST();
        if (_end <= _start) revert STAKING_RANGE_INVALID();
        if (_minStaking >= _maxStaking) revert MIN_STAKING_GREATER_THAN_MAX();

        stakingProgram.minStaking = _minStaking;
        stakingProgram.maxStaking = _maxStaking;
        stakingProgram.start = _start;
        stakingProgram.end = _end;
    }

    /**
     * @dev Stakes tokens.
     * @param _amount Amount of tokens to stake.
     */
    function stake(uint256 _amount) external nonReentrant {
        if (_amount < stakingProgram.minStaking)
            revert MIN_STAKING_AMOUNT_EXCEEDED();

        if (_amount > stakingProgram.maxStaking)
            revert MAX_STAKING_AMOUNT_EXCEEDED();

        if (stakingProgram.start >= block.timestamp)
            revert STAKING_NOT_STARTED();

        if (stakingProgram.end <= block.timestamp) revert STAKING_ENDED();

        stakingProgram.totalStaked += _amount;
        stakingProgram.staked += _amount;

        stakingTimestamps[msg.sender] = block.timestamp;

        stakingToken.transferFrom(msg.sender, address(this), _amount);

        _mint(msg.sender, _amount);

        emit Stake(msg.sender, _amount, block.timestamp);
    }

    /**
     * @dev Unstakes tokens.
     * @param _amount Amount of tokens to unstake.
     */
    function unstake(uint256 _amount) external nonReentrant {
        if (_amount <= 0) revert INVALID_STAKED_AMOUNT();
        if (balanceOf(msg.sender) < _amount) revert INVALID_STAKED_AMOUNT();
        if (block.timestamp < stakingTimestamps[msg.sender] + lockPeriod)
            revert STAKING_LOCK_PERIOD_NOT_OVER();

        stakingProgram.staked -= _amount;

        _burn(msg.sender, _amount);

        stakingToken.transfer(msg.sender, _amount);

        emit Unstake(msg.sender, _amount, block.timestamp);
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
     * @dev Returns the details of the staking program.
     * @return StakingProgram Details of the staking program.
     */
    function getStakingProgram() external view returns (StakingProgram memory) {
        return stakingProgram;
    }

    /**
     * @dev Returns the address of the staking token.
     * @return address Address of the staking token.
     */
    function getStakingToken() external view returns (address) {
        return address(stakingToken);
    }

    /**
     * @dev Returns the duration for which the user has staked the tokens.
     * @param _user Address of the user.
     * @return uint256 Duration for which the user has staked the tokens.
     */
    function getStakedDuration(address _user) external view returns (uint256) {
        if (stakingTimestamps[_user] == 0) return 0;
        return block.timestamp - stakingTimestamps[_user];
    }

    /**
     * @dev Authorizes the upgrade of the contract.
     * @param newImplementation Address of the new implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}
}
