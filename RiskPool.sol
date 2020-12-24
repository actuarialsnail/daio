// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.7.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract RiskPool is Ownable {
    
    // investor
    mapping(address => uint) public investments;
    uint public maxInvestor = 10; // easier divisibility

    // policholder
    struct Policy {
        address recipient;
        uint premiumInit;
        uint sumAssured;
        uint term; // also to be used for funds to be time-locked 
        bool inforce;
    }
    
    mapping(address => Policy) public policies;
    
    // administrator / owner - responsible for management, reporitng, maintenance and oracle
    address payable owner;
    uint private fee_bps = 100; // basis points
    
    // balance sheet
    uint public assets = 0;
    uint public notional_liabilities = 0;
    uint public basis_Ax_bps = 2;
    uint public NAV_total;
    uint public NAV_unlocked;
    uint public NAV_locked;

    event NewClaim (
        uint date,
        address receiver,
        uint amount
    );
    
    constructor() {
        owner = msg.sender;
    }
    
    function policyRegister (uint _term) external payable {
        policies[msg.sender].recipient = msg.sender;
        policies[msg.sender].premiumInit = msg.value;
        policies[msg.sender].term = _term;
        policies[msg.sender].sumAssured = msg.value * _term * basis_Ax_bps * 10000;
        policies[msg.sender].inforce = true;
        assets += msg.value;
        notional_liabilities += policies[msg.sender].sumAssured;
        owner.transfer(msg.value * fee_bps / 100);
    }
    
    function policyClaim (uint amount) external {
        msg.sender.transfer(policies[msg.sender].sumAssured);
        policies[msg.sender].inforce = false;
        emit NewClaim(block.timestamp, msg.sender, amount);
    }
    
    function basesUpdate (uint _basis_Ax_bps) external onlyOwner {
        basis_Ax_bps = _basis_Ax_bps;
    }
    
    function invest () external payable {
        investments[msg.sender] += msg.value;
        assets += msg.value;
        owner.transfer(msg.value * fee_bps / 100);
    }
    
    function balanceOf() external view returns(uint) {
        return address(this).balance;
    }
}
