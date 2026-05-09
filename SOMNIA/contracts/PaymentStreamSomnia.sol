// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title PaymentStreamSomnia
 * @dev Optimized payment streaming contract for Somnia's high throughput and low fees
 * Leverages Somnia's 1M+ TPS, sub-second finality, and sub-cent transaction costs
 */
contract PaymentStreamSomnia is ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    
    // Leverage Somnia's low storage costs for detailed tracking
    struct Stream {
        address payer;           // 20 bytes
        address payee;           // 20 bytes
        uint40 startTime;       // 5 bytes - Optimized for Somnia's fast blocks
        uint40 endTime;         // 5 bytes - Optimized for Somnia's fast blocks
        uint96 totalAmount;     // 12 bytes - Optimized for micro-payments
        uint96 releasedAmount;  // 12 bytes - Track released funds
        uint40 lastReleaseTime; // 5 bytes - Last release timestamp
        bool isActive;          // 1 byte
        uint8 streamType;       // 1 byte - Rental, Subscription, etc.
    }
    
    mapping(address => Stream) public streams;
    mapping(address => uint256) public userStreamCount;
    mapping(address => uint256) public totalStreamedAmount;
    
    uint256 public totalStreams;
    uint256 public totalVolume;
    
    // Somnia-optimized constants
    uint256 public constant MIN_STREAM_AMOUNT = 0.000001 ether; // Minimum viable stream
    uint256 public constant MAX_STREAM_DURATION = 31536000; // 1 year maximum
    uint256 public constant MIN_STREAM_DURATION = 60; // 1 minute minimum
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 250; // 2.5%
    
    address public protocolFeeRecipient;
    
    // Events for real-time monitoring on Somnia's high TPS network
    event StreamCreated(
        address indexed streamId,
        address indexed payer,
        address indexed payee,
        uint256 totalAmount,
        uint256 startTime,
        uint256 endTime,
        uint8 streamType
    );
    
    event FundsReleased(
        address indexed streamId,
        uint256 amount,
        uint256 timestamp,
        uint256 totalReleased
    );
    
    event StreamCancelled(
        address indexed streamId,
        uint256 refundAmount,
        uint256 reason
    );
    
    event StreamCompleted(
        address indexed streamId,
        uint256 finalAmount
    );
    
    constructor() Ownable() {
        protocolFeeRecipient = msg.sender;
    }
    
    /**
     * @dev Create payment stream utilizing Somnia's low fees for micro-payments
     */
    function createStream(
        address payee,
        uint256 duration,
        uint8 streamType
    ) external payable nonReentrant returns (address) {
        require(msg.value >= MIN_STREAM_AMOUNT, "Stream amount too small");
        require(duration >= MIN_STREAM_DURATION, "Duration too short");
        require(duration <= MAX_STREAM_DURATION, "Duration too long");
        require(payee != address(0), "Invalid payee");
        require(payee != msg.sender, "Cannot stream to self");
        require(streamType > 0 && streamType <= 10, "Invalid stream type");
        
        // Generate stream ID using Somnia's fast computation
        address streamId = generateStreamId(msg.sender, payee, duration);
        
        require(streams[streamId].totalAmount == 0, "Stream already exists");
        
        streams[streamId] = Stream({
            payer: msg.sender,
            payee: payee,
            startTime: uint40(block.timestamp),
            endTime: uint40(block.timestamp + duration),
            totalAmount: uint96(msg.value),
            releasedAmount: 0,
            lastReleaseTime: uint40(block.timestamp),
            isActive: true,
            streamType: streamType
        });
        
        totalStreams++;
        totalVolume += msg.value;
        userStreamCount[msg.sender]++;
        
        emit StreamCreated(
            streamId,
            msg.sender,
            payee,
            msg.value,
            block.timestamp,
            block.timestamp + duration,
            streamType
        );
        
        return streamId;
    }
    
    /**
     * @dev Release funds leveraging Somnia's high TPS for real-time payment releases
     */
    function releaseFunds(address streamId) external nonReentrant {
        Stream storage stream = streams[streamId];
        require(stream.isActive, "Stream not active");
        require(block.timestamp >= stream.startTime, "Stream not started");
        
        uint256 releasable = calculateReleasable(streamId);
        require(releasable > 0, "No funds to release");
        
        stream.releasedAmount += uint96(releasable);
        stream.lastReleaseTime = uint40(block.timestamp);
        
        // Calculate protocol fee
        uint256 protocolFee = releasable.mul(PROTOCOL_FEE_PERCENTAGE).div(10000);
        uint256 payeeAmount = releasable.sub(protocolFee);
        
        // Use Somnia's low fees for instant transfers
        if (payeeAmount > 0) {
            (bool success, ) = payable(stream.payee).call{value: payeeAmount}("");
            require(success, "Transfer failed");
        }
        
        if (protocolFee > 0) {
            (bool success, ) = payable(protocolFeeRecipient).call{value: protocolFee}("");
            require(success, "Protocol fee transfer failed");
        }
        
        totalStreamedAmount[stream.payee] += payeeAmount;
        
        emit FundsReleased(streamId, releasable, block.timestamp, stream.releasedAmount);
        
        // Check if stream is completed
        if (stream.releasedAmount >= stream.totalAmount) {
            stream.isActive = false;
            emit StreamCompleted(streamId, stream.totalAmount);
        }
    }
    
    /**
     * @dev Cancel stream with instant refund leveraging Somnia's low fees
     */
    function cancelStream(address streamId, uint256 reason) external nonReentrant {
        Stream storage stream = streams[streamId];
        require(stream.isActive, "Stream not active");
        require(msg.sender == stream.payer || msg.sender == owner(), "Not authorized");
        
        stream.isActive = false;
        
        uint256 totalDuration = stream.endTime - stream.startTime;
        uint256 elapsedTime = block.timestamp - stream.startTime;
        
        // Cap elapsed time to end time
        if (elapsedTime > totalDuration) {
            elapsedTime = totalDuration;
        }
        
        uint256 releasedAmount = (stream.totalAmount * elapsedTime) / totalDuration;
        uint256 refundAmount = stream.totalAmount - releasedAmount;
        
        if (refundAmount > 0) {
            (bool success, ) = payable(stream.payer).call{value: refundAmount}("");
            require(success, "Refund failed");
        }
        
        emit StreamCancelled(streamId, refundAmount, reason);
    }
    
    /**
     * @dev Optimized calculation leveraging Somnia's fast block times
     */
    function calculateReleasable(address streamId) public view returns (uint256) {
        Stream memory stream = streams[streamId];
        if (!stream.isActive) return 0;
        
        uint256 currentTime = block.timestamp;
        if (currentTime <= stream.startTime) return 0;
        if (currentTime >= stream.endTime) return stream.totalAmount - stream.releasedAmount;
        
        uint256 streamDuration = stream.endTime - stream.startTime;
        uint256 elapsedTime = currentTime - stream.startTime;
        
        uint256 totalReleasable = (stream.totalAmount * elapsedTime) / streamDuration;
        return totalReleasable - stream.releasedAmount;
    }
    
    /**
     * @dev Get stream information optimized for Somnia's fast reads
     */
    function getStreamInfo(address streamId) external view returns (
        address payer,
        address payee,
        uint256 startTime,
        uint256 endTime,
        uint256 totalAmount,
        uint256 releasedAmount,
        uint256 releasableAmount,
        bool isActive,
        uint8 streamType
    ) {
        Stream memory stream = streams[streamId];
        uint256 releasable = calculateReleasable(streamId);
        return (
            stream.payer,
            stream.payee,
            stream.startTime,
            stream.endTime,
            stream.totalAmount,
            stream.releasedAmount,
            releasable,
            stream.isActive,
            stream.streamType
        );
    }
    
    /**
     * @dev Get user stream statistics leveraging Somnia's high throughput
     */
    function getUserStreamStats(address user) external view returns (
        uint256 streamCount,
        uint256 totalStreamed,
        uint256 activeStreams
    ) {
        streamCount = userStreamCount[user];
        totalStreamed = totalStreamedAmount[user];
        
        // This would need to iterate through streams to count active ones
        // For gas optimization, we'll return 0 for now
        activeStreams = 0;
    }
    
    /**
     * @dev Generate deterministic stream ID using Somnia's fast computation
     */
    function generateStreamId(
        address payer,
        address payee,
        uint256 duration
    ) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            payer,
            payee,
            duration,
            block.timestamp,
            totalStreams
        )))));
    }
    
    /**
     * @dev Batch release funds for multiple streams leveraging Somnia's high TPS
     */
    function batchReleaseFunds(address[] calldata streamIds) external nonReentrant {
        require(streamIds.length <= 50, "Too many streams"); // Gas limit protection
        
        for (uint256 i = 0; i < streamIds.length; i++) {
            address streamId = streamIds[i];
            Stream storage stream = streams[streamId];
            
            if (stream.isActive && block.timestamp >= stream.startTime) {
                uint256 releasable = calculateReleasable(streamId);
                
                if (releasable > 0) {
                    stream.releasedAmount += uint96(releasable);
                    stream.lastReleaseTime = uint40(block.timestamp);
                    
                    // Calculate protocol fee
                    uint256 protocolFee = releasable.mul(PROTOCOL_FEE_PERCENTAGE).div(10000);
                    uint256 payeeAmount = releasable.sub(protocolFee);
                    
                    // Transfer funds
                    if (payeeAmount > 0) {
                        (bool success, ) = payable(stream.payee).call{value: payeeAmount}("");
                        require(success, "Transfer failed");
                    }
                    
                    if (protocolFee > 0) {
                        (bool success, ) = payable(protocolFeeRecipient).call{value: protocolFee}("");
                        require(success, "Protocol fee transfer failed");
                    }
                    
                    totalStreamedAmount[stream.payee] += payeeAmount;
                    
                    emit FundsReleased(streamId, releasable, block.timestamp, stream.releasedAmount);
                    
                    // Check if stream is completed
                    if (stream.releasedAmount >= stream.totalAmount) {
                        stream.isActive = false;
                        emit StreamCompleted(streamId, stream.totalAmount);
                    }
                }
            }
        }
    }
    
    /**
     * @dev Set protocol fee recipient leveraging Somnia's governance capabilities
     */
    function setProtocolFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid recipient");
        protocolFeeRecipient = newRecipient;
    }
    
    /**
     * @dev Emergency withdraw leveraging Somnia's low fees for admin operations
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
    
    /**
     * @dev Get global statistics leveraging Somnia's high throughput
     */
    function getGlobalStats() external view returns (
        uint256 totalStreamsCount,
        uint256 totalVolumeAmount,
        uint256 activeStreamsCount
    ) {
        return (totalStreams, totalVolume, 0); // activeStreamsCount would need iteration
    }
}
