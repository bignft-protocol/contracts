pragma solidity ^0.5.7;

import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import './utils/ServiceFeeManager.sol';

/**
* @title DataTokenTemplate
* @dev Template DataToken contract, used for as the reference for DataToken Proxy contracts deployment
*/
contract DataTokenTemplate is ERC20 {
    using SafeMath for uint256;
    
    bool    private initialized = false;
    bool    private paused      = false;
    string  private _name;
    string  private _symbol;
    uint256 private _cap;
    uint256 private _decimals;
    address private _minter;

    address payable private beneficiary;

    ServiceFeeManager serviceFeeManager;
    
    modifier onlyNotInitialized() {
        require(
          !initialized,
          'DataToken: token instance already initialized'
        );
        _;
    }
    
    modifier onlyMinter() {
        require(
            msg.sender == _minter,
            'DataToken: invalid minter' 
        );
        _;
    }

    modifier onlyNotPaused() {
        require(
            !paused,
            'DataToken: this token contract is paused' 
        );
        _;
    }

    modifier onlyPaused() {
        require(
            paused,
            'DataToken: this token contract is not paused' 
        );
        _;
    }
    
    /**
     * @notice only used prior contract deployment
     */
    constructor(
        string memory name,
        string memory symbol,
        address minter,
        address payable feeManager

    )
        public
    {
         _initialize(
            name,
            symbol,
            minter,
            feeManager
        );
    }
    
    /**
     * @notice only used prior token instance setup (all state variables will be initialized)
        "initialize(string,string,address)","datatoken-1","dt-1",0xBa3e0EC852Dc24cA7F454ea545D40B1462501711
     */
    function initialize(
        string memory name,
        string memory symbol,
        address minter,
        address payable feeManager
    ) 
        public
        onlyNotInitialized 
    {
        _initialize(
            name,
            symbol,
            minter,
            feeManager
        );
    }
    
    function _initialize(
        string memory name,
        string memory symbol,
        address minter,
        address payable feeManager
    ) private {
        require(minter != address(0), 'Invalid minter:  address(0)');
        require(_minter == address(0), 'Invalid minter: access denied');
        
        _decimals = 18;
        uint256 baseCap = 1400000000;
        _cap = baseCap.mul(uint256(10) ** _decimals);
       
         _name = name;
        _symbol = symbol;
        _minter = minter;

        serviceFeeManager = ServiceFeeManager(feeManager);
        beneficiary = feeManager;
        initialized = true;
    }
    
    function mint(address account, uint256 value) public payable onlyNotPaused onlyMinter {
        uint256 startGas = gasleft();
        require(totalSupply().add(value) <= _cap, "ERC20Capped: cap exceeded");
        
        _mint(account, value);
        require(msg.value >= serviceFeeManager.getFee(startGas, value),
            "DataToken: fee amount is not enough");
        
        beneficiary.transfer(msg.value);
    }

    function transfer(address to, uint256 value) public onlyNotPaused returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public onlyNotPaused returns (bool) {
        return super.transferFrom(from, to, value);
    }

    function approve(address spender, uint256 value) public onlyNotPaused returns (bool) {
        return super.approve(spender, value);
    }

    function increaseAllowance(address spender, uint256 addedValue) public onlyNotPaused returns (bool) {
        return super.increaseAllowance(spender, addedValue);
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public onlyNotPaused returns (bool) {
        return super.decreaseAllowance(spender, subtractedValue);
    }
    
    function pause() public onlyNotPaused onlyMinter {
        paused = true;
    }

    function unpause() public onlyPaused onlyMinter {
        paused = false;
    }

    function setMinter(address minter) public onlyNotPaused onlyMinter {
        _minter = minter;
    }
    
    function name() public view returns(string memory) {
        return _name;
    }
    
    function symbol() public view returns(string memory) {
        return _symbol;
    }
    
    function decimals() public view returns(uint256) {
        return _decimals;
    }
    
    function cap() public view returns (uint256) {
        return _cap;
    }
    
    function isMinter(address account) public view returns(bool) {
        return (_minter == account);
    } 
    
    function isInitialized() public view returns(bool) {
        return initialized;
    }

    function isPaused() public view returns(bool) {
        return paused;
    }
}