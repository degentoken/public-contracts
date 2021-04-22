pragma solidity >=0.6.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/Pancake.sol";

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



contract Betting is Ownable, ReentrancyGuard{

    using SafeMath for uint;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Pool {
        address user;
        uint minBet;
        uint total;
        uint id;
        uint timestamp;
        bool active;
        uint delay;
    }

    mapping (uint => Pool) public pools;

    uint public minBet = 10**16;
    uint public id = 0;
    uint public delay = 900;
    uint public bnbfees = 60;
    uint public adgnzfees = 30;
    uint public step = 100;

    //address ADGNZAddress = 0x02DB7A725DA08393A34c042909CDDb52fde15e5F; //testnet
    //address wbnbAddress = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd; //testnet
    //address uniRouterAddress = 0x5334dEfbffDD7eC8705878DB226cc4a0b498cd12; //testnet

    address ADGNZAddress = 0xe8B9b396c59A6BC136cF1f05C4D1A68A0F7C2Dd7; //main
    address wbnbAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; //main
    address uniRouterAddress = 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F; //main

    address devAddr = 0xAD846dF46442e7B3BafE456b1819954898330030; 

    IERC20 public adgnz = IERC20(ADGNZAddress);
    address[] public earnedToADGNZPath = [wbnbAddress, ADGNZAddress];

    event Bet(uint id, address sender, uint amount);
    event Reward(address claimer, uint amount);
    event Withdraw(uint amount);
    event NewDelay(uint amount);

    function setFees(uint _bnbfees, uint _adgnzfees, uint _step) public onlyOwner {
        bnbfees = _bnbfees;
        adgnzfees = _adgnzfees;
        step = _step;
    }

    function getAdgnzPrice(uint amount) public view returns (int price) {
        uint[] memory prices = IPancakeRouter02(uniRouterAddress).getAmountsOut(amount, earnedToADGNZPath);
        price = int256(prices[prices.length - 1]);
        return price;
    }

    function swap() public payable nonReentrant{
        IPancakeRouter02(uniRouterAddress).swapExactETHForTokens{value: msg.value}(
                0,
                earnedToADGNZPath,
                address(this),
                now.add(600)
       );
    }

    function setDelay(uint delay_) public onlyOwner{
        delay = delay_;
        emit NewDelay(delay);
    }

    function start() public {
        require(pools[id].timestamp + delay < block.timestamp, "Start:Time not expired");
        require(pools[id].total == 0,"Pool empty safe to force restart");
        id = id.add(1);
        pools[id].timestamp = block.timestamp;
        pools[id].active = true;
        pools[id].delay = delay;
    }

    function bet() public payable nonReentrant{
        require(msg.value >=  minBet, "below min bet");
        require(uint256(getAdgnzPrice(msg.value)) >= pools[id].minBet, "Amount should be at least the minimal bet");
        require(pools[id].timestamp + delay > block.timestamp, "Time expired");
        require(pools[id].active == true, "not active");

        uint[] memory amounts = IPancakeRouter02(uniRouterAddress).swapExactETHForTokens{value: msg.value}(
                0,
                earnedToADGNZPath,
                address(this),
                now.add(600)
        );

        uint256 amount = uint256(amounts[amounts.length - 1]);
        uint fee = amount.mul(bnbfees).div(1000);
        adgnz.safeTransfer(address(devAddr), fee);

        pools[id].total = pools[id].total.add(amount).sub(fee);
        pools[id].minBet = amount.add(amount.mul(step).div(1000));
        pools[id].timestamp = block.timestamp;
        pools[id].user = msg.sender;

        emit Bet(id, msg.sender, amount);
    }

    function betDGN(uint amount) public nonReentrant{
        require(pools[id].timestamp + delay > block.timestamp, "Time expired");
        require(pools[id].active == true, "not active");
        require(amount > 0 && amount >= pools[id].minBet, "Amount should be at least the minimal bet");
        require(adgnz.balanceOf(address(msg.sender)) >= amount, "Balance Insuffisiant");

        adgnz.safeTransferFrom(address(msg.sender), address(this), amount);

        uint fee = amount.mul(adgnzfees).div(1000);
        adgnz.safeTransfer(address(devAddr), fee);

        pools[id].total = pools[id].total.add(amount).sub(fee);
        pools[id].minBet = amount.add(amount.mul(step).div(1000));
        pools[id].timestamp = block.timestamp;
        pools[id].user = msg.sender;
        emit Bet(id, msg.sender, amount);
    }

    function sendReward() public {
        require(pools[id].timestamp + delay < block.timestamp, "Time not expired");
        require(pools[id].active == true, "not active");
        pools[id].active = false;
        pools[id].total = 0;
        uint256 amount = adgnz.balanceOf(address(this));
        adgnz.safeTransfer(address(pools[id].user), amount);
        start();
        emit Reward(pools[id].user, amount);
    }


  function withdrawaDGNZ() external onlyOwner {
    require(adgnz.balanceOf(address(this)) > 0, 'Error, contract has insufficent balance');
    uint256 amount = adgnz.balanceOf(address(this));
    adgnz.safeTransfer(address(devAddr), amount);
    emit Withdraw(amount);
  }
}

