// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/Math.sol";

contract Fund is AccessControl {
    
    // create events for websocket
    event PolicyDeposit(address indexed _from, uint _value);
    event PolicyClaim(address indexed _from, uint _value);
    event PolicyLapse(address indexed _from, uint _value);
    event InvestorDeposit(address indexed _from, uint _value);
    event InvestorProfit(address indexed _investor, uint _value);
    event InvestorSurplus(address indexed _investor, uint _value);

    // Create role identifiers
    bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR_ROLE");
    bytes32 public constant POLICYHOLDER_ROLE = keccak256("POLICYHOLDER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    
    // Create states for each role
    // investors
    struct Investment {
        address investor;
        uint deposit;
        uint surplus;
    }
    mapping(address => Investment) public investments;
    address[] public investors;
    
    // policyholders
    struct Policy {
        address recipient;
        uint deposit;
        uint payAmount;
        uint payTermRemain;
        uint lastClaimTime;
        bool inforce;
    }
    mapping(address => Policy) public policies;
    address[] public policyholders;
    
    // oracles
    address[] public oracles;
    uint public inflation = 50000; // bps - to be /10000
    uint public term = 30; // number of payments - one per term 
    uint public a_x = 1538; // annuity factor - 2 decimals accuracy - to be /100 - (1-(1+r)^-t)/r annuity certain
    uint public payInterval = 10 seconds; 
    uint public awolLimitTerm = 5; // number of terms to miss the claim before classified as dead
    uint public fee = 100; // bps /10000

    // balancce sheet
    uint public deposits; //for surplus distribution
    // assets are address(this).balance
    uint public liabilities;
    uint public solvencyTarget = 150; // percent to be /100
    uint public solvencyCeiling = 200; // percent to be /100
    
    // admin
    address[] public requestInvestors;
    address[] public requestPolicyholders;
    
    constructor (address root) {
        _setupRole(DEFAULT_ADMIN_ROLE, root);
    }
    
    // admin functions
    function updateSolvencyTarget(uint _target) public onlyAdmin() {
        solvencyTarget = _target;
    }
    
    // investor functions
    function invest() external payable onlyInvestor() isNotTooSmall(msg.value) {
        require(investments[msg.sender].deposit == 0, "Must not have any invested yet");
        uint max = liabilities * solvencyCeiling / solvencyTarget - address(this).balance;
        require(msg.value <= max, "Must not exceed solvency ceiling");
        investments[msg.sender] = Investment({
            investor: msg.sender,
            deposit: msg.value,
            surplus: 0
        });
        investors.push(msg.sender);
        deposits += msg.value;
    }
    
    function disvest(uint amount) external payable onlyInvestor() isSolvent() {
        uint max = investments[msg.sender].surplus;
        require(amount <= max, "Must not exceed the maximum allocated surplus value");
        investments[msg.sender].surplus -= amount;
        payable(msg.sender).transfer(amount);
        emit InvestorDeposit(msg.sender, msg.value);
    }
    
    function investedValue() external onlyInvestor() view returns(uint) {
        return investments[msg.sender].deposit;
    }
    
    // policyholder functions
    function policyRegister () external payable onlyPolicyholder isNotTooSmall(msg.value) {
        require(policies[msg.sender].inforce == false, "Must be a new policysholder");
        uint max = address(this).balance - liabilities;
        uint liability = msg.value * term * 100 / a_x;
        require(liability <= max, "Policy value is too high compared to available surplus");
        policies[msg.sender] = Policy({
            recipient: msg.sender,
            deposit: msg.value,
            payAmount: msg.value * 100 / a_x ,
            payTermRemain: term,
            lastClaimTime: block.timestamp,
            inforce: true
        });
        policyholders.push(msg.sender);
        liabilities += liability;
        emit PolicyDeposit(msg.sender, msg.value);
    }
    
    function policyClaim () external payable onlyPolicyholder {
        require(policies[msg.sender].inforce == true, "Policy is not inforce ");
        Policy memory policy = policies[msg.sender];
        uint termPay = Math.min((block.timestamp - policy.lastClaimTime) / payInterval, policy.payTermRemain);
        uint claimAmount = policy.payAmount * termPay;
        payable(msg.sender).transfer(claimAmount);
        policies[msg.sender].lastClaimTime = block.timestamp;
        policies[msg.sender].payTermRemain -= termPay;
        if (policies[msg.sender].payTermRemain == 0) {
            policies[msg.sender].inforce = false;
        }
        liabilities -= claimAmount;
    }
    
    // oracle functions
    // update basis - a_x
    function update_a_x(uint axFactor) external onlyOracle {
        a_x = axFactor;
    }
    
    // insurer functions
    
    function liabVal() external returns(uint) {
        // for each policy - liability value += payAmount * payTermRemain * (if inforce == true?)
        // update inforce to false when policy is lapsed (automatically) if no proof of survival is given for n interval
        liabilities = 0;
        for (uint i = 0; i < policyholders.length; i++){
            Policy memory policy = policies[policyholders[i]];
            uint current = block.timestamp;
            uint awol = (current - policy.lastClaimTime) / payInterval;
            uint liab = policy.payAmount * policy.payTermRemain * (policy.inforce ? 1 : 0);
            if (awol > awolLimitTerm) {
                policies[msg.sender].inforce = false;
                emit PolicyLapse(msg.sender, liab);
                profitSplit(liab);
            } else {
                liabilities += liab;
            }
        }
        return liabilities;
    }
    
    function profitSplit(uint surplus) private {
        uint oracleFee = surplus * fee / 1e4;
        this.payOracleFee(oracleFee);
        for (uint i = 0; i < investors.length; i++){
            Investment memory investment = investments[investors[i]];
            uint share = surplus * investment.deposit / deposits;
            investments[investors[i]].surplus += share;
            emit InvestorProfit(investors[i], share);
        }
    }
    
    function payOracleFee(uint _fee) external payable {
        payable(oracles[0]).transfer(_fee);
    }
    
    function surplusRebalance() external {
        uint surplus = Math.min(address(this).balance - liabilities * solvencyTarget / 100, 0);
        if (surplus > 0){
            for (uint i = 0; i < investors.length; i++){
                Investment memory investment = investments[investors[i]];
                uint share = surplus * investment.deposit / deposits;
                investments[investors[i]].surplus += share;
            }    
        }
    }
    
    function reset() external payable onlyAdmin {
        for (uint i = 0; i < investors.length; i++){
            investments[investors[i]].deposit = 0;
            investments[investors[i]].surplus = 0;
        }
        delete investors;
        delete requestInvestors;
        
        for (uint i = 0; i < policyholders.length; i++){
            policies[policyholders[i]].inforce = false;
        }
        delete policyholders;
        delete requestPolicyholders;
        
        delete oracles;
        deposits = 0;
        liabilities = 0;
        payable(msg.sender).transfer(address(this).balance);
    }
    
    modifier isNotTooSmall(uint _value){
        require(_value >= 1e6, "Must be greater than or equal to 1,000,000 wei");
        _;
    }
    
    modifier isSolvent(){
        require(address(this).balance * 100 / liabilities > solvencyTarget, "Must be above solvency target");
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
        for (uint i = 0; i < requestInvestors.length; i++){
            if (requestInvestors[i] == account) {
                requestInvestors[i] = requestInvestors[requestInvestors.length - 1];
                requestInvestors.pop();
            }
        }
    }
    
    function requestInvestor() public {
        requestInvestors.push(msg.sender);
    }
    
    function removeInvestor() public virtual onlyInvestor {
        revokeRole(INVESTOR_ROLE, msg.sender);
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
        for (uint i = 0; i < requestPolicyholders.length; i++){
            if (requestPolicyholders[i] == account) {
                requestPolicyholders[i] = requestPolicyholders[requestPolicyholders.length - 1];
                requestPolicyholders.pop();
            }
        }
    }
    
    function requestPolicyholder() public {
        requestPolicyholders.push(msg.sender);
    }
    
    function removePolicyholder() public virtual onlyPolicyholder {
        revokeRole(POLICYHOLDER_ROLE, msg.sender);
    }
    
    modifier onlyOracle() {
        require(isOracle(msg.sender), "Restricted to the oracle.");
        _;
    }
    
    function isOracle(address account) public virtual view returns (bool) {
        return hasRole(ORACLE_ROLE, account);
    }
    
    function addOracke(address account) public virtual onlyAdmin {
        require(oracles.length < 1, "Oracle has already been assigned");
        grantRole(ORACLE_ROLE, account);
        oracles.push(account);
    }
    
    function removeOracle(address account) public virtual onlyAdmin {
        revokeRole(ORACLE_ROLE, account);
        oracles.pop();
    }
    
}