// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import {WETH} from "./WETH.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract MaticWETH is WETH {

    function deposit() public payable virtual override {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public virtual override {
        require(balanceOf(msg.sender) >= wad);
        _burn(msg.sender, wad);
        msg.sender.transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function withdraw(uint256 wad, address user) public virtual override{
        require(balanceOf(msg.sender) >= wad);
        _burn(msg.sender, wad);
        address(uint160(user)).transfer(wad);
        emit Withdrawal(user, wad);
    }
}
