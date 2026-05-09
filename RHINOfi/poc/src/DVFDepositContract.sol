// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./BridgeVM.sol";

/**
 * PoC SUT (System Under Test) — точная копия оригинального DVFDepositContract
 * Исходник: https://github.com/rhinofi/contracts_public/blob/main/bridge-deposit/DVFDepositContract.sol
 */
contract DVFDepositContract is OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  mapping(address => bool) public authorized;
  mapping(string => bool) public processedWithdrawalIds;
  bool public depositsDisallowed;
  mapping(address => int) public maxDepositAmount;
  BridgeVM private vm;

  modifier _isAuthorized() {
    require(authorized[msg.sender], "UNAUTHORIZED");
    _;
  }

  modifier _areDepositsAllowed() {
    require(!depositsDisallowed, "DEPOSITS_NOT_ALLOWED");
    _;
  }

  event BridgedDeposit(address indexed user, address indexed token, uint256 amount);
  event BridgedDepositWithId(address sender, address origin, address token, uint256 amount, uint256 commitmentId);
  event BridgedWithdrawal(address user, address token, uint256 amount, string withdrawalId);
  event BridgedWithdrawalWithNative(address user, address token, uint256 amountToken, uint256 amountNative);
  event BridgedWithdrawalWithData(address token, uint256 amountToken, uint256 amountNative, bytes ref);

  function initialize() public virtual initializer {
    __Ownable_init();
    authorized[_msgSender()] = true;
    createVMContract();
  }

  function createVMContract() public returns (address) {
    require(address(vm) == address(0), 'VM_ALREADY_DEPLOYED');
    vm = new BridgeVM();
    return address(vm);
  }

  function checkMaxDepositAmount(address token, uint256 amount) public view {
    int maxDeposit = maxDepositAmount[token];
    require(maxDeposit >= 0, "DEPOSITS_NOT_ALLOWED");
    if(maxDeposit == 0) { return; }
    require(amount <= uint(maxDeposit), "DEPOSIT_EXCEEDS_MAX");
  }

  function deposit(address token, uint256 amount) external _areDepositsAllowed {
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
    checkMaxDepositAmount(token, amount);
    require(token != address(0), 'BLACKHOLE_NOT_ALLOWED');
    emit BridgedDeposit(msg.sender, token, amount);
  }

  // ⚠️ Finding #7: НЕТ модификатора _areDepositsAllowed
  function depositWithId(address token, uint256 amount, uint256 commitmentId) public {
    require(token != address(0), 'BLACKHOLE_NOT_ALLOWED');
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
    emit BridgedDepositWithId(msg.sender, tx.origin, token, amount, commitmentId);
  }

  // ⚠️ Finding #3: permit отправляется на цепь с подписью
  function depositWithPermit(address token, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s, uint256 commitmentId) external {
    IERC20PermitUpgradeable(token).permit(msg.sender, address(this), amount, deadline, v, r, s);
    depositWithId(token, amount, commitmentId);
  }

  function depositNative() external payable _areDepositsAllowed {
    checkMaxDepositAmount(address(0), msg.value);
    emit BridgedDeposit(msg.sender, address(0), msg.value);
  }

  // ⚠️ Finding #7: НЕТ модификатора _areDepositsAllowed
  function depositNativeWithId(uint256 commitmentId) external payable {
    emit BridgedDepositWithId(msg.sender, tx.origin, address(0), msg.value, commitmentId);
  }

  function addFunds(address token, uint256 amount) external _isAuthorized {
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
  }

  function addFundsNative() external payable _isAuthorized { }

  function withdrawV2(address token, address to, uint256 amount) external _isAuthorized {
    IERC20Upgradeable(token).safeTransfer(to, amount);
    emit BridgedWithdrawal(to, token, amount, '');
  }

  // ⚠️ Finding #2: ETH переводится ДО ERC20 — нарушение CEI
  function withdrawV2WithNative(address token, address to, uint256 amountToken, uint256 amountNative) external _isAuthorized {
    (bool success,) = to.call{value: amountNative}("");
    require(success, "FAILED_TO_SEND_ETH");
    IERC20Upgradeable(token).safeTransfer(to, amountToken);
    emit BridgedWithdrawalWithNative(to, token, amountToken, amountNative);
  }

  function withdrawV2WithNativeNoEvent(address token, address to, uint256 amountToken, uint256 amountNative) external _isAuthorized {
    if(amountNative > 0) {
      (bool success,) = to.call{value: amountNative}("");
      require(success, "FAILED_TO_SEND_ETH");
    }
    if(amountToken > 0 && token != address(0)) {
      IERC20Upgradeable(token).safeTransfer(to, amountToken);
    }
  }

  function withdrawNativeV2(address payable to, uint256 amount) external _isAuthorized {
    (bool success,) = to.call{value: amount}("");
    require(success, "FAILED_TO_SEND_ETH");
    emit BridgedWithdrawal(to, address(0), amount, '');
  }

  function _withdrawWithData(address token, uint256 amount, uint256 amountNative, BridgeVM.Call[] calldata datas) internal {
    require(address(vm) != address(0), 'VM_DOES_NOT_EXIST');
    if (address(token) != address(0)) {
      IERC20Upgradeable(token).safeTransfer(address(vm), amount);
    }
    vm.execute{value: amountNative}(datas);
  }

  function withdrawWithData(address token, uint256 amount, uint256 amountNative, BridgeVM.Call[] calldata datas, bytes calldata ref) external _isAuthorized {
    _withdrawWithData(token, amount, amountNative, datas);
    emit BridgedWithdrawalWithData(token, amount, amountNative, ref);
  }

  function withdrawWithDataNoEvent(address token, uint256 amount, uint256 amountNative, BridgeVM.Call[] calldata datas) external _isAuthorized {
    _withdrawWithData(token, amount, amountNative, datas);
  }

  function removeFunds(address token, address to, uint256 amount) external _isAuthorized {
    IERC20Upgradeable(token).safeTransfer(to, amount);
  }

  // ⚠️ Finding #1: НЕТ проверки возвращаемого значения .call{value}
  function removeFundsNative(address payable to, uint256 amount) public _isAuthorized {
    require(address(this).balance >= amount, "INSUFFICIENT_BALANCE");
    to.call{value: amount}("");
  }

  function authorize(address user, bool value) external onlyOwner {
    authorized[user] = value;
  }

  function authorizeMulti(address[] calldata users, bool value) external onlyOwner {
    for (uint256 i = 0; i < users.length; i++) {
      authorized[users[i]] = value;
    }
  }

  // ⚠️ Finding #6: НЕТ проверки address(0)
  function transferOwner(address newOwner) external onlyOwner {
    require(newOwner != owner(), "SAME_OWNER");
    authorized[newOwner] = true;
    authorized[owner()] = false;
    transferOwnership(newOwner);
  }

  function renounceOwnership() public view override onlyOwner {
    require(false, "Unable to renounce ownership");
  }

  function allowDepositsGlobal(bool value) external _isAuthorized {
    depositsDisallowed = !value;
  }

  function allowDeposits(address tokenAddress, int256 maxAmount) external _isAuthorized {
    maxDepositAmount[tokenAddress] = maxAmount;
  }

  function withdrawVmFunds(address token) external {
    require(address(vm) != address(0), 'VM_DOES_NOT_EXIST');
    vm.withdrawVmFunds(token);
  }

  receive() external payable { }
}
