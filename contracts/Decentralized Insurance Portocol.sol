// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Insurance Protocol
 * @dev A smart contract for managing decentralized insurance policies
 * @author Decentralized Insurance Protocol Team
 */
contract Project {
    // State variables
    address public owner;
    uint256 public totalPolicies;
    uint256 public totalClaims;
    uint256 public constant PREMIUM_RATE = 100; // 1% premium rate (100 basis points)
    uint256 public constant CLAIM_PERIOD = 30 days;
    
    // Structs
    struct Policy {
        uint256 id;
        address holder;
        uint256 coverageAmount;
        uint256 premium;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool hasClaimed;
    }
    
    struct Claim {
        uint256 id;
        uint256 policyId;
        address claimant;
        uint256 claimAmount;
        string description;
        uint256 timestamp;
        ClaimStatus status;
    }
    
    enum ClaimStatus { Pending, Approved, Rejected, Paid }
    
    // Mappings
    mapping(uint256 => Policy) public policies;
    mapping(uint256 => Claim) public claims;
    mapping(address => uint256[]) public userPolicies;
    mapping(address => uint256) public userBalances;
    
    // Events
    event PolicyCreated(uint256 indexed policyId, address indexed holder, uint256 coverageAmount);
    event ClaimSubmitted(uint256 indexed claimId, uint256 indexed policyId, address indexed claimant);
    event ClaimProcessed(uint256 indexed claimId, ClaimStatus status, uint256 amount);
    event PremiumPaid(uint256 indexed policyId, address indexed holder, uint256 amount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }
    
    modifier validPolicy(uint256 _policyId) {
        require(_policyId > 0 && _policyId <= totalPolicies, "Invalid policy ID");
        require(policies[_policyId].isActive, "Policy is not active");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        totalPolicies = 0;
        totalClaims = 0;
    }
    
    /**
     * @dev Core Function 1: Create Insurance Policy
     * @param _coverageAmount The amount to be covered by the insurance
     * @param _duration Duration of the policy in seconds
     */
    function createPolicy(uint256 _coverageAmount, uint256 _duration) external payable {
        require(_coverageAmount > 0, "Coverage amount must be greater than 0");
        require(_duration >= 30 days, "Policy duration must be at least 30 days");
        
        uint256 premium = (_coverageAmount * PREMIUM_RATE) / 10000;
        require(msg.value >= premium, "Insufficient premium payment");
        
        totalPolicies++;
        
        policies[totalPolicies] = Policy({
            id: totalPolicies,
            holder: msg.sender,
            coverageAmount: _coverageAmount,
            premium: premium,
            startTime: block.timestamp,
            endTime: block.timestamp + _duration,
            isActive: true,
            hasClaimed: false
        });
        
        userPolicies[msg.sender].push(totalPolicies);
        
        // Refund excess payment
        if (msg.value > premium) {
            payable(msg.sender).transfer(msg.value - premium);
        }
        
        emit PolicyCreated(totalPolicies, msg.sender, _coverageAmount);
        emit PremiumPaid(totalPolicies, msg.sender, premium);
    }
    
    /**
     * @dev Core Function 2: Submit Insurance Claim
     * @param _policyId The ID of the policy for which claim is being made
     * @param _claimAmount The amount being claimed
     * @param _description Description of the claim
     */
    function submitClaim(
        uint256 _policyId, 
        uint256 _claimAmount, 
        string memory _description
    ) external validPolicy(_policyId) {
        Policy storage policy = policies[_policyId];
        
        require(policy.holder == msg.sender, "Only policy holder can submit claims");
        require(!policy.hasClaimed, "Claim already submitted for this policy");
        require(_claimAmount <= policy.coverageAmount, "Claim amount exceeds coverage");
        require(block.timestamp <= policy.endTime, "Policy has expired");
        require(
            block.timestamp >= policy.startTime + CLAIM_PERIOD, 
            "Claim period has not started yet"
        );
        
        totalClaims++;
        
        claims[totalClaims] = Claim({
            id: totalClaims,
            policyId: _policyId,
            claimant: msg.sender,
            claimAmount: _claimAmount,
            description: _description,
            timestamp: block.timestamp,
            status: ClaimStatus.Pending
        });
        
        policy.hasClaimed = true;
        
        emit ClaimSubmitted(totalClaims, _policyId, msg.sender);
    }
    
    /**
     * @dev Core Function 3: Process Insurance Claim (Admin function)
     * @param _claimId The ID of the claim to process
     * @param _approve Whether to approve or reject the claim
     */
    function processClaim(uint256 _claimId, bool _approve) external onlyOwner {
        require(_claimId > 0 && _claimId <= totalClaims, "Invalid claim ID");
        
        Claim storage claim = claims[_claimId];
        require(claim.status == ClaimStatus.Pending, "Claim already processed");
        
        if (_approve) {
            require(address(this).balance >= claim.claimAmount, "Insufficient contract balance");
            
            claim.status = ClaimStatus.Approved;
            userBalances[claim.claimant] += claim.claimAmount;
            
            emit ClaimProcessed(_claimId, ClaimStatus.Approved, claim.claimAmount);
        } else {
            claim.status = ClaimStatus.Rejected;
            
            // Reactivate policy for rejected claims
            Policy storage policy = policies[claim.policyId];
            policy.hasClaimed = false;
            
            emit ClaimProcessed(_claimId, ClaimStatus.Rejected, 0);
        }
    }
    
    /**
     * @dev Withdraw approved claim amount
     */
    function withdrawClaim() external {
        uint256 amount = userBalances[msg.sender];
        require(amount > 0, "No approved claims to withdraw");
        
        userBalances[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        
        // Update claim status to paid
        for (uint256 i = 1; i <= totalClaims; i++) {
            if (claims[i].claimant == msg.sender && claims[i].status == ClaimStatus.Approved) {
                claims[i].status = ClaimStatus.Paid;
            }
        }
    }
    
    /**
     * @dev Get user's policies
     * @param _user Address of the user
     * @return Array of policy IDs owned by the user
     */
    function getUserPolicies(address _user) external view returns (uint256[] memory) {
        return userPolicies[_user];
    }
    
    /**
     * @dev Get policy details
     * @param _policyId ID of the policy
     * @return Policy details
     */
    function getPolicyDetails(uint256 _policyId) external view returns (
        uint256 id,
        address holder,
        uint256 coverageAmount,
        uint256 premium,
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        bool hasClaimed
    ) {
        Policy memory policy = policies[_policyId];
        return (
            policy.id,
            policy.holder,
            policy.coverageAmount,
            policy.premium,
            policy.startTime,
            policy.endTime,
            policy.isActive,
            policy.hasClaimed
        );
    }
    
    /**
     * @dev Get claim details
     * @param _claimId ID of the claim
     * @return Claim details
     */
    function getClaimDetails(uint256 _claimId) external view returns (
        uint256 id,
        uint256 policyId,
        address claimant,
        uint256 claimAmount,
        string memory description,
        uint256 timestamp,
        ClaimStatus status
    ) {
        Claim memory claim = claims[_claimId];
        return (
            claim.id,
            claim.policyId,
            claim.claimant,
            claim.claimAmount,
            claim.description,
            claim.timestamp,
            claim.status
        );
    }
    
    /**
     * @dev Emergency withdrawal function (only owner)
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    /**
     * @dev Get contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @dev Fallback function to receive Ether
     */
    receive() external payable {}
}

