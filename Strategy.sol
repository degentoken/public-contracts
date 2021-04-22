// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/Pancake.sol";

    
contract Strategy is Ownable, ReentrancyGuard, Pausable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool public StakingPool; 
    bool public StakingPoolAUTO; 
    bool public Compounding; 
    bool public HousePool;

    address public farmContractAddress; 
    uint256 public pid; 
    address public wantAddress;
    address public token0Address;
    address public token1Address;
    address public earnedAddress;
    address public uniRouterAddress; 

    address public wbnbAddress;
    address public aDGNZFarmAddress;
    address public ADGNZAddress;
    address public govAddress;
    bool public onlyGov = true;

    uint256 public lastEarnBlock = 0;
    uint256 public wantLockedTotal = 0;
    uint256 public sharesTotal = 0;

    uint256 public controllerFee = 200; //2%
    uint256 public constant controllerFeeMax = 10000; // 100 = 1%
    uint256 public constant controllerFeeUL = 10000;

    uint256 public buyBackRate = 250; // 2.5%
    uint256 public constant buyBackRateMax = 10000; // 100 = 1%
    uint256 public constant buyBackRateUL = 10000;
    address public buyBackAddress = 0x000000000000000000000000000000000000dEaD;

    uint256 public entranceFeeFactor = 9990; // < 0.1% entrance fee - goes to pool + prevents front-running
    uint256 public constant entranceFeeFactorMax = 10000;
    uint256 public constant entranceFeeFactorLL = 9950; // 0.5% is the max entrance fee settable. LL = lowerlimit

    uint256 public withdrawFeeFactor = 10000; // 0% withdraw fee - goes to pool
    uint256 public constant withdrawFeeFactorMax = 10000;
    uint256 public constant withdrawFeeFactorLL = 8000; //100

    address public roulette;
    address public coinflip;
    uint256 public coinFlipRate = 500;
    uint256 public rouletteRate = 400;

    address[] public earnedToWant;
    address[] public earnedToADGNZPath;
    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    address[] public token0ToEarnedPath;
    address[] public token1ToEarnedPath;

    constructor(
        address _aDGNZFarmAddress,
        address _ADGNZAddress,
        bool _StakingPool,
        bool _StakingPoolAUTO,
        bool _Compounding,
        bool _HousePool,
        address _farmContractAddress,
        uint256 _pid,
        address _wantAddress,
        address _token0Address,
        address _token1Address,
        address _earnedAddress,
        address _uniRouterAddress,
        address _wbnbAddress,
        address _coinflip,
        address _roulette
    ) public {
        coinflip = _coinflip;
        roulette = _roulette;
        HousePool = _HousePool;
        wbnbAddress = _wbnbAddress;
        govAddress = msg.sender;
        aDGNZFarmAddress = _aDGNZFarmAddress;
        ADGNZAddress = _ADGNZAddress;

        StakingPool = _StakingPool;
        StakingPoolAUTO = _StakingPoolAUTO;
        Compounding = _Compounding;
        wantAddress = _wantAddress;
        earnedAddress = _earnedAddress;

        if (Compounding) {
            if (!StakingPool) {
                token0Address = _token0Address;
                token1Address = _token1Address;
            }

        if (StakingPoolAUTO){
                token0Address = _token0Address;
                token1Address = _token1Address;
                earnedToWant = [earnedAddress, wbnbAddress, wantAddress];
                if (wbnbAddress == wantAddress) {
                    earnedToWant = [earnedAddress, wbnbAddress];
                }
            }

            farmContractAddress = _farmContractAddress;
            pid = _pid;

            uniRouterAddress = _uniRouterAddress;

            earnedToADGNZPath = [earnedAddress, wbnbAddress, ADGNZAddress];
            if (wbnbAddress == earnedAddress) {
                earnedToADGNZPath = [wbnbAddress, ADGNZAddress];
            }

            earnedToToken0Path = [earnedAddress, wbnbAddress, token0Address];
            if (wbnbAddress == token0Address) {
                earnedToToken0Path = [earnedAddress, wbnbAddress];
            }

            earnedToToken1Path = [earnedAddress, wbnbAddress, token1Address];
            if (wbnbAddress == token1Address) {
                earnedToToken1Path = [earnedAddress, wbnbAddress];
            }

            token0ToEarnedPath = [token0Address, wbnbAddress, earnedAddress];
            if (wbnbAddress == token0Address) {
                token0ToEarnedPath = [wbnbAddress, earnedAddress];
            }

            token1ToEarnedPath = [token1Address, wbnbAddress, earnedAddress];
            if (wbnbAddress == token1Address) {
                token1ToEarnedPath = [wbnbAddress, earnedAddress];
            }
        }

        transferOwnership(aDGNZFarmAddress);
    }

    // Receives new deposits from user
    function deposit(address _userAddress,uint256 _wantAmt)
        public
        onlyOwner
        whenNotPaused
        returns (uint256)
    {
        IERC20(wantAddress).safeTransferFrom(
            address(msg.sender),
            address(this),
            _wantAmt
        );

        uint256 sharesAdded = _wantAmt;
        if (wantLockedTotal > 0) {
            sharesAdded = _wantAmt
                .mul(sharesTotal)
                .mul(entranceFeeFactor)
                .div(wantLockedTotal)
                .div(entranceFeeFactorMax);
        }
        sharesTotal = sharesTotal.add(sharesAdded);

        if (Compounding) {
            _farm();
        } else {
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }

        return sharesAdded;
    }

    function farm() public nonReentrant {
        _farm();
    }

    function _farm() internal {
        require(Compounding, "!Compounding");
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        wantLockedTotal = wantLockedTotal.add(wantAmt);
        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);

        if (StakingPool) {
            IPancakeswapFarm(farmContractAddress).enterStaking(wantAmt); 
        } else {
            IPancakeswapFarm(farmContractAddress).deposit(pid, wantAmt);
        }
    }

    function withdraw(address _userAddress, uint256 _wantAmt)
        public
        onlyOwner
        nonReentrant
        returns (uint256)
    {
        require(_wantAmt > 0, "_wantAmt <= 0");

        uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        sharesTotal = sharesTotal.sub(sharesRemoved);

        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = _wantAmt.mul(withdrawFeeFactor).div(
                withdrawFeeFactorMax
            );
        }
 
        if (Compounding) {
            if (StakingPool) {
                IPancakeswapFarm(farmContractAddress).leaveStaking(_wantAmt); 
            } else {
                IPancakeswapFarm(farmContractAddress).withdraw(pid, _wantAmt);
            }
        }

        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }

        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }

       wantLockedTotal = wantLockedTotal.sub(_wantAmt);

       IERC20(wantAddress).safeTransfer(aDGNZFarmAddress, _wantAmt);

       return sharesRemoved;
    }

    // 1. Harvest farm tokens
    // 2. Converts farm tokens into want tokens
    // 3. Deposits want tokens

    function earn() public whenNotPaused {
        require(Compounding, "!Compounding");
        if (onlyGov) {
            require(msg.sender == govAddress, "Not authorised");
        }

        // Harvest farm tokens
        if (StakingPool) {
            IPancakeswapFarm(farmContractAddress).leaveStaking(0); 
        } else {
            IPancakeswapFarm(farmContractAddress).withdraw(pid, 0);
        }

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        earnedAmt = distributeFees(earnedAmt);

        if (!HousePool){
            earnedAmt = buyBack(earnedAmt);
        }

        if (HousePool){
            earnedAmt = gamePush(earnedAmt);
        }

        if (StakingPool) {
            lastEarnBlock = block.number;
            _farm();
            return;
        }

        if (StakingPoolAUTO) {

            IERC20(earnedAddress).safeApprove(uniRouterAddress, 0);
            IERC20(earnedAddress).safeIncreaseAllowance(
                uniRouterAddress,
                earnedAmt
            );
            if (earnedAddress != wantAddress) {
                // Swap earned to wantAddress
                IPancakeRouter02(uniRouterAddress)
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    earnedAmt,
                    0,
                    earnedToWant,
                    address(this),
                    now + 600
                );
            }
            lastEarnBlock = block.number;
            _farm();
            return;
        }

        IERC20(earnedAddress).safeApprove(uniRouterAddress, 0);
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            earnedAmt
        );

        if (earnedAddress != token0Address) {
            // Swap half earned to token0
            IPancakeRouter02(uniRouterAddress)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                earnedAmt.div(2),
                0,
                earnedToToken0Path,
                address(this),
                now + 600
            );
        }

        if (earnedAddress != token1Address) {
            // Swap half earned to token1
            IPancakeRouter02(uniRouterAddress)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                earnedAmt.div(2),
                0,
                earnedToToken1Path,
                address(this),
                now + 600
            );
        }

        // Get want tokens, ie. add liquidity
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token0Amt > 0 && token1Amt > 0) {
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );
            IPancakeRouter02(uniRouterAddress).addLiquidity(
                token0Address,
                token1Address,
                token0Amt,
                token1Amt,
                0,
                0,
                address(this),
                now + 600
            );
        }

        lastEarnBlock = block.number;

        _farm();
    }

    function gamePush(uint256 _earnedAmt) internal returns (uint256) {

        uint256 cAmount = _earnedAmt.mul(coinFlipRate).div(10000);
        uint256 rAmount = _earnedAmt.mul(rouletteRate).div(10000);

        IERC20(earnedAddress).safeIncreaseAllowance(coinflip, cAmount);
        IERC20(earnedAddress).transfer(coinflip, cAmount);

        IERC20(earnedAddress).safeIncreaseAllowance(roulette, rAmount);
        IERC20(earnedAddress).transfer(roulette, rAmount);

        _earnedAmt.sub(cAmount);
        _earnedAmt.sub(rAmount);
        return _earnedAmt;
    }

    function buyBack(uint256 _earnedAmt) internal returns (uint256) {
        if (buyBackRate <= 0) {
            return _earnedAmt;
        }

        uint256 buyBackAmt = _earnedAmt.mul(buyBackRate).div(buyBackRateMax);

        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            buyBackAmt
        );

        IPancakeRouter02(uniRouterAddress)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
            buyBackAmt,
            0,
            earnedToADGNZPath,
            buyBackAddress,
            now + 600
        );

        return _earnedAmt.sub(buyBackAmt);
    }

    function distributeFees(uint256 _earnedAmt) internal returns (uint256) {
        if (_earnedAmt > 0) {
            // Performance fee
            if (controllerFee > 0) {
                uint256 fee =
                    _earnedAmt.mul(controllerFee).div(controllerFeeMax);
                IERC20(earnedAddress).safeTransfer(govAddress, fee);
                _earnedAmt = _earnedAmt.sub(fee);
            }
        }

        return _earnedAmt;
    }

    function convertDustToEarned() public whenNotPaused {
        require(Compounding, "!Compounding");
        require(!StakingPool, "StakingPool");
        require(!StakingPoolAUTO, "StakingPoolAUTO");

        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().

        // Converts token0 dust (if any) to earned tokens
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Address != earnedAddress && token0Amt > 0) {
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );

            // Swap all dust tokens to earned tokens
            IPancakeRouter02(uniRouterAddress)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                token0Amt,
                0,
                token0ToEarnedPath,
                address(this),
                now + 600
            );
        }

        // Converts token1 dust (if any) to earned tokens
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Address != earnedAddress && token1Amt > 0) {
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );

            // Swap all dust tokens to earned tokens
            IPancakeRouter02(uniRouterAddress)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                token1Amt,
                0,
                token1ToEarnedPath,
                address(this),
                now + 600
            );
        }
    }

    function pause() public {
        require(msg.sender == govAddress, "Not authorised");
        _pause();
    }

    function unpause() external {
        require(msg.sender == govAddress, "Not authorised");
        _unpause();
    }

    function setEntranceFeeFactor(uint256 _entranceFeeFactor) public {
        require(msg.sender == govAddress, "Not authorised");
        require(_entranceFeeFactor > entranceFeeFactorLL, "!safe - too low");
        require(_entranceFeeFactor <= entranceFeeFactorMax, "!safe - too high");
        entranceFeeFactor = _entranceFeeFactor;
    }

    function setWithdrawFeeFactor(uint256 _withdrawFeeFactor) public {
        require(msg.sender == govAddress, "Not authorised");
        require(_withdrawFeeFactor> withdrawFeeFactorLL, "!safe - too low");
        require(_withdrawFeeFactor<= withdrawFeeFactorMax, "!safe - too high");
        withdrawFeeFactor= _withdrawFeeFactor;
    }

    function setBuyBackAddress(address _buyBackAddress) public {
        require(msg.sender == govAddress, "Not authorised");
        buyBackAddress = _buyBackAddress;
    }

    function setUniRouterAddress(address _uniRouterAddress) public {
        require(msg.sender == govAddress, "Not authorised");
        uniRouterAddress = _uniRouterAddress;
    }

    function setControllerFee(uint256 _controllerFee) public {
        require(msg.sender == govAddress, "Not authorised");
        require(_controllerFee <= controllerFeeUL, "too high");
        controllerFee = _controllerFee;
    }

    function setbuyBackRate(uint256 _buyBackRate) public {
        require(msg.sender == govAddress, "Not authorised");
        require(buyBackRate <= buyBackRateUL, "too high");
        buyBackRate = _buyBackRate;
    }

    function setGov(address _govAddress) public {
        require(msg.sender == govAddress, "!gov");
        govAddress = _govAddress;
    }

    function setOnlyGov(bool _onlyGov) public {
        require(msg.sender == govAddress, "!gov");
        onlyGov = _onlyGov;
    }

    // Set Games Addresses
    function setAddr(address _roulette, address _coinflip) public {
        require(msg.sender == govAddress, "!gov");
        roulette = _roulette;
        coinflip = _coinflip;
    }

    function setGamesRates(uint256 _coinFlipRate, uint256 _rouletteRate) public {
        require(msg.sender == govAddress, "Not authorised");
        coinFlipRate = _coinFlipRate;
        rouletteRate = _rouletteRate;
    }


    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) public {
        require(msg.sender == govAddress, "!gov");
        require(_token != earnedAddress, "!safe");
        require(_token != wantAddress, "!safe");
        IERC20(_token).safeTransfer(_to, _amount);
    }
}
