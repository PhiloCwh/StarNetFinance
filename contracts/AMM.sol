// SPDX-License-Identifier: MIT
//import "./lptoken.sol";
import "./interfaces/ILPToken.sol";
//import "./IERC20.sol";
import "./lptoken.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IAMM.sol";
//import "./StableAlgorithm.sol";

pragma solidity ^0.8.9;

contract AnchorFinance is IAMM{
//全局变量


    address owner;
    uint constant ONE_ETH = 10 ** 18;
    mapping(address => address) pairCreator;//lpAddr pairCreator
    address [] public lpTokenAddressList;//lptoken的数组
    mapping(address => mapping(address => uint)) reserve;//第一个address是lptoken的address ，第2个是相应token的资产，uint是资产的amount
    uint userFee;//fee to pool
    //检索lptoken
    mapping(address => mapping(address => address)) public findLpToken;
    mapping (address=> mapping (address => address)) public findStableLpToken;
    IWETH  WETH;
    address  WETHAddr;
    //mapping (address => bool) public isStablePair;
    mapping (address=>uint) stablelpParameterA;
    mapping (address => address[2]) _lpInfo;
    mapping (address => bool) _lpSwapStatic;




    constructor()
    {
        owner = msg.sender;
    }

    receive() payable external {}

    modifier reEntrancyMutex() {
        bool _reEntrancyMutex;

        require(!_reEntrancyMutex,"FUCK");
        _reEntrancyMutex = true;
        _;
        _reEntrancyMutex = false;

    }

    modifier onlyOwner (){
        require(msg.sender == owner,"fuck");
        _;
    }

//管理人员权限

    function transferOwnership(address _newOwner) external onlyOwner{
        owner = _newOwner;
    }
    function setFee(uint fee) external onlyOwner{
        userFee = fee;// dx / 10000
    }

    function setlpA(address _lpPair, uint _A) public  onlyOwner{
        stablelpParameterA[_lpPair] = _A;
    }

    function setWeth(address _wethAddr) external onlyOwner{
        WETH = IWETH(_wethAddr);
        WETHAddr = _wethAddr;
    }
    function setLpSwapStatic(address _lpAddr, bool _static) external onlyOwner{
        _lpSwapStatic[_lpAddr] = _static;
    }

//业务合约
    //添加流动性

    function addLiquidityWithETH(address _token, uint _tokenAmount) public payable reEntrancyMutex
    {
        uint ETHAmount = msg.value;
        address user = msg.sender;
       // address addr = address(this);
        WETH.depositETH{value : ETHAmount}();
        //WETH.approve(user,ETHAmount);
        WETH.transfer(user,ETHAmount);
        addLiquidity(WETHAddr,_token, ETHAmount,_tokenAmount);

    }



    function addLiquidity(address _token0, address _token1, uint _amount0,uint _amount1) public returns (uint shares) {
        
        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        
        require(_amount0 > 0 ,"require _amount0 > 0 && _amount1 >0");
        require(_token0 != _token1, "_token0 == _token1");
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        
        //token1.transferFrom(msg.sender, address(this), _amount1);
        address lptokenAddr;

        /*
        How much dx, dy to add?
        xy = k
        (x + dx)(y + dy) = k'
        No price change, before and after adding liquidity
        x / y = (x + dx) / (y + dy)
        x(y + dy) = y(x + dx)
        x * dy = y * dx
        x / y = dx / dy
        dy = y / x * dx
        */
        //问题：
        /*
        如果项目方撤出所有流动性后会存在问题
        1.添加流动性按照比例 0/0 会报错

        解决方案：
        每次添加至少n个token
        且remove流动性至少保留n给在amm里面

        */


        if (findLpToken[_token1][_token0] == address(0)) {
            //当lptoken = 0时，创建lptoken
            shares = _sqrt(_amount0 * _amount1);

            createPair(_token0,_token1);

            lptokenAddr = findLpToken[_token1][_token0];
            lptoken = ILPToken(lptokenAddr);//获取lptoken地址
            pairCreator[lptokenAddr] = msg.sender;

            token0.transferFrom(msg.sender, address(this), _amount0);
            token1.transferFrom(msg.sender, address(this), _amount1);

            
        } else {
            lptokenAddr = findLpToken[_token1][_token0];
            lptoken = ILPToken(lptokenAddr);//获取lptoken地址
            shares = _min(
                (_amount0 * lptoken.totalSupply()) / reserve[lptokenAddr][_token0],
                (_amount1 * lptoken.totalSupply()) / reserve[lptokenAddr][_token1]
            );
            _amount1 = reserve[lptokenAddr][_token1] * _amount0 / reserve[lptokenAddr][_token0];
            token0.transferFrom(msg.sender, address(this), _amount0);
            token1.transferFrom(msg.sender, address(this), _amount1);
            //获取lptoken地址
        }
        require(shares > 0, "shares = 0");
        lptoken.mint(msg.sender,shares);
        

        _update(lptokenAddr,_token0, _token1, reserve[lptokenAddr][_token0] + _amount0, reserve[lptokenAddr][_token1] + _amount1);
    }

    // to do
    function addLiquidityWithStablePairByUser(address _token0, address _token1, uint _amount0) public returns (uint shares) {
        
        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        
        require(_amount0 > 0 ,"require _amount0 > 0 && _amount1 >0");
        require(_token0 != _token1, "_token0 == _token1");
        require(findStableLpToken[_token0][_token1] != address(0),"invalid tokenpair");
        IERC20 token0 = IERC20(_token0);
        IERC20 token1 = IERC20(_token1);
        token0.transferFrom(msg.sender, address(this), _amount0);
        address lptokenAddr;
        



        lptokenAddr = findStableLpToken[_token1][_token0];
        //require(isStablePair[lptokenAddr],"not StablePair");
        uint amount1 =   reserve[lptokenAddr][_token1] * _amount0 / reserve[lptokenAddr][_token0];
        token1.transferFrom(msg.sender, address(this), amount1);
        lptoken = ILPToken(lptokenAddr);//获取lptoken地址
        shares = _min(
            (_amount0 * lptoken.totalSupply()) / reserve[lptokenAddr][_token0],
            (amount1 * lptoken.totalSupply()) / reserve[lptokenAddr][_token1]
        );
            //获取lptoken地址
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
        //lptokenAddr = findLpToken[_token1][_token0];

        ILPToken lptoken;//lptoken接口，为了mint 和 burn lptoken
        lptoken = ILPToken(lptokenAddr);//获取lptoken地址

        pairCreator[lptokenAddr] = msg.sender;
        //_amount1 = calOutput(100,reserve[lptokenAddr][_token0] + reserve[lptokenAddr][_token1], reserve[lptokenAddr][_token0],_amount0);


        //isStablePair[lptokenAddr] = true;
            
        require(shares > 0, "shares = 0");
        lptoken.mint(msg.sender,shares);

        //setlpA(lptokenAddr, _A);
        

        _update(lptokenAddr,_token0, _token1, reserve[lptokenAddr][_token0] + _amount0, reserve[lptokenAddr][_token1] + _amount1);

    }

    function addLiquidityWithStablePairByOwner(address _token0, address _token1, uint _amount0,uint _amount1, uint _A) public onlyOwner
    //移除流动性
    {
        addLiquidityWithStablePair(_token0, _token1, _amount0, _amount1);
        setlpA(findLpToken[_token0][_token1], _A);
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

    //交易

    function swapWithETH(address _tokenOut,uint _disirSli) public payable reEntrancyMutex
    {
        uint amountIn = msg.value;
        WETH.depositETH{value : amountIn}();
        swapByLimitSli(WETHAddr,_tokenOut,amountIn, _disirSli);
    }


    function swapToETH(address _tokenIn, uint _amountIn, uint _disirSli)public {
        uint amountOut = swapByLimitSli(_tokenIn,WETHAddr,_amountIn, _disirSli);
        WETH.withdrawETH(amountOut);
        address payable user = payable(msg.sender);
        user.transfer(amountOut);

    }


    function swapByPath(uint _amountIn, uint _disirSli,address [] memory _path) public {
        uint amountIn = _amountIn;
        for(uint i; i < _path.length - 1; i ++ ){
            (address tokenIn,address tokenOut) = (_path[i],_path[i + 1]);
            amountIn = swapByLimitSli(tokenIn, tokenOut, amountIn, _disirSli);
        }
    }

    function swapByLimitSli(address _tokenIn, address _tokenOut, uint _amountIn, uint _disirSli) public returns(uint amountOut){
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

    function calSwapWithStableCoinAmount(address _tokenIn, address _tokenOut, uint _amountIn) public view returns(uint reserveIn,uint reserveOut,uint amountOut){
        require(_amountIn > 0, "amount in = 0");
        require(_tokenIn != _tokenOut);

        address lptokenAddr = findStableLpToken[_tokenIn][_tokenOut];
        reserveIn = reserve[lptokenAddr][_tokenIn];
        reserveOut = reserve[lptokenAddr][_tokenOut];



        //交易税收 
        uint amountInWithFee = (_amountIn * (10000-userFee)) / 10000;
        //amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);
        amountOut = calOutput(getA(lptokenAddr),reserveIn + reserveOut, reserveIn,amountInWithFee);



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
        //amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);
        amountOut = calOutput(getA(lptokenAddr),reserveIn + reserveOut, reserveIn,amountInWithFee);

        //检查滑点
        //setSli(amountInWithFee,reserveIn,reserveOut,_disirSli);
        //setSliBystable(amountOut,amountInWithFee,reserveIn,reserveOut,_disirSli);


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

//依赖方法
    //creatpair

    function createPair(address addrToken0, address addrToken1) internal returns(address){
        bytes32 _salt = keccak256(
            abi.encodePacked(
                addrToken0,addrToken1
            )
        );
        new LPToken{
            salt : bytes32(_salt)
        }
        ();
        address lptokenAddr = getAddress(getBytecode(),_salt);

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
        new LPToken{
            salt : bytes32(_salt)
        }
        ();
        address lptokenAddr = getAddress(getBytecode(),_salt);

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

    function lpInfo(address _lpAddr) public view returns(address [2] memory){
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
