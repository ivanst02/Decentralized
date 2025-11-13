// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.26;

contract BulBank{
    uint256 private  lastResult;
    address public owner;
    bool public active;

    uint256 private currentAssets; // contains the assets added by the owner to pay interests
    uint256 private flatInterest; // cointains the interest% rate that is configured
    uint256[3] private interestPlanInterest; // contains the interest% for each plan treshold
    uint256[2] private interestPlanMinutes; // contains the minutes for each plan treshold
    bool private isPlanSet; // check if the interest of the withdraw is flat or interest plan

    mapping (address => bool) private users; // used to track if an address is an useer
    mapping (address => bool) private admins; // used to track in an address is an admin

    struct DepositHistory{
        uint256 amount;
        uint256 depositTimestamp;
        uint256 depositMaturity;
        uint256 withdrawTimestamp;   
        uint256 interestRate;
    } 

    mapping (address => DepositHistory) private deposits;

    constructor(){
        owner = msg.sender;
        active = false;
        flatInterest = 1;
        isPlanSet = false;
    }

    function add(uint256 a, uint256 b) public{
        lastResult = a + b;
    }

    function multiply(uint256 a, uint256 b) public {
        lastResult = a * b;
    }
    
    function getLastResult() external view returns (uint256){
        return lastResult;
    }

    function getEthBalance() onlyIfUser external view returns (uint256){
        return address(this).balance; 
    }

    // changes made to contain the interest rate set at the initial investment
    function loadEth() onlyIfUser onlyIfBankActive external payable {
        require(deposits[msg.sender].depositTimestamp == 0, 'You Have already deposited.');
        DepositHistory memory newDeposit = DepositHistory({
            amount: msg.value,
            depositTimestamp: block.timestamp,
            depositMaturity: block.timestamp + 2 minutes,
            withdrawTimestamp: 0,
            interestRate: flatInterest
        });
        deposits[msg.sender] = newDeposit;
    }

    modifier onlyOwner(){
        if(msg.sender != owner){
            revert('Only owner can call this function.');
        }
        _;
    }

    modifier onlyDepositors(){
        if( deposits[msg.sender].depositTimestamp == 0){
            revert('Only Depositor can withdraw.');
        }
        _;
    }

     modifier onlyMatureDeposits(){
        if(deposits[msg.sender].depositMaturity > block.timestamp){
            revert('Deposit is not matured yet.');
        }
        _;
    }

    modifier onlyWithSufficientDeposit(uint256 amount){
        if(deposits[msg.sender].amount < amount){
            revert('Insufficient deposit amount');
        }
        _;
    }

   modifier onlyIfBankActive(){
    if(!active){
        revert('Bank is not active');
   }
   _;
   }
    // calculates the interest of the investment withdraws the amount from the deposit and withdraws the interest from the assets
    // !!!!! if an investor desides to withdraw 20 the func will give them 20 + interests !!!!!
    function withdraw(uint256 amount) onlyDepositors onlyWithSufficientDeposit(amount) onlyIfUser external {
        uint256 accInterest;
        if(isPlanSet) {
            accInterest =
            (deposits[msg.sender].amount * (1 + (currentPlanInterestRate() / 100) * getMinutes())) - deposits[msg.sender].amount;
        }
        else {
            accInterest =
            (deposits[msg.sender].amount * (1 + (flatInterest / 100) * getMinutes())) - deposits[msg.sender].amount;
        }
        deposits[msg.sender].amount -= amount;
        currentAssets -= accInterest;
        deposits[msg.sender].withdrawTimestamp = block.timestamp;
        payable(msg.sender).transfer(amount + accInterest);
    }

    function setBankStatus(bool _bankStatus) external onlyOwner{
        active = _bankStatus;
    }

    // owner makes an investment to pay interests with
    function addAsset() onlyOwner external payable {
        currentAssets += msg.value;
    }

    // returns the value of the remaining assets
    function getCurrentAssets() onlyOwner external view returns (uint256) {
        return currentAssets;
    }

    // returns the value of the remaining (not yet withdrawn) investment
    function getCurrentBalance() onlyIfUser external view returns (uint256) {
        return deposits[msg.sender].amount;
    }

    // sets a flat interest % (affects only deposits made after the change by design)
    function setInterestRate(uint256 _interest) onlyIfAdmin external {
        flatInterest = _interest;
    }

    // internal func used to calculate the time between the time of deposit and withdraw
    function getMinutes() internal view returns (uint256) {
        return (block.timestamp - deposits[msg.sender].depositTimestamp) / 60;
    }
    
    // check is an address is an admin (owner is an admin by default)
    modifier onlyIfAdmin() {
        if((msg.sender != owner) && (!admins[msg.sender])){
            revert('Only admins can call this function.');
        }
        _;
    }
    
    // check if an address is an user (owner and admins are users by default)
    modifier onlyIfUser() {
        if(!users[msg.sender] && msg.sender != owner && !admins[msg.sender]){
            revert('Only registered users can call this function.');
        }
        _;
    }

    // set of 4 functions that give / remove admin / user priviliges from an address
    // if admin is removed, the address will not remain user unless previosli "registered"
    function makeUser(address userAddr) onlyIfAdmin external {
        users[userAddr] = true;
    }

    function removeUser(address userAddr) onlyIfAdmin external {
        users[userAddr] = false;
    }

    function makeAdmin(address adminAddr) onlyOwner external {
        admins[adminAddr] = true;
    }

    function removeAdmin(address adminAddr) onlyOwner external {
        admins[adminAddr] = false;
    }

    // used for testing returns true if address is admin
    function amIAdmin() external view returns (bool) {
        if(admins[msg.sender]) {
            return true;
        }
        return false;
    }

    // used to set a rate plan, takes 2 values for minutes and 3 treshhold values
    // treshold 1 = under minute value 1
    // treshold 2 = between minute value 1 and 2
    // treshold 3 = more than minute value 2
    function addInterestPlan(uint256 interest1, uint256 min1,
                             uint256 interest2, uint256 min2,
                             uint256 interest3
                             ) onlyIfAdmin external {
        interestPlanInterest[0] = interest1; interestPlanMinutes[0] = min1;
        interestPlanInterest[1] = interest2; interestPlanMinutes[1] = min2;
        interestPlanInterest[2] = interest3; 
    }

    // func returns the current threshold value of the interest plan
    function currentPlanInterestRate() internal view returns (uint256) {
        if(getMinutes() <= interestPlanMinutes[0]) {return interestPlanInterest[0];}
        if(getMinutes() <= interestPlanMinutes[1]) {return interestPlanInterest[1];}
        return interestPlanInterest[2];
    }

    // func that decides if interest calculation is make on a flat interest of the interest plan
    function setPlanStatus(bool _status) onlyIfAdmin external {
        isPlanSet = _status;
    }
}
