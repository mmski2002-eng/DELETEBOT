// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title ReputationSystem
 * @dev On-chain reputation and review system for NFTFlow
 * @notice Manages user reviews, ratings, and reputation scores
 */
contract ReputationSystem is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    
    // Structs
    struct Review {
        address reviewer;
        address reviewee;
        uint8 rating; // 1-5 stars
        string comment;
        uint256 timestamp;
        bytes32 rentalId;
        bool verified;
        ReviewType reviewType;
    }
    
    struct ReputationData {
        uint256 totalScore;
        uint256 reviewCount;
        uint256 rentalCount;
        uint256 successfulRentals;
        uint256 disputeCount;
        uint256 lastUpdated;
        uint256 streak;
        uint256 maxStreak;
    }
    
    enum ReviewType {
        RENTER_TO_LENDER,
        LENDER_TO_RENTER,
        MUTUAL
    }
    
    // State variables
    mapping(address => ReputationData) public reputationData;
    mapping(address => Review[]) public userReviews;
    mapping(bytes32 => Review) public reviews;
    mapping(bytes32 => bool) public reviewExists;
    mapping(address => mapping(address => mapping(bytes32 => bool))) public hasReviewed;
    
    Counters.Counter private _reviewIdCounter;
    
    // Configuration
    uint256 public constant MAX_RATING = 5;
    uint256 public constant MIN_RATING = 1;
    uint256 public constant REPUTATION_DECAY_PERIOD = 30 days;
    uint256 public constant STREAK_BONUS_THRESHOLD = 5;
    
    // Events
    event ReviewSubmitted(
        bytes32 indexed reviewId,
        address indexed reviewer,
        address indexed reviewee,
        uint8 rating,
        bytes32 rentalId,
        ReviewType reviewType
    );
    
    event ReputationUpdated(
        address indexed user,
        uint256 newScore,
        uint256 reviewCount,
        uint256 streak
    );
    
    event ReviewDisputed(
        bytes32 indexed reviewId,
        address indexed disputer,
        string reason
    );
    
    event ReviewVerified(
        bytes32 indexed reviewId,
        address indexed verifier
    );
    
    // Modifiers
    modifier validRating(uint8 rating) {
        require(rating >= MIN_RATING && rating <= MAX_RATING, "Invalid rating");
        _;
    }
    
    modifier notSelfReview(address reviewee) {
        require(msg.sender != reviewee, "Cannot review yourself");
        _;
    }
    
    modifier rentalCompleted(bytes32 rentalId) {
        // In a real implementation, this would check with the rental contract
        // For now, we'll assume the rental is completed
        _;
    }
    
    /**
     * @dev Submit a review for a completed rental
     * @param reviewee Address of the user being reviewed
     * @param rating Rating from 1-5 stars
     * @param comment Review comment
     * @param rentalId ID of the completed rental
     * @param reviewType Type of review (renter to lender, lender to renter, or mutual)
     */
    function submitReview(
        address reviewee,
        uint8 rating,
        string calldata comment,
        bytes32 rentalId,
        ReviewType reviewType
    ) external 
        nonReentrant 
        validRating(rating) 
        notSelfReview(reviewee)
        rentalCompleted(rentalId)
    {
        require(!hasReviewed[msg.sender][reviewee][rentalId], "Already reviewed");
        require(bytes(comment).length <= 500, "Comment too long");
        
        _reviewIdCounter.increment();
        bytes32 reviewId = keccak256(abi.encodePacked(
            msg.sender,
            reviewee,
            rentalId,
            _reviewIdCounter.current()
        ));
        
        reviews[reviewId] = Review({
            reviewer: msg.sender,
            reviewee: reviewee,
            rating: rating,
            comment: comment,
            timestamp: block.timestamp,
            rentalId: rentalId,
            verified: false,
            reviewType: reviewType
        });
        
        reviewExists[reviewId] = true;
        hasReviewed[msg.sender][reviewee][rentalId] = true;
        
        // Add to user reviews
        userReviews[reviewee].push(reviews[reviewId]);
        
        // Update reputation
        _updateReputation(reviewee, rating);
        
        emit ReviewSubmitted(reviewId, msg.sender, reviewee, rating, rentalId, reviewType);
    }
    
    /**
     * @dev Update user reputation based on new review
     * @param user User address
     * @param rating New rating received
     */
    function _updateReputation(address user, uint8 rating) internal {
        ReputationData storage data = reputationData[user];
        
        // Calculate new total score
        uint256 newTotalScore = data.totalScore + (rating * 20); // Convert to 0-100 scale
        uint256 newReviewCount = data.reviewCount + 1;
        
        // Calculate new average reputation score
        uint256 newReputationScore = newTotalScore / newReviewCount;
        
        // Update streak
        if (rating >= 4) {
            data.streak += 1;
            if (data.streak > data.maxStreak) {
                data.maxStreak = data.streak;
            }
        } else {
            data.streak = 0;
        }
        
        // Update data
        data.totalScore = newTotalScore;
        data.reviewCount = newReviewCount;
        data.lastUpdated = block.timestamp;
        
        emit ReputationUpdated(user, newReputationScore, newReviewCount, data.streak);
    }
    
    /**
     * @dev Update rental statistics
     * @param user User address
     * @param successful Whether the rental was successful
     * @param disputed Whether there was a dispute
     */
    function updateRentalStats(
        address user,
        bool successful,
        bool disputed
    ) external onlyOwner {
        ReputationData storage data = reputationData[user];
        
        data.rentalCount += 1;
        
        if (successful) {
            data.successfulRentals += 1;
        }
        
        if (disputed) {
            data.disputeCount += 1;
            // Reduce reputation for disputes
            if (data.totalScore > 100) {
                data.totalScore -= 100;
            }
        }
        
        data.lastUpdated = block.timestamp;
    }
    
    /**
     * @dev Get reputation score for a user
     * @param user User address
     * @return score Reputation score (0-100)
     */
    function getReputationScore(address user) external view returns (uint256) {
        ReputationData memory data = reputationData[user];
        
        if (data.reviewCount == 0) {
            return 50; // Default score for new users
        }
        
        return data.totalScore / data.reviewCount;
    }
    
    /**
     * @dev Get detailed reputation data
     * @param user User address
     * @return data Reputation data struct
     */
    function getReputationData(address user) external view returns (ReputationData memory) {
        return reputationData[user];
    }
    
    /**
     * @dev Get reviews for a user
     * @param user User address
     * @param limit Maximum number of reviews to return
     * @param offset Starting index
     * @return reviews Array of reviews
     */
    function getUserReviews(
        address user,
        uint256 limit,
        uint256 offset
    ) external view returns (Review[] memory) {
        Review[] memory allReviews = userReviews[user];
        uint256 totalReviews = allReviews.length;
        
        if (offset >= totalReviews) {
            return new Review[](0);
        }
        
        uint256 endIndex = offset + limit;
        if (endIndex > totalReviews) {
            endIndex = totalReviews;
        }
        
        uint256 resultLength = endIndex - offset;
        Review[] memory result = new Review[](resultLength);
        
        for (uint256 i = 0; i < resultLength; i++) {
            result[i] = allReviews[totalReviews - 1 - offset - i]; // Most recent first
        }
        
        return result;
    }
    
    /**
     * @dev Get a specific review
     * @param reviewId Review ID
     * @return review Review data
     */
    function getReview(bytes32 reviewId) external view returns (Review memory) {
        require(reviewExists[reviewId], "Review does not exist");
        return reviews[reviewId];
    }
    
    /**
     * @dev Verify a review (only owner)
     * @param reviewId Review ID to verify
     */
    function verifyReview(bytes32 reviewId) external onlyOwner {
        require(reviewExists[reviewId], "Review does not exist");
        require(!reviews[reviewId].verified, "Review already verified");
        
        reviews[reviewId].verified = true;
        
        emit ReviewVerified(reviewId, msg.sender);
    }
    
    /**
     * @dev Dispute a review
     * @param reviewId Review ID to dispute
     * @param reason Reason for dispute
     */
    function disputeReview(bytes32 reviewId, string calldata reason) external {
        require(reviewExists[reviewId], "Review does not exist");
        require(
            msg.sender == reviews[reviewId].reviewer || 
            msg.sender == reviews[reviewId].reviewee,
            "Not authorized to dispute this review"
        );
        
        emit ReviewDisputed(reviewId, msg.sender, reason);
    }
    
    /**
     * @dev Calculate reputation tier
     * @param user User address
     * @return tier Tier level (1-5)
     */
    function getReputationTier(address user) external view returns (uint256) {
        ReputationData memory data = reputationData[user];
        
        if (data.reviewCount == 0) {
            return 1; // New user tier
        }
        
        uint256 score = data.totalScore / data.reviewCount;
        
        if (score >= 90) return 5; // Excellent
        if (score >= 80) return 4; // Very Good
        if (score >= 70) return 3; // Good
        if (score >= 60) return 2; // Fair
        return 1; // Poor
    }
    
    /**
     * @dev Get reputation tier name
     * @param user User address
     * @return tierName Tier name
     */
    function getReputationTierName(address user) external view returns (string memory) {
        uint256 tier = this.getReputationTier(user);
        
        if (tier == 5) return "Excellent";
        if (tier == 4) return "Very Good";
        if (tier == 3) return "Good";
        if (tier == 2) return "Fair";
        return "New User";
    }
    
    /**
     * @dev Check if user can review
     * @param reviewer Reviewer address
     * @param reviewee Reviewee address
     * @param rentalId Rental ID
     * @return canReview True if can review
     */
    function canReview(
        address reviewer,
        address reviewee,
        bytes32 rentalId
    ) external view returns (bool) {
        return !hasReviewed[reviewer][reviewee][rentalId] && reviewer != reviewee;
    }
    
    /**
     * @dev Get review statistics
     * @param user User address
     * @return stats Review statistics
     */
    function getReviewStats(address user) external view returns (
        uint256 totalReviews,
        uint256 averageRating,
        uint256 fiveStarReviews,
        uint256 fourStarReviews,
        uint256 threeStarReviews,
        uint256 twoStarReviews,
        uint256 oneStarReviews
    ) {
        Review[] memory reviews = userReviews[user];
        totalReviews = reviews.length;
        
        if (totalReviews == 0) {
            return (0, 0, 0, 0, 0, 0, 0);
        }
        
        uint256 totalRating = 0;
        
        for (uint256 i = 0; i < totalReviews; i++) {
            uint8 rating = reviews[i].rating;
            totalRating += rating;
            
            if (rating == 5) fiveStarReviews++;
            else if (rating == 4) fourStarReviews++;
            else if (rating == 3) threeStarReviews++;
            else if (rating == 2) twoStarReviews++;
            else if (rating == 1) oneStarReviews++;
        }
        
        averageRating = totalRating / totalReviews;
    }
    
    /**
     * @dev Get contract version
     * @return version string
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
