// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Project {
    struct Campaign {
        uint256 id;
        address payable creator;
        string title;
        string description;
        uint256 targetAmount;
        uint256 raisedAmount;
        uint256 deadline;
        bool isActive;
        bool fundsWithdrawn;
        mapping(address => uint256) contributions;
        address[] contributors;
    }
    
    struct Contributor {
        address contributorAddress;
        uint256 amount;
        uint256 timestamp;
    }
    
    uint256 public campaignCounter;
    uint256 public totalCampaigns;
    uint256 public totalFundsRaised;
    address public platformOwner;
    uint256 public platformFeePercentage; // in basis points (e.g., 250 = 2.5%)
    
    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => Contributor[]) public campaignContributors;
    
    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        string title,
        uint256 targetAmount,
        uint256 deadline
    );
    
    event ContributionMade(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount,
        uint256 timestamp
    );
    
    event FundsWithdrawn(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 amount,
        uint256 timestamp
    );
    
    event RefundIssued(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );
    
    event CampaignStatusChanged(
        uint256 indexed campaignId,
        bool isActive
    );
    
    modifier onlyPlatformOwner() {
        require(msg.sender == platformOwner, "Only platform owner can perform this action");
        _;
    }
    
    modifier campaignExists(uint256 _campaignId) {
        require(_campaignId > 0 && _campaignId <= campaignCounter, "Campaign does not exist");
        _;
    }
    
    modifier onlyCampaignCreator(uint256 _campaignId) {
        require(campaigns[_campaignId].creator == msg.sender, "Only campaign creator can perform this action");
        _;
    }
    
    constructor() {
        platformOwner = msg.sender;
        campaignCounter = 0;
        totalCampaigns = 0;
        totalFundsRaised = 0;
        platformFeePercentage = 250; // 2.5% platform fee
    }
    
    /**
     * @dev Create a new crowdfunding campaign
     * @param _title Title of the campaign
     * @param _description Description of the campaign
     * @param _targetAmount Target funding amount in wei
     * @param _durationInDays Campaign duration in days
     */
    function createCampaign(
        string memory _title,
        string memory _description,
        uint256 _targetAmount,
        uint256 _durationInDays
    ) public {
        require(bytes(_title).length > 0, "Campaign title cannot be empty");
        require(bytes(_description).length > 0, "Campaign description cannot be empty");
        require(_targetAmount > 0, "Target amount must be greater than 0");
        require(_durationInDays > 0 && _durationInDays <= 365, "Duration must be between 1 and 365 days");
        
        campaignCounter++;
        totalCampaigns++;
        
        Campaign storage newCampaign = campaigns[campaignCounter];
        newCampaign.id = campaignCounter;
        newCampaign.creator = payable(msg.sender);
        newCampaign.title = _title;
        newCampaign.description = _description;
        newCampaign.targetAmount = _targetAmount;
        newCampaign.raisedAmount = 0;
        newCampaign.deadline = block.timestamp + (_durationInDays * 1 days);
        newCampaign.isActive = true;
        newCampaign.fundsWithdrawn = false;
        
        emit CampaignCreated(
            campaignCounter,
            msg.sender,
            _title,
            _targetAmount,
            newCampaign.deadline
        );
    }
    
    /**
     * @dev Contribute funds to a campaign
     * @param _campaignId ID of the campaign to contribute to
     */
    function contribute(uint256 _campaignId) public payable campaignExists(_campaignId) {
        Campaign storage campaign = campaigns[_campaignId];
        
        require(campaign.isActive, "Campaign is not active");
        require(block.timestamp < campaign.deadline, "Campaign has ended");
        require(msg.value > 0, "Contribution must be greater than 0");
        require(msg.sender != campaign.creator, "Campaign creator cannot contribute to own campaign");
        
        // Check if this is a new contributor
        if (campaign.contributions[msg.sender] == 0) {
            campaign.contributors.push(msg.sender);
        }
        
        campaign.contributions[msg.sender] += msg.value;
        campaign.raisedAmount += msg.value;
        totalFundsRaised += msg.value;
        
        // Add to contributors list for this campaign
        campaignContributors[_campaignId].push(Contributor({
            contributorAddress: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp
        }));
        
        emit ContributionMade(_campaignId, msg.sender, msg.value, block.timestamp);
    }
    
    /**
     * @dev Withdraw funds from a successful campaign
     * @param _campaignId ID of the campaign
     */
    function withdrawFunds(uint256 _campaignId) public campaignExists(_campaignId) onlyCampaignCreator(_campaignId) {
        Campaign storage campaign = campaigns[_campaignId];
        
        require(block.timestamp >= campaign.deadline, "Campaign is still active");
        require(campaign.raisedAmount >= campaign.targetAmount, "Campaign did not reach target amount");
        require(!campaign.fundsWithdrawn, "Funds have already been withdrawn");
        require(campaign.raisedAmount > 0, "No funds to withdraw");
        
        campaign.fundsWithdrawn = true;
        campaign.isActive = false;
        
        uint256 platformFee = (campaign.raisedAmount * platformFeePercentage) / 10000;
        uint256 creatorAmount = campaign.raisedAmount - platformFee;
        
        // Transfer platform fee to platform owner
        if (platformFee > 0) {
            payable(platformOwner).transfer(platformFee);
        }
        
        // Transfer remaining funds to campaign creator
        campaign.creator.transfer(creatorAmount);
        
        emit FundsWithdrawn(_campaignId, campaign.creator, creatorAmount, block.timestamp);
    }
    
    /**
     * @dev Request refund for failed campaign
     * @param _campaignId ID of the campaign
     */
    function requestRefund(uint256 _campaignId) public campaignExists(_campaignId) {
        Campaign storage campaign = campaigns[_campaignId];
        
        require(block.timestamp >= campaign.deadline, "Campaign is still active");
        require(campaign.raisedAmount < campaign.targetAmount, "Campaign was successful, no refunds available");
        require(campaign.contributions[msg.sender] > 0, "No contribution found for this address");
        require(!campaign.fundsWithdrawn, "Funds have already been withdrawn");
        
        uint256 contributionAmount = campaign.contributions[msg.sender];
        campaign.contributions[msg.sender] = 0;
        campaign.raisedAmount -= contributionAmount;
        
        payable(msg.sender).transfer(contributionAmount);
        
        emit RefundIssued(_campaignId, msg.sender, contributionAmount);
    }
    
   
    function getCampaign(uint256 _campaignId) public view campaignExists(_campaignId) returns (
        uint256 id,
        address creator,
        string memory title,
        string memory description,
        uint256 targetAmount,
        uint256 raisedAmount,
        uint256 deadline,
        bool isActive,
        bool fundsWithdrawn,
        uint256 contributorsCount
    ) {
        Campaign storage campaign = campaigns[_campaignId];
        return (
            campaign.id,
            campaign.creator,
            campaign.title,
            campaign.description,
            campaign.targetAmount,
            campaign.raisedAmount,
            campaign.deadline,
            campaign.isActive,
            campaign.fundsWithdrawn,
            campaign.contributors.length
        );
    }
    
    /**
     * @dev Get contributor's contribution amount for a campaign
     * @param _campaignId ID of the campaign
     * @param _contributor Address of the contributor
     * @return Contribution amount
     */
    function getContribution(uint256 _campaignId, address _contributor) public view campaignExists(_campaignId) returns (uint256) {
        return campaigns[_campaignId].contributions[_contributor];
    }
    
    /**
     * @dev Get all contributors for a campaign
     * @param _campaignId ID of the campaign
     * @return Array of contributor addresses
     */
    function getCampaignContributors(uint256 _campaignId) public view campaignExists(_campaignId) returns (address[] memory) {
        return campaigns[_campaignId].contributors;
    }
    
    function getCampaignContributionHistory(uint256 _campaignId) public view campaignExists(_campaignId) returns (
        address[] memory contributors,
        uint256[] memory amounts,
        uint256[] memory timestamps
    ) {
        Contributor[] storage history = campaignContributors[_campaignId];
        uint256 length = history.length;
        
        contributors = new address[](length);
        amounts = new uint256[](length);
        timestamps = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            contributors[i] = history[i].contributorAddress;
            amounts[i] = history[i].amount;
            timestamps[i] = history[i].timestamp;
        }
    }
    
    /**
     * @dev Check if campaign is successful
     * @param _campaignId ID of the campaign
     * @return true if campaign reached target amount
     */
    function isCampaignSuccessful(uint256 _campaignId) public view campaignExists(_campaignId) returns (bool) {
        return campaigns[_campaignId].raisedAmount >= campaigns[_campaignId].targetAmount;
    }
    
    /**
     * @dev Get platform statistics
     * @return Total campaigns, total funds raised, active campaigns count
     */
    function getPlatformStats() public view returns (uint256, uint256, uint256) {
        uint256 activeCampaigns = 0;
        for (uint256 i = 1; i <= campaignCounter; i++) {
            if (campaigns[i].isActive && block.timestamp < campaigns[i].deadline) {
                activeCampaigns++;
            }
        }
        return (totalCampaigns, totalFundsRaised, activeCampaigns);
    }
    
    /**
     * @dev Set platform fee (only platform owner)
     * @param _feePercentage New fee percentage in basis points
     */
    function setPlatformFee(uint256 _feePercentage) public onlyPlatformOwner {
        require(_feePercentage <= 1000, "Platform fee cannot exceed 10%");
        platformFeePercentage = _feePercentage;
    }
    
    /**
     * @dev Emergency function to deactivate a campaign (only platform owner)
     * @param _campaignId ID of the campaign
     */
    function deactivateCampaign(uint256 _campaignId) public onlyPlatformOwner campaignExists(_campaignId) {
        campaigns[_campaignId].isActive = false;
        emit CampaignStatusChanged(_campaignId, false);
    }
}
