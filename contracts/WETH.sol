// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WETH is ERC20{
    constructor() ERC20("Wrapped Ether", "WETH") {}

    modifier reEntrancyMutex() {
        bool _reEntrancyMutex;

        require(!_reEntrancyMutex,"FUCK");
        _reEntrancyMutex = true;
        _;
        _reEntrancyMutex = false;

    }

    function depositETH() payable public reEntrancyMutex  {
        _mint(msg.sender, msg.value);
    }

    function withdrawETH(uint _amount) public reEntrancyMutex returns(uint amount){
        _burn(msg.sender,_amount);
        address payable user = payable(msg.sender);
        user.transfer(_amount);
        amount = _amount;
    }
}
