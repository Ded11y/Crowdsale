// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract WETH is ERC20 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    constructor() public ERC20("Wrapped Ether", "WETH") {}

    function deposit() public virtual payable;

    function withdraw(uint256 wad) public virtual;

    function withdraw(uint256 wad, address user) public virtual;
}
