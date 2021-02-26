// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./DGNZToken.sol";
import "./DGNZBar.sol";

abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() internal {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}


// MasterChef is the master of DGNZ. He can make DGNZ and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once DGNZ is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of DGNZs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accDGNZPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accDGNZPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. DGNZs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that DGNZs distribution occurs.
        uint256 accDGNZPerShare; // Accumulated DGNZs per share, times 1e12. See below.
    }

    // The DGNZ and xDGNZ TOKEN!
    DGNZToken public dgnz;
    DGNZBar public xdgnz;

    //Games
    address public roulette;
    address public coinflip;
    address public degen;

    // Dev address.
    address public devaddr;
    // DGNZ tokens created per block.
    uint256 public dgnzPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when DGNZ mining starts.
    uint256 public startBlock;

    uint8 public devfees = 6;
    uint8 public coinflipfees = 4;
    uint8 public roulettefees = 4;
    uint8 public degenfees = 1;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        DGNZToken _dgnz,
        DGNZBar _xdgnz,
        address _devaddr,
        uint256 _dgnzPerBlock,
        uint256 _startBlock
    ) public {
        dgnz = _dgnz;
        xdgnz = _xdgnz;
        devaddr = _devaddr;
        dgnzPerBlock = _dgnzPerBlock*10**18;
        startBlock = _startBlock;
        roulette = _devaddr;
        coinflip = _devaddr;
        degen = _devaddr;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accDGNZPerShare: 0
        }));
        updateStakingPool();
    }

    //Change Block Reward
    function setdgnzPerBlock(uint256 _dgnzPerBlock) public onlyOwner {
        dgnzPerBlock = _dgnzPerBlock*10**18;
    }

    // Update the given pool's DGNZ allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }

    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
         return _to.sub(_from);
    }

    // View function to see pending DGNZs on frontend.
    function pendingDGNZ(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDGNZPerShare = pool.accDGNZPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 dgnzReward = multiplier.mul(dgnzPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accDGNZPerShare = accDGNZPerShare.add(dgnzReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accDGNZPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 dgnzReward = multiplier.mul(dgnzPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        dgnz.mint(devaddr, dgnzReward.mul(devfees).div(100));
        dgnz.mint(coinflip, dgnzReward.mul(coinflipfees).div(100));
        dgnz.mint(roulette, dgnzReward.mul(roulettefees).div(100));
        dgnz.mint(degen, dgnzReward.mul(degenfees).div(100));
        dgnz.mint(address(xdgnz), dgnzReward);
        pool.accDGNZPerShare = pool.accDGNZPerShare.add(dgnzReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }


    // Set Games Addresses
    function setAddr(address _roulette, address _coinflip, address _degen) public onlyOwner{
        roulette = _roulette;
        coinflip = _coinflip;
        degen = _degen;
    }


    // Set Games fees
    function setFees(uint8 _devfees, uint8 _roulettefees, uint8 _coinflipfees, uint8 _degenfees) public onlyOwner{
        devfees = _devfees;
        roulettefees = _roulettefees;
        coinflipfees = _coinflipfees;
        degenfees = _degenfees;
    }


    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Deposit LP tokens to MasterChef for DGNZ allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {

        require (_pid != 0, 'deposit DGNZ not allowed');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accDGNZPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeDGNZTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDGNZPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {

        require (_pid != 0, 'withdraw DGNZ not allowed');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accDGNZPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeDGNZTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDGNZPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    //Helper to withdrawAll
    function withdrawAll(uint256 _pid) public nonReentrant {
        withdraw(_pid, uint256(-1));
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }


    // Stake DGNZ tokens to MasterChef
    function enterStaking(uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accDGNZPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeDGNZTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDGNZPerShare).div(1e12);

        xdgnz.mint(msg.sender, _amount);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw DGNZ tokens from STAKING.
    function leaveStaking(uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accDGNZPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeDGNZTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDGNZPerShare).div(1e12);

        xdgnz.burn(msg.sender, _amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    // Safe cake transfer function, just in case if rounding error causes pool to not have enough DGNZs.
    function safeDGNZTransfer(address _to, uint256 _amount) internal {
        xdgnz.safeDGNZTransfer(_to, _amount);
    }

    // Update dev address
    function dev(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
    }
}
