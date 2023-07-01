// SPDX-License-Identifier: MIT
import "./interfaces/ILPToken.sol";
import "./lptoken.sol";
import "./interfaces/IAMM.sol";

pragma solidity ^0.8.9;

contract AMMbasic {
//全局变量


    address owner;
    uint constant ONE_ETH = 10 ** 18;
    mapping(address => address) pairCreator;//lpAddr pairCreator
    address [] public lpTokenAddressList;//lptoken的数组
    mapping(address => mapping(address => uint)) reserve;//第一个address是lptoken的address ，第2个是相应token的资产，uint是资产的amount
    uint userFee;//fee to pool
    mapping(address => mapping(address => address)) public findLpToken;//查找到lptoken
    mapping (address=> mapping (address => address)) public findStableLpToken;//查找到稳定币的lptoken
    mapping (address=>uint) stablelpParameterA;//调控稳定币对的交易参数
    mapping (address => address[2]) _lpInfo;//通过lp找到原来两个币对
    mapping (address => bool) _lpSwapStatic;//稳定币交易暂停




    constructor()
    {
        owner = msg.sender;
    }

    receive() payable external {}

    //防止重入攻击
    modifier reEntrancyMutex() {
        bool _reEntrancyMutex;

        require(!_reEntrancyMutex,"FUCK");
        _reEntrancyMutex = true;
        _;
        _reEntrancyMutex = false;

    }
    //管理员权限
    modifier onlyOwner (){
        require(msg.sender == owner,"fuck");
        _;
    }

//管理人员权限

    function transferOwnership(address _newOwner) external onlyOwner{
        owner = _newOwner;
    }
    function setFee(uint fee) external onlyOwner{
        userFee = fee;
    }

    function setlpA(address _lpPair, uint _A) public  onlyOwner{
        stablelpParameterA[_lpPair] = _A;
    }

    //是否暂停lp的交易
    function setLpSwapStatic(address _lpAddr, bool _static) external onlyOwner{
        _lpSwapStatic[_lpAddr] = _static;
    }

//业务合约
    //添加流动性





    function addLiquidity(address _token0, address _token1, uint _amount0,uint _amount1) public returns (uint shares) {
        
        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        
        require(_amount0 > 0 ,"require _amount0 > 0 && _amount1 >0");
        require(_token0 != _token1, "_token0 == _token1");
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        
        address lptokenAddr;


        //当流动性对未被创建的时候
        if (findLpToken[_token1][_token0] == address(0)) {

            //可以lp做市商可以得到的lptoken数量
            shares = _sqrt(_amount0 * _amount1);

            //创建lp对
            createPair(_token0,_token1);

            //找到lp地址并铸造lptoken
            lptokenAddr = findLpToken[_token1][_token0];
            lptoken = ILPToken(lptokenAddr);

            //记录lptoken对的创建者
            pairCreator[lptokenAddr] = msg.sender;

            token0.transferFrom(msg.sender, address(this), _amount0);
            token1.transferFrom(msg.sender, address(this), _amount1);

            
        } else {

            //lpaddr不为0时
            lptokenAddr = findLpToken[_token1][_token0];
            lptoken = ILPToken(lptokenAddr);
            shares = _min(
                (_amount0 * lptoken.totalSupply()) / reserve[lptokenAddr][_token0],
                (_amount1 * lptoken.totalSupply()) / reserve[lptokenAddr][_token1]
            );

            //重新计算amount1的数量
            _amount1 = reserve[lptokenAddr][_token1] * _amount0 / reserve[lptokenAddr][_token0];

            token0.transferFrom(msg.sender, address(this), _amount0);
            token1.transferFrom(msg.sender, address(this), _amount1);
        }
        require(shares > 0, "shares = 0");

        //铸造lptoken
        lptoken.mint(msg.sender,shares);
        

        _update(lptokenAddr,_token0, _token1, reserve[lptokenAddr][_token0] + _amount0, reserve[lptokenAddr][_token1] + _amount1);
    }

    // 用户添加流动性
    function addLiquidityWithStablePairByUser(address _token0, address _token1, uint _amount0) public returns (uint shares) {
        
        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        
        require(_amount0 > 0 ,"require _amount0 > 0 && _amount1 >0");
        require(_token0 != _token1, "_token0 == _token1");

        //判断是否为稳定币的lp对
        require(findStableLpToken[_token0][_token1] != address(0),"invalid tokenpair");
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        
        address lptokenAddr;
        
        lptokenAddr = findStableLpToken[_token1][_token0];

        uint amount1 =   reserve[lptokenAddr][_token1] * _amount0 / reserve[lptokenAddr][_token0];

        token0.transferFrom(msg.sender, address(this), _amount0);
        token1.transferFrom(msg.sender, address(this), amount1);

        lptoken = ILPToken(lptokenAddr);
        shares = _min(
            (_amount0 * lptoken.totalSupply()) / reserve[lptokenAddr][_token0],
            (amount1 * lptoken.totalSupply()) / reserve[lptokenAddr][_token1]
        );

        require(shares > 0, "shares = 0");
        lptoken.mint(msg.sender,shares);
        

        _update(lptokenAddr,_token0, _token1, reserve[lptokenAddr][_token0] + _amount0, reserve[lptokenAddr][_token1] + amount1);

    }

    function addLiquidityWithStablePair(address _token0, address _token1, uint _amount0,uint _amount1) internal returns (uint shares) {
        
        
        
        require(_amount0 > 0 ,"require _amount0 > 0 && _amount1 >0");
        require(_token0 != _token1, "_token0 == _token1");
        require(findStableLpToken[_token0][_token1] == address(0),"alredy add liquidity");
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        token0.transferFrom(msg.sender, address(this), _amount0);
        token1.transferFrom(msg.sender, address(this), _amount1);
        address lptokenAddr;


        shares = _sqrt(_amount0 * _amount1);
        lptokenAddr = createStablePair(_token0,_token1);

        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        lptoken = ILPToken(lptokenAddr);//获取lptoken地址

        pairCreator[lptokenAddr] = msg.sender;
            
        require(shares > 0, "shares = 0");
        lptoken.mint(msg.sender,shares);

        

        _update(lptokenAddr,_token0, _token1, reserve[lptokenAddr][_token0] + _amount0, reserve[lptokenAddr][_token1] + _amount1);

    }

    function addLiquidityWithStablePairByOwner(address _token0, address _token1, uint _amount0,uint _amount1, uint _A) public onlyOwner
    //移除流动性
    {
        addLiquidityWithStablePair(_token0, _token1, _amount0, _amount1);
        setlpA(findStableLpToken[_token0][_token1], _A);
    }
    function removeLiquidity(
        address _token0,
        address _token1,
        uint _shares
    ) public  returns (uint amount0, uint amount1) {
        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        address lptokenAddr = findLpToken[_token0][_token1];

        lptoken = ILPToken(lptokenAddr);

        if(pairCreator[lptokenAddr] == msg.sender)
        {
            require(lptoken.balanceOf(msg.sender) - _shares > 100 ,"paieCreator should left 100 wei lptoken in pool");
        }

        amount0 = (_shares * reserve[lptokenAddr][_token0]) / lptoken.totalSupply();//share * totalsuply/bal0
        amount1 = (_shares * reserve[lptokenAddr][_token1]) / lptoken.totalSupply();
        require(amount0 > 0 && amount1 > 0, "amount0 or amount1 = 0");

        lptoken.burn(msg.sender, _shares);
        _update(lptokenAddr,_token0, _token1, reserve[lptokenAddr][_token0] - amount0, reserve[lptokenAddr][_token1] - amount1);
        

        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
    }

    function removeLiquidityWithStableCoin(
        address _token0,
        address _token1,
        uint _shares
    ) public  returns (uint amount0, uint amount1) {
        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        address lptokenAddr = findStableLpToken[_token0][_token1];

        lptoken = ILPToken(lptokenAddr);

        if(pairCreator[lptokenAddr] == msg.sender)
        {
            require(lptoken.balanceOf(msg.sender) - _shares > 100 ,"paieCreator should left 100 wei lptoken in pool");
        }

        amount0 = (_shares * reserve[lptokenAddr][_token0]) / lptoken.totalSupply();//share * totalsuply/bal0
        amount1 = (_shares * reserve[lptokenAddr][_token1]) / lptoken.totalSupply();
        require(amount0 > 0 && amount1 > 0, "amount0 or amount1 = 0");

        lptoken.burn(msg.sender, _shares);
        _update(lptokenAddr,_token0, _token1, reserve[lptokenAddr][_token0] - amount0, reserve[lptokenAddr][_token1] - amount1);
        

        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
    }

    //交易

  


    function swapByPath(uint _amountIn, uint _disirSli,address [] memory _path) public {
        uint amountIn = _amountIn;
        for(uint i; i < _path.length - 1; i ++ ){
            (address tokenIn,address tokenOut) = (_path[i],_path[i + 1]);
            amountIn = swap(tokenIn, tokenOut, amountIn, _disirSli);
        }
    }

    function swap(address _tokenIn, address _tokenOut, uint _amountIn, uint _disirSli) public returns(uint amountOut){
        require(
            findLpToken[_tokenIn][_tokenOut] != address(0),
            "invalid token"
        );
        require(_amountIn > 0, "amount in = 0");
        require(_tokenIn != _tokenOut);
        require(_amountIn >= 1000, "require amountIn >= 1000 wei token");

        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = IERC20(_tokenOut);
        address lptokenAddr = findLpToken[_tokenIn][_tokenOut];
        uint reserveIn = reserve[lptokenAddr][_tokenIn];
        uint reserveOut = reserve[lptokenAddr][_tokenOut];

        tokenIn.transferFrom(msg.sender, address(this), _amountIn);


        //交易税收 
        uint amountInWithFee = (_amountIn * (10000-userFee)) / 10000;
        amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);

        //检查滑点
        setSli(amountInWithFee,reserveIn,reserveOut,_disirSli);


        tokenOut.transfer(msg.sender, amountOut);
        uint totalReserve0 = reserve[lptokenAddr][_tokenIn] + _amountIn; 
        uint totalReserve1 = reserve[lptokenAddr][_tokenOut] - amountOut;

        _update(lptokenAddr,_tokenIn, _tokenOut, totalReserve0, totalReserve1);

    }



    function swapWithStableCoin(address _tokenIn, address _tokenOut, uint _amountIn) public returns(uint amountOut){
        require(
            findStableLpToken[_tokenIn][_tokenOut] != address(0),
            "invalid token"
        );
        
        require(_amountIn > 0, "amount in = 0");
        require(_tokenIn != _tokenOut);
        require(_amountIn >= 1000, "require amountIn >= 1000 wei token");
        //require(isStablePair[findLpToken[_tokenIn][_tokenOut]],"not stablePair");

        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = IERC20(_tokenOut);
        address lptokenAddr = findStableLpToken[_tokenIn][_tokenOut];
        require(!getLpSwapStatic(lptokenAddr),"swapPair pausing");
        uint reserveIn = reserve[lptokenAddr][_tokenIn];
        uint reserveOut = reserve[lptokenAddr][_tokenOut];

        tokenIn.transferFrom(msg.sender, address(this), _amountIn);


        //交易税收 
        uint amountInWithFee = (_amountIn * (10000-userFee)) / 10000;

        //计算输出token数量
        amountOut = calOutput(getA(lptokenAddr),reserveIn + reserveOut, reserveIn,amountInWithFee);

        tokenOut.transfer(msg.sender, amountOut);
        uint totalReserve0 = reserve[lptokenAddr][_tokenIn] + _amountIn; 
        uint totalReserve1 = reserve[lptokenAddr][_tokenOut] - amountOut;

        _update(lptokenAddr,_tokenIn, _tokenOut, totalReserve0, totalReserve1);

    }

    //暴露数据查询方法

    function getReserve(address _lpTokenAddr, address _tokenAddr) public view returns(uint)
    {
        return reserve[_lpTokenAddr][_tokenAddr];
    }

    function getUserFee()public view returns(uint) {
        return userFee;
        
    }

    function getLptoken(address _tokenA, address _tokenB) public view returns(address)
    {
        return findLpToken[_tokenA][_tokenB];
    }

    function getStableLptoken(address _tokenA, address _tokenB) public view returns(address)
    {
        return findStableLpToken[_tokenA][_tokenB];
    }

    function lptokenTotalSupply(address _token0, address _token1, address user) public view returns(uint)
    {
        ILPToken lptoken;
        lptoken = ILPToken(findLpToken[_token0][_token1]);
        uint totalSupply = lptoken.balanceOf(user);
        return totalSupply;
    }

    function getLptokenLength() public view returns(uint)
    {
        return lpTokenAddressList.length;
    }

    function getlptokenList(uint _index) public view returns(address)
    {
        return lpTokenAddressList[_index];
    }

