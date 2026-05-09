// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title ArbitrageRouter
/// @notice Store proposals of bundled calls for arbitrage, execute atomically, verify profit, distribute proceeds.
///
/// Security model:
/// - Proposer deposits a bond (native or ERC20) to propose (spam prevention)
/// - Executor (multisig/operator) calls executeProposal. Contract runs stored calls, measures profit in profitToken,
///   enforces profit >= minProfit, distributes shares to proposer & treasury, returns bond.
/// - Atomic: if any call fails or profit check fails, revert and bond remains (optionally returned by admin).
///
/// NOTE: For production always use a timelock + multisig executor. This contract is designed for hackathon/dev use
/// with best-effort safety patterns.
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ArbitrageRouter is ReentrancyGuard {
    struct Call {
        address target;
        uint256 value; // native value to send
        bytes data;
    }

    struct Proposal {
        address proposer;
        uint256 bondAmount;
        address bondToken; // address(0) for native
        Call[] calls;
        address profitToken; // address(0) for native profit measurement
        uint256 minProfit; // in profitToken / native units
        uint256 proposerShareBps;
        uint256 treasuryShareBps;
        address treasury;
        bool executed;
        uint256 createdAt;
    }

    mapping(uint256 => Proposal) private proposals;
    uint256 public proposalCount;

    event ProposalCreated(uint256 indexed id, address indexed proposer, address profitToken, uint256 minProfit);
    event ProposalExecuted(uint256 indexed id, address indexed executor, uint256 profit);
    event ProposalFailed(uint256 indexed id, address indexed executor, string reason);
    event ProposalCancelled(uint256 indexed id, address indexed admin);

    uint256 public constant BPS_DENOM = 10_000;

    address public admin;

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin");
        _;
    }

    constructor(address _admin) {
        require(_admin != address(0), "admin zero");
        admin = _admin;
    }

    /// @notice proposeArbitrage bundles many calls to be executed atomically later
    /// @dev if bondToken==address(0), proposer must send msg.value == bondAmount
    function proposeArbitrage(
        address bondToken,
        uint256 bondAmount,
        address profitToken,
        uint256 minProfit,
        uint256 proposerShareBps,
        uint256 treasuryShareBps,
        address treasury,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external payable returns (uint256 id) {
        require(targets.length == values.length && values.length == datas.length, "len mismatch");
        require(proposerShareBps + treasuryShareBps <= BPS_DENOM, "invalid shares");
        require(treasury != address(0), "treasury zero");

        // handle bond deposit
        if (bondToken == address(0)) {
            require(msg.value == bondAmount, "bond mismatch");
        } else {
            require(msg.value == 0, "no native expected");
            require(IERC20(bondToken).transferFrom(msg.sender, address(this), bondAmount), "bond transfer failed");
        }

        id = ++proposalCount;
        Proposal storage p = proposals[id];
        p.proposer = msg.sender;
        p.bondAmount = bondAmount;
        p.bondToken = bondToken;
        p.profitToken = profitToken;
        p.minProfit = minProfit;
        p.proposerShareBps = proposerShareBps;
        p.treasuryShareBps = treasuryShareBps;
        p.treasury = treasury;
        p.executed = false;
        p.createdAt = block.timestamp;

        // persist calls
        for (uint256 i = 0; i < targets.length; i++) {
            p.calls.push(Call({ target: targets[i], value: values[i], data: datas[i] }));
        }

        emit ProposalCreated(id, msg.sender, profitToken, minProfit);
    }

    // getter for calls length
    function getCallsLen(uint256 id) external view returns (uint256) {
        return proposals[id].calls.length;
    }

    function getCall(uint256 id, uint256 idx) external view returns (address target, uint256 value, bytes memory data) {
        Call storage c = proposals[id].calls[idx];
        return (c.target, c.value, c.data);
    }

    /// @notice executeProposal runs calls, ensures profit >= minProfit and distributes shares
    function executeProposal(uint256 id) external nonReentrant returns (uint256 profit) {
        Proposal storage p = proposals[id];
        require(p.proposer != address(0), "no proposal");
        require(!p.executed, "already executed");

        // pre-balance for profit token
        uint256 preBalance = _balanceOf(p.profitToken, address(this));

        // execute all calls sequentially
        for (uint256 i = 0; i < p.calls.length; i++) {
            Call storage c = p.calls[i];
            (bool ok, bytes memory ret) = c.target.call{ value: c.value }(c.data);
            if (!ok) {
                // bubble error message if available
                string memory reason = _getRevertMsg(ret);
                emit ProposalFailed(id, msg.sender, reason);
                revert(reason);
            }
        }

        // post-balance
        uint256 postBalance = _balanceOf(p.profitToken, address(this));

        // profit = post - pre (handle underflow)
        if (postBalance <= preBalance) {
            emit ProposalFailed(id, msg.sender, "no profit");
            revert("no profit");
        }
        profit = postBalance - preBalance;

        require(profit >= p.minProfit, "profit too low");

        // compute distributions
        uint256 proposerShare = (profit * p.proposerShareBps) / BPS_DENOM;
        uint256 treasuryShare = (profit * p.treasuryShareBps) / BPS_DENOM;
        uint256 remainder = profit - proposerShare - treasuryShare;

        // For safety: send shares
        if (p.profitToken == address(0)) {
            // native transfers
            _sendNative(p.proposer, proposerShare);
            _sendNative(p.treasury, treasuryShare);
            // remainder stays in contract (or can be sent to admin treasury) - send to admin
            if (remainder > 0) _sendNative(admin, remainder);
        } else {
            IERC20 token = IERC20(p.profitToken);
            require(token.transfer(p.proposer, proposerShare), "transfer proposer failed");
            require(token.transfer(p.treasury, treasuryShare), "transfer treasury failed");
            if (remainder > 0) require(token.transfer(admin, remainder), "transfer admin remainder failed");
        }

        // return bond to proposer
        if (p.bondAmount > 0) {
            if (p.bondToken == address(0)) {
                _sendNative(p.proposer, p.bondAmount);
            } else {
                require(IERC20(p.bondToken).transfer(p.proposer, p.bondAmount), "return bond failed");
            }
        }

        p.executed = true;
        emit ProposalExecuted(id, msg.sender, profit);
    }

    /// @notice admin can cancel a proposal and refund bond (emergency)
    function adminCancelProposal(uint256 id) external onlyAdmin nonReentrant {
        Proposal storage p = proposals[id];
        require(p.proposer != address(0), "no proposal");
        require(!p.executed, "already executed");

        // refund bond
        if (p.bondAmount > 0) {
            if (p.bondToken == address(0)) {
                _sendNative(p.proposer, p.bondAmount);
            } else {
                require(IERC20(p.bondToken).transfer(p.proposer, p.bondAmount), "refund bond failed");
            }
        }

        // delete calls to free storage
        delete proposals[id];
        emit ProposalCancelled(id, msg.sender);
    }

    // -------- utilities --------
    function _balanceOf(address token, address who) internal view returns (uint256) {
        if (token == address(0)) {
            return who.balance;
        } else {
            return IERC20(token).balanceOf(who);
        }
    }

    function _sendNative(address to, uint256 amount) internal {
        (bool ok, ) = to.call{ value: amount }("");
        require(ok, "native send failed");
    }

    // decode revert reason from returned data
    function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) return "call failed";
        assembly {
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string));
    }

    // allow contract to receive native
    receive() external payable {}
}
