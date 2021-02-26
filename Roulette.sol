pragma solidity 0.6.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


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


contract Roulette is Ownable, ReentrancyGuard{
    
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public dead = 0x000000000000000000000000000000000000dEaD;

  uint256 public maxticket = 1000*10**18;
  uint256 public burnRate = 30;
  uint256 public housefees = 1;
  
  uint256 constant step1 = 19298681539552699237261830834781317975544997444273427339909597334652188273322;
  uint256 constant step2 = 38597363079105398474523661669562635951089994888546854679819194669304376546644;
  uint256 constant step3 = 57896044618658097711785492504343953926634992332820282019728792003956564819968;
  uint256 constant step4 = 77194726158210796949047323339125271902179989777093709359638389338608753093288;
  uint256 constant step5 = 96493407697763496186309154173906589877724987221367136699547986673260941366610;
  uint256 constant step6 =  115792089237316195423570985008687907853269984665640564039457584007913129639935;
  
  uint256 public gameId;
  address payable public admin;
  mapping(uint256 => Game) public games;
  mapping(address => Outcome) public outcomes;

  modifier onlyAdmin() {
    require(msg.sender == admin, 'caller is not the admin');
    _;
  }

  IERC20 public dgnz;

  struct Outcome{
    uint256 id;
    uint256 bet;
    uint256 seed;
    uint256 random;
    uint256 winAmount;
    uint256 block;
    uint256 amount;
  }

  struct Game{
    uint256 id;
    uint256 bet;
    uint256 seed;
    uint256 amount;
    address player;
  }

  event Withdraw(address admin, uint256 amount);
  event Result(uint256 id, uint256 bet, uint256 randomSeed, uint256 amount, address player, uint256 winAmount, uint256 randomResult, uint256 time);
  
  /**
   * Constructor 
   */
  constructor(IERC20 _dgnz) public {
    dgnz = _dgnz;
    admin = msg.sender;
  }


  /**
  * Set the newAdmin
  */

  function setAdmin(address payable _newadmin) external onlyAdmin {
        admin = _newadmin;
  }

  /**
  * Set the fees amount
  */

  function setFees(uint256 _amount) external onlyOwner {
        housefees = _amount;
  }
  
  /**
  * Set the max bet amount
  */

  function setTicket(uint256 _amount) external onlyOwner {
        maxticket = _amount;
  }

  /**
  * Set the BurnRate
  */
  function setBurnRate(uint256 _amount) external onlyOwner {
        burnRate = _amount;
  }
  /**
   * Taking bets function.
   * By winning, user 6x his betAmount.
   * Chances to win and lose are the same.
   */
  function game(uint256 _amount, uint256 bet, uint256 seed) public nonReentrant returns (bool) {

    require(_amount > 0,"Incorrect Amount");
    require(dgnz.balanceOf(address(msg.sender)) >= _amount, "Balance Insuffisiant");
    require(dgnz.balanceOf(address(this)) >= _amount.mul(6),  "Error, insufficent vault balance");
    dgnz.safeTransferFrom(address(msg.sender), address(this), _amount);
      
    require(bet<=6 && bet>=1, 'Error, accept only 1 too 6');

    //each bet has unique id
    games[gameId] = Game(gameId, bet, seed, _amount, msg.sender);
    
    //seed is auto-generated by DApp
    getRandomNumber(seed);

    return true;
  }
  
   /** 
   * Request for randomness.
   */
  function getRandomNumber(uint256 userProvidedSeed) internal {

    bytes32 _structHash;
    uint256 _randomNumber;
    bytes32 _blockhash = blockhash(block.number-1);
    uint256 gasleft = gasleft();

    // 1
    _structHash = keccak256(
        abi.encode(
            _blockhash,
            gameId,
            gasleft,
            userProvidedSeed
        )
    );
    _randomNumber  = uint256(_structHash);
    assembly {_randomNumber := mod(_randomNumber, step6)}
    verdict(uint256(_randomNumber));
  }

  
  /**
   * Send rewards to the winners.
   */
  function verdict(uint256 random) internal {
      uint256 winAmount = 0;
      uint256 fees = games[gameId].amount * housefees / 100;
      dgnz.safeTransfer(address(admin),fees);

      //if user wins, then receives 6x of their betting amount
      if(
                           (random<step1 && games[gameId].bet==1) || 
        ( step1<=random &&  random<step2 && games[gameId].bet==2) ||
        ( step2<=random &&  random<step3 && games[gameId].bet==3) ||
        ( step3<=random &&  random<step4 && games[gameId].bet==4) ||
        ( step4<=random &&  random<step5 && games[gameId].bet==5) ||
                         ( step5<=random && games[gameId].bet==6)
        )
        {
        winAmount =  games[gameId].amount * 599 / 100;
        dgnz.safeTransfer(address(games[gameId].player),winAmount);
      }
      else{
        uint256 burnAmount = games[gameId].amount * burnRate / 100;
        dgnz.safeTransfer(address(dead),burnAmount);
      }


      emit Result(games[gameId].id, games[gameId].bet, games[gameId].seed, games[gameId].amount, games[gameId].player, winAmount, random, block.timestamp);
      outcomes[games[gameId].player] = Outcome(games[gameId].id, games[gameId].bet, games[gameId].seed,random,winAmount,block.timestamp,  games[gameId].amount);

      gameId += 1;
  }
  
  function withdrawDGNZ(uint256 amount) external onlyAdmin {
    require(dgnz.balanceOf(address(this)) >= amount, 'Error, contract has insufficent balance');
    dgnz.transfer(address(admin), amount);
   
    emit Withdraw(admin, amount);
  }
}