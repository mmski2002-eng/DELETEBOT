// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../interfaces/IERC4907.sol";
import "../interfaces/IPriceOracle.sol";

/**
 * @title NFTFlow
 * @dev Main contract for NFT rental marketplace on Somnia Network
 * Enables micro-rentals with real-time payment streaming
 */
contract NFTFlow is ReentrancyGuard, Pausable, Ownable {

    // Struct to represent a rental
    struct Rental {
        address nftContract;
        uint256 tokenId;
        address owner;
        address renter;
        uint256 pricePerSecond;
        uint256 startTime;
        uint256 endTime;
        uint256 collateralAmount;
        bool active;
        bool completed;
    }

    // Struct for rental listings
    struct RentalListing {
        address nftContract;
        uint256 tokenId;
        address owner;
        uint256 pricePerSecond;
        uint256 minRentalDuration;
        uint256 maxRentalDuration;
        uint256 collateralRequired;
        bool active;
    }

    // State variables
    mapping(uint256 => Rental) public rentals;
    mapping(bytes32 => RentalListing) public listings;
    mapping(address => uint256[]) public userRentals;
    mapping(address => uint256[]) public ownerListings;
    mapping(address => uint256) public userCollateralBalance;
    
    uint256 public nextRentalId;
    uint256 public platformFeePercentage = 250; // 2.5%
    uint256 public constant MAX_RENTAL_DURATION = 30 days;
    uint256 public constant MIN_RENTAL_DURATION = 1; // 1 second
    
    address public paymentStreamContract;
    address public reputationContract;
    address public utilityTrackerContract;
    IPriceOracle public priceOracle;
    
    // DAO integration
    address public daoContract;
    uint256 public collateralMultiplier = 2; // 2x collateral
    address public feeRecipient;

    // Events
    event RentalListed(
        bytes32 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address owner,
        uint256 pricePerSecond
    );
    
    event RentalCreated(
        uint256 indexed rentalId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address owner,
        address renter,
        uint256 duration,
        uint256 totalCost
    );
    
    event RentalCompleted(
        uint256 indexed rentalId,
        address indexed renter,
        bool successful
    );
    
    event CollateralDeposited(
        address indexed user,
        uint256 amount
    );
    
    event CollateralWithdrawn(
        address indexed user,
        uint256 amount
    );
    
    event ParameterUpdated(
        string indexed key,
        bytes value
    );
    
    event DAOContractUpdated(
        address indexed newDAO
    );

    constructor(
        address _priceOracle,
        address _paymentStreamContract,
        address _reputationContract,
        address _utilityTrackerContract
    ) {
        priceOracle = IPriceOracle(_priceOracle);
        paymentStreamContract = _paymentStreamContract;
        reputationContract = _reputationContract;
        utilityTrackerContract = _utilityTrackerContract;
        feeRecipient = msg.sender; // Default to deployer
    }

    /**
     * @dev List an NFT for rental
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to list
     * @param pricePerSecond Price per second in wei
     * @param minDuration Minimum rental duration in seconds
     * @param maxDuration Maximum rental duration in seconds
     * @param collateralRequired Collateral amount required from renter
     */
    function listForRental(
        address nftContract,
        uint256 tokenId,
        uint256 pricePerSecond,
        uint256 minDuration,
        uint256 maxDuration,
        uint256 collateralRequired
    ) external nonReentrant whenNotPaused {
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not token owner");
        require(IERC721(nftContract).isApprovedForAll(msg.sender, address(this)), "Contract not approved");
        require(pricePerSecond > 0, "Price must be greater than 0");
        require(minDuration >= MIN_RENTAL_DURATION, "Duration too short");
        require(maxDuration <= MAX_RENTAL_DURATION, "Duration too long");
        require(minDuration <= maxDuration, "Invalid duration range");

        bytes32 listingId = keccak256(abi.encodePacked(nftContract, tokenId, msg.sender, block.timestamp));
        
        listings[listingId] = RentalListing({
            nftContract: nftContract,
            tokenId: tokenId,
            owner: msg.sender,
            pricePerSecond: pricePerSecond,
            minRentalDuration: minDuration,
            maxRentalDuration: maxDuration,
            collateralRequired: collateralRequired,
            active: true
        });

        ownerListings[msg.sender].push(uint256(listingId));

        emit RentalListed(listingId, nftContract, tokenId, msg.sender, pricePerSecond);
    }

    /**
     * @dev Rent an NFT for a specified duration
     * @param listingId The listing ID to rent
     * @param duration Duration in seconds
     */
    function rentNFT(
        bytes32 listingId,
        uint256 duration
    ) external payable nonReentrant whenNotPaused {
        RentalListing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(duration >= listing.minRentalDuration, "Duration too short");
        require(duration <= listing.maxRentalDuration, "Duration too long");
        
        uint256 totalCost = listing.pricePerSecond * duration;
        uint256 platformFee = totalCost * platformFeePercentage / 10000;
        uint256 ownerPayment = totalCost - platformFee;
        
        // Use DAO-controlled collateral multiplier
        uint256 requiredCollateral = listing.collateralRequired * collateralMultiplier;
        
        require(msg.value >= totalCost + requiredCollateral, "Insufficient payment");
        
        // Check if user has sufficient collateral balance or reputation
        if (reputationContract != address(0)) {
            // Reduce collateral based on reputation (simplified)
            requiredCollateral = requiredCollateral / 2;
        }
        
        require(
            userCollateralBalance[msg.sender] + msg.value >= requiredCollateral,
            "Insufficient collateral"
        );

        uint256 rentalId = nextRentalId++;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;

        rentals[rentalId] = Rental({
            nftContract: listing.nftContract,
            tokenId: listing.tokenId,
            owner: listing.owner,
            renter: msg.sender,
            pricePerSecond: listing.pricePerSecond,
            startTime: startTime,
            endTime: endTime,
            collateralAmount: listing.collateralRequired,
            active: true,
            completed: false
        });

        userRentals[msg.sender].push(rentalId);

        // Set user for ERC-4907 compatible NFTs
        if (supportsInterface(listing.nftContract, type(IERC4907).interfaceId)) {
            IERC4907(listing.nftContract).setUser(listing.tokenId, msg.sender, uint64(endTime));
        }

        // Transfer payment to owner
        payable(listing.owner).transfer(ownerPayment);
        
        // Send platform fee to fee recipient
        if (platformFee > 0 && feeRecipient != address(0)) {
            (bool feeSuccess, ) = payable(feeRecipient).call{value: platformFee}("");
            require(feeSuccess, "Fee transfer failed");
        }
        
        // Store collateral
        userCollateralBalance[msg.sender] = userCollateralBalance[msg.sender] + requiredCollateral;

        // Deactivate listing temporarily
        listing.active = false;

        emit RentalCreated(rentalId, listing.nftContract, listing.tokenId, listing.owner, msg.sender, duration, totalCost);
    }

    /**
     * @dev Complete a rental and handle collateral return
     * @param rentalId The rental ID to complete
     */
    function completeRental(uint256 rentalId) external nonReentrant {
        Rental storage rental = rentals[rentalId];
        require(rental.active, "Rental not active");
        require(block.timestamp >= rental.endTime, "Rental not expired");
        require(msg.sender == rental.renter || msg.sender == rental.owner, "Not authorized");

        rental.active = false;
        rental.completed = true;

        // Return collateral to renter
        if (rental.collateralAmount > 0) {
            userCollateralBalance[rental.renter] = userCollateralBalance[rental.renter] - rental.collateralAmount;
            payable(rental.renter).transfer(rental.collateralAmount);
        }

        // Clear user for ERC-4907 compatible NFTs
        if (supportsInterface(rental.nftContract, type(IERC4907).interfaceId)) {
            IERC4907(rental.nftContract).setUser(rental.tokenId, address(0), 0);
        }

        // Record utility usage for analytics
        if (utilityTrackerContract != address(0)) {
            uint256 duration = rental.endTime - rental.startTime;
            uint256 utilityValue = rental.pricePerSecond * duration; // Use payment as utility value proxy
            
            // Call utility tracker to record usage (simplified - assumes utility type 0 for gaming)
            (bool success, ) = utilityTrackerContract.call(
                abi.encodeWithSignature(
                    "recordUtilityUsage(address,uint256,address,uint256,uint256,uint256,uint256)",
                    rental.nftContract,
                    rental.tokenId,
                    rental.renter,
                    rental.startTime,
                    rental.endTime,
                    0, // Gaming utility type
                    utilityValue
                )
            );
            // Continue even if utility tracking fails
            success; // Silence unused variable warning
        }

        // Reactivate listing
        bytes32 listingId = keccak256(abi.encodePacked(rental.nftContract, rental.tokenId, rental.owner));
        if (listings[listingId].owner == rental.owner) {
            listings[listingId].active = true;
        }

        emit RentalCompleted(rentalId, rental.renter, true);
    }

    /**
     * @dev Deposit collateral for future rentals
     */
    function depositCollateral() external payable {
        require(msg.value > 0, "Must deposit some amount");
        userCollateralBalance[msg.sender] = userCollateralBalance[msg.sender] + msg.value;
        emit CollateralDeposited(msg.sender, msg.value);
    }

    /**
     * @dev Withdraw available collateral
     * @param amount Amount to withdraw
     */
    function withdrawCollateral(uint256 amount) external nonReentrant {
        require(userCollateralBalance[msg.sender] >= amount, "Insufficient balance");
        userCollateralBalance[msg.sender] = userCollateralBalance[msg.sender] - amount;
        payable(msg.sender).transfer(amount);
        emit CollateralWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Get rental details
     * @param rentalId The rental ID
     * @return Rental struct
     */
    function getRental(uint256 rentalId) external view returns (Rental memory) {
        return rentals[rentalId];
    }

    /**
     * @dev Get listing details
     * @param listingId The listing ID
     * @return RentalListing struct
     */
    function getListing(bytes32 listingId) external view returns (RentalListing memory) {
        return listings[listingId];
    }

    /**
     * @dev Check if a contract supports an interface
     * @param contractAddr Contract address to check
     * @param interfaceId Interface ID to check
     * @return True if supported
     */
    function supportsInterface(address contractAddr, bytes4 interfaceId) internal view returns (bool) {
        try IERC165(contractAddr).supportsInterface(interfaceId) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }

    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause function
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Update platform fee
     * @param newFeePercentage New fee percentage (in basis points)
     */
    function updatePlatformFee(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 1000, "Fee too high"); // Max 10%
        platformFeePercentage = newFeePercentage;
    }

    /**
     * @dev Withdraw platform fees
     */
    function withdrawPlatformFees() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev Get utility-based pricing recommendation for an NFT
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID
     * @param basePrice Base price per second
     * @return Recommended price per second based on utility analytics
     */
    function getUtilityBasedPrice(
        address nftContract,
        uint256 tokenId,
        uint256 basePrice
    ) external view returns (uint256) {
        if (utilityTrackerContract == address(0)) {
            return basePrice;
        }
        
        (bool success, bytes memory data) = utilityTrackerContract.staticcall(
            abi.encodeWithSignature(
                "getUtilityBasedPrice(address,uint256,uint256)",
                nftContract,
                tokenId,
                basePrice
            )
        );
        
        if (success && data.length > 0) {
            return abi.decode(data, (uint256));
        }
        
        return basePrice;
    }

    /**
     * @dev Check if an NFT has high utility demand
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID
     * @return True if NFT has high utility demand
     */
    function hasHighUtilityDemand(address nftContract, uint256 tokenId) external view returns (bool) {
        if (utilityTrackerContract == address(0)) {
            return false;
        }
        
        (bool success, bytes memory data) = utilityTrackerContract.staticcall(
            abi.encodeWithSignature(
                "hasHighUtilityDemand(address,uint256)",
                nftContract,
                tokenId
            )
        );
        
        if (success && data.length > 0) {
            return abi.decode(data, (bool));
        }
        
        return false;
    }
    
    // --- DAO Governance Functions ---
    
    /**
     * @dev Modifier to restrict functions to DAO only
     */
    modifier onlyDAO() {
        require(msg.sender == daoContract, "Only DAO can call this function");
        _;
    }
    
    /**
     * @notice Set DAO contract address (only callable by owner initially)
     * @param newDAO Address of the new DAO contract
     */
    function setDAOContract(address newDAO) external onlyOwner {
        require(newDAO != address(0), "Invalid DAO address");
        daoContract = newDAO;
        emit DAOContractUpdated(newDAO);
    }
    
    /**
     * @notice Set fee parameters (only callable by DAO)
     * @param newFeePercentage New fee percentage in basis points
     * @param newFeeRecipient Address to receive fees
     */
    function setFeeParameters(uint256 newFeePercentage, address newFeeRecipient) external onlyDAO {
        require(newFeePercentage <= 1000, "Fee too high"); // Max 10%
        require(newFeeRecipient != address(0), "Invalid fee recipient");
        platformFeePercentage = newFeePercentage;
        feeRecipient = newFeeRecipient;
    }
    
    /**
     * @notice Set collateral multiplier (only callable by DAO)
     * @param newMultiplier New collateral multiplier
     */
    function setCollateralMultiplier(uint256 newMultiplier) external onlyDAO {
        require(newMultiplier >= 1 && newMultiplier <= 10, "Invalid multiplier");
        collateralMultiplier = newMultiplier;
    }
    
    /**
     * @notice Generic parameter setting function for DAO
     * @param key Parameter key
     * @param value Parameter value
     */
    function setParameter(string calldata key, bytes calldata value) external onlyDAO {
        // Implementation would depend on specific parameters needed
        // This allows for flexible governance of various contract parameters
        emit ParameterUpdated(key, value);
    }
    
    /**
     * @notice Update platform fee (legacy function for backward compatibility)
     * @param newFeePercentage New fee percentage (in basis points)
     */
    function updatePlatformFee(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 1000, "Fee too high"); // Max 10%
        platformFeePercentage = newFeePercentage;
    }
    
    /**
     * @notice Set fee recipient (only callable by owner)
     * @param newFeeRecipient New fee recipient address
     */
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = newFeeRecipient;
    }
}

