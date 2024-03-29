// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";

contract RiskPoolToken is ERC20 {
    constructor() ERC20("RiskPoolToken","RPT") {
        _mint(msg.sender, 1000000);
    }
}