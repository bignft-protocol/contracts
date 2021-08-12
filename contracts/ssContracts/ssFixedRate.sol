pragma solidity >=0.6.0;
// Copyright BigchainDB GmbH and Ocean Protocol contributors
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import "../interfaces/IERC20Template.sol";
import "../ssContracts/BPoolInterface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";
/**
 * @title ssFixedRate
 *
 * @dev ssFixedRate is a contract that during the burn-in period handles DT trades and after that monitors stakings in pools
 *      Called by the pool contract
 *      Every ss newDataTokenCreated function has a ssParams array, which for this contract has the following structure:
 *               - [0] - fixed rate between DT and basetoken
 *               - [1] - if >0 , then allowSell=TRUE  (getting back DT for Ocean)
 *               - [2] - vestingAmount  - total # of datatokens to be vested
 *               - [3] - vestingBlocks - how long is the vesting period (in blocks)
 *
 */
contract ssFixedRate {
    using SafeMath for uint256;
    struct Record {
        bool bound; //datatoken bounded
        address basetokenAddress;
        address poolAddress;
        bool poolFinalized; // did we finalized the pool ? We have to do it after burn-in
        uint256 datatokenBalance; //current dt balance
        uint256 datatokenCap; //dt cap
        uint256 basetokenBalance; //current basetoken balance
        uint256 lastPrice; //used for creating the pool
        // rate options
        uint256 burnInEndBlock; //block to end burn-in
        uint256 rate; // rate to exchange DT<->BaseToken
        bool allowDtSale; //if should allow DT to be swaped for basetoken.  Buying is always accepted
        // vesting options
        address publisherAddress;
        uint256 blockDeployed; //when this record was created
        uint256 vestingEndBlock; //see below
        uint256 vestingAmount; // total amount to be vested to publisher until vestingEndBlock
        uint256 vestingLastBlock; //last block in which a vesting has been granted
        uint256 vestingAmountSoFar; //how much was vested so far
    }

    mapping(address => Record) private _datatokens;
    uint256 private constant BASE = 10**18;

    /**
     * @dev constructor
     *      Called on contract deployment.
     */
    constructor() public {}

    /**
     * @dev newDataTokenCreated
     *      Called when new DataToken is deployed by the DataTokenFactory
     * @param datatokenAddress - datatokenAddress
     * @param basetokenAddress -
     * @param poolAddress - poolAddress
     * @param publisherAddress - publisherAddress
     * @param burnInEndBlock - block that will end the burn-in period
     * @param ssParams  - ss Params, see below
     */

    function newDataTokenCreated(
        address datatokenAddress,
        address basetokenAddress,
        address poolAddress,
        address publisherAddress,
        uint256 burnInEndBlock,
        uint256[] memory ssParams
    ) public returns (bool) {
        //check if we are the controller of the pool
        require(poolAddress != address(0), "Invalid poolAddress");
        BPoolInterface bpool = BPoolInterface(poolAddress);
        require(
            bpool.getController() == address(this),
            "We are not the pool controller"
        );
        //check if the tokens are bound
        require(
            bpool.getDataTokenAddress() == datatokenAddress,
            "DataToken address missmatch"
        );
        require(
            bpool.getBaseTokenAddress() == basetokenAddress,
            "BaseToken address missmatch"
        );
        // check if we are the minter of DT
        IERC20Template dt = IERC20Template(datatokenAddress);
        require( (dt.permissions(address(this))).minter == true , "BaseToken address mismatch");
        // get cap and mint it..
        dt.mint(address(this), dt.cap());
        require(dt.balanceOf(address(this)) == dt.totalSupply(), "Mint failed");
        console.log('here');
        console.log(dt.balanceOf(address(this)));
        // check the ssParams
       // uint256 rate = ssParams[0];
       IERC20Template bt = IERC20Template(basetokenAddress);
       console.log('OCEAN', bt.balanceOf(address(this)));
        bool allowSell;
        if (ssParams[1] == 0) allowSell = false;
        else allowSell = true;
       // uint256 vestingAmount = ssParams[2];
        //uint256 vestingEndBlock = block.number+ssParams[3];
        
      
        //we are rich :)let's setup the records and we are good to go
        _datatokens[datatokenAddress] = Record({
            bound: true,
            basetokenAddress: basetokenAddress,
            poolAddress: poolAddress,
            poolFinalized: false,
            datatokenBalance: dt.totalSupply(),
            datatokenCap:dt.cap(),
            basetokenBalance: ssParams[4],
            lastPrice: 0,
            burnInEndBlock: burnInEndBlock,
            rate: ssParams[0],
            allowDtSale: allowSell,
            publisherAddress: publisherAddress,
            blockDeployed: block.number,
            vestingEndBlock: block.number+ssParams[3],
            vestingAmount: ssParams[2],
            vestingLastBlock: block.number,
            vestingAmountSoFar: 0
        });

        notifyFinalize(datatokenAddress);

        return (true);
    }

    //public getters
    function getDataTokenCirculatingSupply(address datatokenAddress)
        public
        view
        returns (uint)
    {
        if (_datatokens[datatokenAddress].bound != true) return (0);
        return( _datatokens[datatokenAddress].datatokenCap - _datatokens[datatokenAddress].datatokenBalance);
    }
    function getPublisherAddress(address datatokenAddress)
        public
        view
        returns (address)
    {
        if (_datatokens[datatokenAddress].bound != true) return (address(0));
        return (_datatokens[datatokenAddress].publisherAddress);
    }

    function getBaseTokenAddress(address datatokenAddress)
        public
        view
        returns (address)
    {
        if (_datatokens[datatokenAddress].bound != true) return (address(0));
        return (_datatokens[datatokenAddress].basetokenAddress);
    }

    function getPoolAddress(address datatokenAddress)
        public
        view
        returns (address)
    {
        if (_datatokens[datatokenAddress].bound != true) return (address(0));
        return (_datatokens[datatokenAddress].poolAddress);
    }

    function getBaseTokenBalance(address datatokenAddress)
        public
        view
        returns (uint256)
    {
        if (_datatokens[datatokenAddress].bound != true) return (0);
        return (_datatokens[datatokenAddress].basetokenBalance);
    }

    function getDataTokenBalance(address datatokenAddress)
        public
        view
        returns (uint256)
    {
        if (_datatokens[datatokenAddress].bound != true) return (0);
        return (_datatokens[datatokenAddress].datatokenBalance);
    }

    function getburnInEndBlock(address datatokenAddress)
        public
        view
        returns (uint256)
    {
        if (_datatokens[datatokenAddress].bound != true) return (0);
        return (_datatokens[datatokenAddress].burnInEndBlock);
    }

    function getvestingEndBlock(address datatokenAddress)
        public
        view
        returns (uint256)
    {
        if (_datatokens[datatokenAddress].bound != true) return (0);
        return (_datatokens[datatokenAddress].vestingEndBlock);
    }

    function getvestingAmount(address datatokenAddress)
        public
        view
        returns (uint256)
    {
        if (_datatokens[datatokenAddress].bound != true) return (0);
        return (_datatokens[datatokenAddress].vestingAmount);
    }

    function getvestingLastBlock(address datatokenAddress)
        public
        view
        returns (uint256)
    {
        if (_datatokens[datatokenAddress].bound != true) return (0);
        return (_datatokens[datatokenAddress].vestingLastBlock);
    }

    function getvestingAmountSoFar(address datatokenAddress)
        public
        view
        returns (uint256)
    {
        if (_datatokens[datatokenAddress].bound != true) return (0);
        return (_datatokens[datatokenAddress].vestingAmountSoFar);
    }

    function isInBurnIn(address datatokenAddress) public view returns (bool) {
        if (_datatokens[datatokenAddress].bound != true) return (false);
        if (block.number > _datatokens[datatokenAddress].burnInEndBlock)
            return (false);
        else return (true);
    }

    //how many tokenIn tokens are required to get tokenAmountOut tokenOut tokens
    function calcInGivenOut(
        address datatokenAddress,
        address tokenIn,
        address tokenOut,
        uint256 tokenAmountOut
    ) public view returns (uint256) {
        if (_datatokens[datatokenAddress].bound != true) return (0);
        //calls private function
        return (_calcInGivenOut(tokenIn, tokenOut, tokenAmountOut));
    }

    //how many tokenOut tokens will get in exchange of tokenAmountIn tokensIn
    function calcOutGivenIn(
        address datatokenAddress,
        address tokenIn,
        address tokenOut,
        uint256 tokenAmountIn
    ) public view returns (uint256) {
        if (_datatokens[datatokenAddress].bound != true) return (0);
        //calls private function
        return (_calcOutGivenIn(tokenIn, tokenOut, tokenAmountIn));
    }

    //called by pool to confirm that we can stake a token (add pool liquidty). If true, pool will call Stake function
    function canStake(address datatokenAddress,address stakeToken,uint256 amount) public view returns (bool){
        //TO DO
        if (_datatokens[datatokenAddress].bound != true) return (false);
        require(msg.sender == _datatokens[datatokenAddress].poolAddress,'ERR: Only pool can call this');
        
        if (_datatokens[datatokenAddress].bound != true) return (false);
        if (_datatokens[datatokenAddress].basetokenAddress == stakeToken) return (false);
        //check balances
        IERC20Template dt = IERC20Template(datatokenAddress);
        uint256 balance = dt.balanceOf(address(this));
        if (_datatokens[datatokenAddress].datatokenBalance >=amount && balance>= amount) return (true);
        return(false);
    }
    //called by pool so 1ss will stake a token (add pool liquidty). Function only needs to approve the amount to be spent by the pool, pool will do the rest
    function Stake(address datatokenAddress,address stakeToken,uint256 amount) public {
        if (_datatokens[datatokenAddress].bound != true) return;
        require(msg.sender == _datatokens[datatokenAddress].poolAddress,'ERR: Only pool can call this');
        bool ok=canStake(datatokenAddress,stakeToken,amount);
        if (ok != true) return;
        IERC20Template dt = IERC20Template(datatokenAddress);
        dt.approve(_datatokens[datatokenAddress].poolAddress,amount);
        _datatokens[datatokenAddress].datatokenBalance-=amount;
    }
    //called by pool to confirm that we can stake a token (add pool liquidty). If true, pool will call Unstake function
    function canUnStake(address datatokenAddress,address stakeToken,uint256 amount) public view returns (bool){
        //TO DO
        if (_datatokens[datatokenAddress].bound != true) return (false);
        require(msg.sender == _datatokens[datatokenAddress].poolAddress,'ERR: Only pool can call this');
        //check balances, etc and issue true or false
        if (_datatokens[datatokenAddress].basetokenAddress == stakeToken) return (false);
        return true;
    }
    //called by pool so 1ss will unstake a token (remove pool liquidty). In our case the balancer pool will handle all, this is just a notifier so 1ss can handle internal kitchen
    function UnStake(address datatokenAddress,address stakeToken,uint256 amount) public {
        if (_datatokens[datatokenAddress].bound != true) return;
        require(msg.sender == _datatokens[datatokenAddress].poolAddress,'ERR: Only pool can call this');
        bool ok=canUnStake(datatokenAddress,stakeToken,amount);
        if (ok != true) return;
        _datatokens[datatokenAddress].datatokenBalance+=amount;
    }
    //called by the pool (or by us) when we should finalize the pool
    function notifyFinalize(address datatokenAddress) internal {
        if (_datatokens[datatokenAddress].bound != true) return;
       // require(msg.sender == _datatokens[datatokenAddress].poolAddress,'ERR: Only pool can call this');
        if(_datatokens[datatokenAddress].poolFinalized==true) return;
        _datatokens[datatokenAddress].poolFinalized=true;
        uint baseTokenWeight=5*BASE; //pool weight: 50-50
        uint dataTokenWeight=5*BASE; //pool weight: 50-50
        uint baseTokenAmount=_datatokens[datatokenAddress].basetokenBalance;
        //given the price, compute dataTokenAmount
        uint dataTokenAmount=_datatokens[datatokenAddress].rate * (baseTokenAmount/baseTokenWeight) * dataTokenWeight/ BASE;
        //approve the tokens and amounts
        IERC20Template dt = IERC20Template(datatokenAddress);
        dt.approve(_datatokens[datatokenAddress].poolAddress,dataTokenAmount);
        IERC20Template dtBase = IERC20Template(_datatokens[datatokenAddress].basetokenAddress);
        dtBase.approve(_datatokens[datatokenAddress].poolAddress,baseTokenAmount);
        console.log('dataTokenAmount',dataTokenAmount);
        // call the pool, bind the tokens, set the price, finalize pool
        BPoolInterface pool=BPoolInterface(_datatokens[datatokenAddress].poolAddress);
        pool.setup(datatokenAddress,dataTokenAmount,dataTokenWeight,_datatokens[datatokenAddress].basetokenAddress,baseTokenAmount,baseTokenWeight);
        //substract
        _datatokens[datatokenAddress].basetokenBalance-=baseTokenAmount;
        _datatokens[datatokenAddress].datatokenBalance-=dataTokenAmount;

    }
    function allowStake(address datatokenAddress,address basetoken,uint datatokenAmount,uint basetokenAmount,address userAddress) public view returns (bool){
        if (_datatokens[datatokenAddress].bound != true) return false;
        require(msg.sender == _datatokens[datatokenAddress].poolAddress,'ERR: Only pool can call this');
        if (isInBurnIn(datatokenAddress) == true) return (false); //we are in burn-period, so no stake/unstake
        //allow user to stake
        return(true);
    }
    function allowUnStake(address datatokenAddress,address basetoken,uint datatokenAmount,uint basetokenAmount,address userAddress) public view returns (bool){
        if (_datatokens[datatokenAddress].bound != true) return false;
        require(msg.sender == _datatokens[datatokenAddress].poolAddress,'ERR: Only pool can call this');
        if (isInBurnIn(datatokenAddress) == true) return (false); //we are in burn-period, so no stake/unstake
        //allow user to stake
        return(true);
    }

    function swapExactAmountIn(address datatokenAddress,address userAddress,address tokenIn,uint tokenAmountIn,address tokenOut,uint minAmountOut) public returns (uint tokenAmountOut){
        require(_datatokens[datatokenAddress].bound == true,'ERR:Invalid datatoken');
        require(msg.sender == _datatokens[datatokenAddress].poolAddress,'ERR: Only pool can call this');
        require(isInBurnIn(datatokenAddress) == true,'ERR: Not in burn-in period');
        tokenAmountOut=calcOutGivenIn(datatokenAddress,tokenIn,tokenOut,tokenAmountIn);
        require(tokenAmountOut>=minAmountOut,'ERR:minAmountOut not meet'); //revert if minAmountOut is not met
        //pull tokenIn from the pool (pool will approve)
        IERC20Template dtIn = IERC20Template(tokenIn);
        console.log('test');
        console.log(_datatokens[datatokenAddress].poolAddress);
        console.log(tokenAmountIn);
        uint balance = dtIn.balanceOf(_datatokens[datatokenAddress].poolAddress);
        console.log('balance', balance);
        dtIn.transferFrom(_datatokens[datatokenAddress].poolAddress,address(this), tokenAmountIn);
        //update our balances
        if(tokenIn==datatokenAddress){
            _datatokens[datatokenAddress].basetokenBalance+=tokenAmountOut;
            _datatokens[datatokenAddress].datatokenBalance+=tokenAmountIn;
        }
        else{
            _datatokens[datatokenAddress].datatokenBalance+=tokenAmountOut;
            _datatokens[datatokenAddress].basetokenBalance+=tokenAmountIn;
        }
        //send tokens to the user  
        IERC20Template dtOut = IERC20Template(tokenOut);
        dtOut.transfer(userAddress, tokenAmountOut);
        return(tokenAmountOut);
    }
    function swapExactAmountOut(address datatokenAddress,address userAddress,address tokenIn,uint maxTokenAmountIn,address tokenOut,uint amountOut) public returns (uint tokenAmountIn){
        require(_datatokens[datatokenAddress].bound == true,'ERR:Invalid datatoken');
        require(msg.sender == _datatokens[datatokenAddress].poolAddress,'ERR: Only pool can call this');
        require(isInBurnIn(datatokenAddress) == true,'ERR: Not in burn-in period');
        tokenAmountIn=calcInGivenOut(datatokenAddress,tokenIn,tokenOut,amountOut);
        console.log('ssFixed',tokenAmountIn);
        require(tokenAmountIn<=maxTokenAmountIn,'ERR:maxTokenAmountIn not meet'); //revert if minAmountOut is not met
        //pull tokenIn from the pool (pool will approve)
        IERC20Template dtIn = IERC20Template(tokenIn);
        dtIn.transferFrom(_datatokens[datatokenAddress].poolAddress,address(this), tokenAmountIn);
        //update our balances
        if(tokenIn==datatokenAddress){
            _datatokens[datatokenAddress].basetokenBalance+=amountOut;
            _datatokens[datatokenAddress].datatokenBalance+=tokenAmountIn;
        }
        else{
            _datatokens[datatokenAddress].datatokenBalance+=amountOut;
            _datatokens[datatokenAddress].basetokenBalance+=tokenAmountIn;
        }
        //send tokens to the user  
        IERC20Template dtOut = IERC20Template(tokenOut);
        dtOut.transfer(userAddress, amountOut);
        return(tokenAmountIn);
    }

    // called by vester to get datatokens
    function getVesting(address datatokenAddress) public{
        require(_datatokens[datatokenAddress].bound == true,'ERR:Invalid datatoken');
        require(msg.sender == _datatokens[datatokenAddress].publisherAddress,'ERR: Only publisher can call this');
        //calculate how many tokens we need to vest to publisher
        uint blocksPassed=block.number-_datatokens[datatokenAddress].vestingLastBlock;
        uint vestPerBlock=_datatokens[datatokenAddress].vestingAmount.div(_datatokens[datatokenAddress].vestingEndBlock-_datatokens[datatokenAddress].blockDeployed);
        if(vestPerBlock==0) return;
        uint amount=blocksPassed.mul(vestPerBlock);
        if(amount>0 && _datatokens[datatokenAddress].datatokenBalance >= amount){
            IERC20Template dt = IERC20Template(datatokenAddress);
            _datatokens[datatokenAddress].vestingAmount+=amount;
            _datatokens[datatokenAddress].vestingLastBlock=block.number;
            dt.transfer(_datatokens[datatokenAddress].publisherAddress, amount);
            _datatokens[datatokenAddress].datatokenBalance-=amount;
        }
    }









    // this is the section that is customizable for every ss


    //private functions that depends on the ss type
    function _calcInGivenOut(
        address tokenIn,
        address tokenOut,
        uint256 tokenAmountOut
    ) private view returns (uint256) {

        /// baseTokenAmount = dataTokenAmount.mul(_datatokens[tokenOut].rate).div(BASE);
        //  dataTokenAmount = baseTokenAmount.mul(BASE).div(_datatokens[tokenOut].rate)

        if (_datatokens[tokenIn].bound == true) {
            //swap datatoken(tokenIn) for basetoken(tokenOut) - spending DT to get Ocean
            if (_datatokens[tokenIn].allowDtSale == false) return (0); //selling DT is not allowed
            //compute how many tokenIn tokens are needed to get tokenOut
            // THIS IS VERY SPECIFIC TO THE ss TYPE (Fixed rate, Bonding, Dutch, etc)
            uint256 tokenAmountIn = tokenAmountOut.mul(BASE).div(_datatokens[tokenIn].rate);
            return (tokenAmountIn);
        }
        if (_datatokens[tokenOut].bound == true) {
            //swap basetoken(tokenIn) for datatokens(tokenOut) - spending Ocean to get DT
            uint256 tokenAmountIn = tokenAmountOut.mul(_datatokens[tokenOut].rate).div(BASE);
            return (tokenAmountIn);
        }
        //no match, bail out
        return (0);
    }

    function _calcOutGivenIn(
        address tokenIn,
        address tokenOut,
        uint256 tokenAmountIn
    ) private view returns (uint256 tokenAmount) {
        
        /// baseTokenAmount = dataTokenAmount.mul(_datatokens[tokenIn].rate).div(BASE);
        //  dataTokenAmount = baseTokenAmount.mul(BASE).div(_datatokens[tokenIn].rate)
        console.log('_calcOutGivenIn');
        if (_datatokens[tokenIn].bound == true) {
            console.log('_calcOutGivenIn2');
            //swap datatoken(tokenIn) for basetoken(tokenOut) - spending DT to get Ocean
            if (_datatokens[tokenIn].allowDtSale == false) return (0); //selling DT is not allowed
            //compute how many tokenIn tokens are needed to get tokenOut
            // THIS IS VERY SPECIFIC TO THE ss TYPE (Fixed rate, Bonding, Dutch, etc)
            
            tokenAmount = tokenAmountIn.mul(_datatokens[tokenIn].rate).div(BASE);
            return (tokenAmount);
        }
        if (_datatokens[tokenOut].bound == true) {
            console.log('_calcOutGivenIn3');
            //sells basetoken(tokenIn) for datatokens(tokenOut) - spending Ocean to get DT
            console.log(tokenAmountIn);
            console.log(BASE);
            console.log(_datatokens[tokenOut].rate);
            tokenAmount = tokenAmountIn.mul(BASE).div(_datatokens[tokenOut].rate);
            console.log(tokenAmount,'tokenAmount');
            return (tokenAmount);
        }
        
        //no match, bail out
        return (0);
    }
}