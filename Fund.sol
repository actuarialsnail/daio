// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/Math.sol";

contract Fund is AccessControl {
    
    // Create role identifiers
    bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR_ROLE");
    bytes32 public constant POLICYHOLDER_ROLE = keccak256("POLICYHOLDER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    
    // Create states for each role
    // investors
    mapping(address => uint) public investments;
    address[] investors;
    
    // policyholders
    struct Policy {
        address recipient;
        uint deposit;
        uint payAmount;
        uint payTermRemain;
        uint paidTimeLast;
        bool inforce;
    }
    mapping(address => Policy) public policies;
    address[] policyholders;
    
    // oracles
    uint public inflation = 30000; // bps - to be /10000
    uint public term = 50; // number of payments - one per term 
    uint public a_x = 5000; // annuity factor - 2 decimals accuracy - to be /100
    uint public payInterval = 10 seconds; 
    uint public awolLimitTerm = 5; // number of terms to miss the claim before classified as dead
    
    // owner
    uint public fee = 100; // bps /10000

    // balancce sheet
    uint public assets;
    uint public liabilities;
    uint public solvencyTarget = 150; // percent
    
    constructor (address root) {
        _setupRole(DEFAULT_ADMIN_ROLE, root);
    }
    
    // admin functions
    function updateSolvencyTarget(uint _target) public onlyAdmin() {
        solvencyTarget = _target;
    }
    
    // investor functions
    function invest() external payable onlyInvestor() {
        investors.push(msg.sender);
        investments[msg.sender] += msg.value;
        assets += msg.value;
    }
    
    function maxDisvestValue(address _addr) external view returns(uint) {
        uint max = investments[_addr] * (assets / liabilities / solvencyTarget / 100);
        return max;
    }
    
    function disvest(uint amount) external payable onlyInvestor() isSolvent() {
        uint max = this.maxDisvestValue(msg.sender);
        require(amount < max, "Must be below the maximum investment value");
        investments[msg.sender] -= amount;
        assets -= amount;
        payable(msg.sender).transfer(amount);
    }
    
    function investedValue() external onlyInvestor() view returns(uint) {
        return investments[msg.sender];
    }
    
    // policyholder functions
    function policyRegister () external payable onlyPolicyholder {
        require(policies[msg.sender].inforce == false, "Must be a new policyholder");
        require(msg.value > 100, "Must be greater than 100 wei");
        
        policies[msg.sender] = Policy({
            recipient: msg.sender,
            deposit: msg.value,
            payAmount: msg.value / a_x,
            payTermRemain: term,
            paidTimeLast: block.timestamp,
            inforce: true
        });
        policyholders.push(msg.sender);
        liabilities += msg.value / a_x * term;
    }
    
    function policyClaim () external payable onlyPolicyholder {
        require(policies[msg.sender].inforce == false, "Policy is not inforce ");
        Policy memory policy = policies[msg.sender];
        uint termPay = Math.min((block.timestamp - policy.paidTimeLast) % payInterval, term);
        uint claimAmount = policy.payAmount * termPay;
        payable(msg.sender).transfer(claimAmount);
        liabilities -= claimAmount;
    }
    
    // oracle functions
    // update basis - a_x
    
    function liabVal () external {
        // for each policy - liability value += payAmount * payTermRemain * (if inforce == true?)
        // update inforce to false when policy is lapsed (automatically) if no proof of survival is given for n interval
        liabilities = 0;
        for (uint i = 0; i < policyholders.length; i++){
            Policy memory policy = policies[policyholders[i]];
            if (((block.timestamp - policy.paidTimeLast) % payInterval - term) > awolLimitTerm) {
                policies[policyholders[i]].inforce == false;
            } else {
                liabilities += policy.payAmount * policy.payTermRemain * (policy.inforce ? 1 : 0);
            }
        }
    }
    
    modifier isSolvent(){
        require(assets / liabilities * 100 > solvencyTarget, "Must be above solvency target");
        _;
    }
    
    // Role based access control 
    
    modifier onlyAdmin() {
        require(isAdmin(msg.sender), "Restricted to admins.");
        _;
    }
    
    function isAdmin(address account) public virtual view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account);
    }
    
    function addAdmin(address account) public virtual onlyAdmin {
        grantRole(DEFAULT_ADMIN_ROLE, account);
    }
    
    modifier onlyInvestor() {
        require(isInvestor(msg.sender), "Restricted to investors.");
        _;
    }
    
    function isInvestor(address account) public virtual view returns (bool) {
        return hasRole(INVESTOR_ROLE, account);
    }
    
    function addInvestor(address account) public virtual onlyAdmin {
        grantRole(INVESTOR_ROLE, account);
    }
    
    modifier onlyPolicyholder() {
        require(isPolicyholder(msg.sender), "Restricted to policyholders.");
        _;
    }
    
    function isPolicyholder(address account) public virtual view returns (bool) {
        return hasRole(POLICYHOLDER_ROLE, account);
    }
    
    function addPolicyholder(address account) public virtual onlyAdmin {
        grantRole(POLICYHOLDER_ROLE, account);
    }
    
    modifier onlyOracle() {
        require(isOracle(msg.sender), "Restricted to the oracle.");
        _;
    }
    
    function isOracle(address account) public virtual view returns (bool) {
        return hasRole(ORACLE_ROLE, account);
    }
    
    function addOracke(address account) public virtual onlyAdmin {
        grantRole(ORACLE_ROLE, account);
    }
    
}