//依赖方法
    //creatpair

    function createPair(address addrToken0, address addrToken1) internal returns(address){
        bytes32 _salt = keccak256(
            abi.encodePacked(
                addrToken0,addrToken1
            )
        );

        address lptokenAddr = address(new LPToken{
            salt : bytes32(_salt)
        }
        ());

         //检索lptoken
        lpTokenAddressList.push(lptokenAddr);
        findLpToken[addrToken0][addrToken1] = lptokenAddr;
        findLpToken[addrToken1][addrToken0] = lptokenAddr;

        _lpInfo[lptokenAddr] = [addrToken0,addrToken1];

        return lptokenAddr;
    }

    function createStablePair(address addrToken0, address addrToken1) internal returns(address){
        bytes32 _salt = keccak256(
            abi.encodePacked(
                addrToken0,addrToken1,"stablecoin"
            )
        );
        address lptokenAddr = address(new LPToken{
            salt : bytes32(_salt)
        }
        ());

         //检索lptoken
        lpTokenAddressList.push(lptokenAddr);
        findStableLpToken[addrToken0][addrToken1] = lptokenAddr;
        findStableLpToken[addrToken1][addrToken0] = lptokenAddr;

        _lpInfo[lptokenAddr] = [addrToken0,addrToken1];

        return lptokenAddr;
    }

    function getBytecode() internal pure returns(bytes memory) {
        bytes memory bytecode = type(LPToken).creationCode;
        return bytecode;
    }

    function getAddress(bytes memory bytecode, bytes32 _salt)
        internal
        view
        returns(address)
    {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), address(this), _salt, keccak256(bytecode)
            )
        );

        return address(uint160(uint(hash)));
    }

    function getA(address _lpAddr) public view returns(uint){
        return stablelpParameterA[_lpAddr];
    }

    function getlpInfo(address _lpAddr) public view returns(address [2] memory){
        return _lpInfo[_lpAddr];
    }

    function getLpSwapStatic(address _lpAddr) public view returns(bool){
        return _lpSwapStatic[_lpAddr];
    }

    //数据更新

    function _update(address lptokenAddr,address _token0, address _token1, uint _reserve0, uint _reserve1) private {
        reserve[lptokenAddr][_token0] = _reserve0;
        reserve[lptokenAddr][_token1] = _reserve1;
    }

//数学库

    function cacalTokenOutAmount(address _tokenIn, address _tokenOut, uint _tokenInAmount) public view returns(uint tokenOutAmount)
    {
        address lptokenAddr = getLptoken(_tokenIn,_tokenOut);
        uint reserveIn = getReserve(lptokenAddr, _tokenIn);
        uint reserveOut = getReserve(lptokenAddr,_tokenOut);

        tokenOutAmount = (reserveOut * _tokenInAmount) / (reserveIn + _tokenInAmount);
    }

    function _sqrt(uint y) private pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }

    function setSli(uint dx, uint x, uint y, uint _disirSli) private pure returns(uint){


        uint amountOut = (y * dx) / (x + dx);

        uint dy = dx * y/x;
        /*
        loseAmount = Idea - ammOut
        Sli = loseAmount/Idea
        Sli = [dx*y/x - y*dx/(dx + x)]/dx*y/x
        */
        uint loseAmount = dy - amountOut;

        uint Sli = loseAmount * 10000 /dy;
        
        require(Sli <= _disirSli, "Sli too large");
        return Sli;

    }

    function setSliBystable(uint _amountOut,uint dx, uint x, uint y, uint _disirSli) public pure returns(uint){


        uint amountOut = _amountOut;

        uint dy = dx * y/x;
        /*
        loseAmount = Idea - ammOut
        Sli = loseAmount/Idea
        Sli = [dx*y/x - y*dx/(dx + x)]/dx*y/x
        */
        uint loseAmount = dy - amountOut;

        uint Sli = loseAmount * 100000 /dy;
        
        require(Sli <= _disirSli, "Sli too large");
        return Sli;

    }




    function calOutAmount(uint A, uint D, uint X)public pure returns(uint)
    {
        //return  (4*A*D*D*X+calSqrt(A, D, X) -4*X-4*A*D*X*X) / (8*A*D*X);
        uint a = 4*A*D*X+D*calSqrt(A, D, X)-4*A*X*X-D*X;
        //uint amountOut2 = y - amountOut1;
        return a/(8*A*X);

    }

    function calOutput(uint A, uint D, uint X,uint dx)public pure returns(uint)
    {
        //D = D * 10**18;
        //X = X * 10**18;
        //dx = dx* 10**18;
        uint S = X + dx;
        uint amount1 = calOutAmount(A, D, X);
        uint amount2 = calOutAmount(A, D, S);

        //uint amountOut2 = y - amountOut1;
        return amount1 - amount2;

    }

    


    function calSqrt(uint A, uint D, uint X)public pure returns(uint)
    {
        //uint T = t(A,D,X);
        //uint calSqrtNum = _sqrt((X*(4+T))*(X*(4+T))+T*T*D*D+4*T*D*D-2*X*T*D*(4+T));
        //return calSqrtNum;
        (uint a, uint b) = (4*A*X*X/D+X,4*A*X);
        uint c;
        if(a>=b){
            c = a -b;
        }else{
            c = b-a;
        }

        return _sqrt(c*c+4*D*X*A);

    }



}
