#!/usr/bin/env python3
"""
Pharos Atlantic Testnet — Live PoP Validation PoC
=================================================
Проверяет в тестовой сети Atlantic (chain ID 688689):

  1. Контракт принимает произвольные PoP (read-only — запрос getValidator)
  2. Key squatting — первый регистрант захватывает poolId
  3. Активация валидатора с произвольным PoP

Запуск:
    pip install web3
    python live_pop_poc.py

⚠ Read-only режим — только запросы к контракту, без отправки транзакций.
  Для полного PoC нужен funded testnet аккаунт.
"""

from web3 import Web3
from eth_account import Account
from typing import Optional
import hashlib
import secrets

# ── Конфигурация ─────────────────────────────────────────────────────────────

# RPC Atlantic testnet
RPC_URL = "http://atlantic.dplabs-internal.com:18100"  # замените на ваш RPC

# Адреса системных контрактов
STAKING_ADDRESS = "0x4100000000000000000000000000000000000000"
CHAIN_CONFIG_ADDRESS = "0x3100000000000000000000000000000000000000"

# ABI фрагменты для staking
STAKING_ABI = [
    {
        "inputs": [{"internalType": "bytes32", "name": "_poolId", "type": "bytes32"}],
        "name": "getValidator",
        "outputs": [{
            "components": [
                {"internalType": "string", "name": "description"},
                {"internalType": "string", "name": "publicKey"},
                {"internalType": "string", "name": "publicKeyPop"},
                {"internalType": "string", "name": "blsPublicKey"},
                {"internalType": "string", "name": "blsPublicKeyPop"},
                {"internalType": "string", "name": "endpoint"},
                {"internalType": "uint8", "name": "status"},
                {"internalType": "bytes32", "name": "poolId"},
                {"internalType": "uint256", "name": "totalStake"},
                {"internalType": "address", "name": "owner"},
                {"internalType": "uint256", "name": "stakeSnapshot"},
                {"internalType": "uint256", "name": "pendingWithdrawStake"},
                {"internalType": "uint8", "name": "pendingWithdrawWindow"},
                {"internalType": "address", "name": "pendingOwner"}
            ],
            "internalType": "struct IStaking.Validator",
            "name": "validator",
            "type": "tuple"
        }],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "getActiveValidators",
        "outputs": [{"internalType": "bytes32[]", "name": "", "type": "bytes32[]"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "getAllValidators",
        "outputs": [{"internalType": "bytes32[]", "name": "poolIds", "type": "bytes32[]"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "getValidatorCounts",
        "outputs": [
            {"internalType": "uint256", "name": "activeCount", "type": "uint256"},
            {"internalType": "uint256", "name": "inactiveCount", "type": "uint256"},
            {"internalType": "uint256", "name": "pendingExitCount", "type": "uint256"}
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "bytes32", "name": "_poolId", "type": "bytes32"}],
        "name": "isValidatorActive",
        "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "bytes32", "name": "_poolId", "type": "bytes32"}],
        "name": "isValidatorPendingAdd",
        "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "string", "name": "_description", "type": "string"},
            {"internalType": "string", "name": "_publicKey", "type": "string"},
            {"internalType": "string", "name": "_proofOfPossession", "type": "string"},
            {"internalType": "string", "name": "_blsPublicKey", "type": "string"},
            {"internalType": "string", "name": "_blsProofOfPossession", "type": "string"},
            {"internalType": "string", "name": "_endpoint", "type": "string"}
        ],
        "name": "registerValidator",
        "outputs": [{"internalType": "bytes32", "name": "", "type": "bytes32"}],
        "stateMutability": "payable",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "getBlockchainInfo",
        "outputs": [
            {"internalType": "uint256", "name": "currentEpoch_", "type": "uint256"},
            {"internalType": "uint256", "name": "currentBlock_", "type": "uint256"},
            {"internalType": "uint256", "name": "totalStake_", "type": "uint256"}
        ],
        "stateMutability": "view",
        "type": "function"
    }
]


def compute_pool_id(public_key_hex: str) -> bytes:
    """Вычисляет poolId = sha256(publicKeyBytes)"""
    pk = public_key_hex
    if pk.startswith("0x"):
        pk = pk[2:]
    # Strip prefix like 1003, 4003, etc.
    if pk.startswith("1003"):
        pk = pk[4:]
    elif pk.startswith("4003"):
        pk = pk[4:]
    elif pk.startswith("4002"):
        pk = pk[4:]
    
    pk_bytes = bytes.fromhex(pk)
    return hashlib.sha256(pk_bytes).digest()


def main():
    print("=" * 70)
    print("Pharos Atlantic Testnet — Live PoP Validation PoC")
    print("=" * 70)
    
    # Подключаемся к RPC
    try:
        w3 = Web3(Web3.HTTPProvider(RPC_URL))
        chain_id = w3.eth.chain_id
        print(f"\n✅ Подключено к {RPC_URL}")
        print(f"   Chain ID: {chain_id} (0x{chain_id:x})")
        print(f"   Block:    {w3.eth.block_number}")
    except Exception as e:
        print(f"\n❌ Не удалось подключиться к RPC: {e}")
        print("   Убедитесь, что нода запущена и RPC endpoint доступен.")
        return
    
    # Создаём контракт
    staking = w3.eth.contract(
        address=Web3.to_checksum_address(STAKING_ADDRESS),
        abi=STAKING_ABI
    )
    
    # ═══════════════════════════════════════════════════════════════
    # ЧАСТЬ 0: Базовая информация о контракте
    # ═══════════════════════════════════════════════════════════════
    print("\n" + "=" * 70)
    print("ЧАСТЬ 0 — Информация о стейкинг-контракте")
    print("=" * 70)
    
    try:
        counts = staking.functions.getValidatorCounts().call()
        print(f"\n   Активных валидаторов:    {counts[0]}")
        print(f"   В pending добавлении:     {counts[1]}")
        print(f"   В pending выходе:         {counts[2]}")
    except Exception as e:
        print(f"\n   ❌ getValidatorCounts() failed: {e}")
    
    try:
        info = staking.functions.getBlockchainInfo().call()
        print(f"\n   Текущая эпоха:    {info[0]}")
        print(f"   Текущий блок:     {info[1]}")
        print(f"   Общий стейк:      {w3.from_wei(info[2], 'ether')} PHAROS")
    except Exception as e:
        print(f"\n   ❌ getBlockchainInfo() failed: {e}")
    
    # ═══════════════════════════════════════════════════════════════
    # ЧАСТЬ 1: Проверка PoP существующих валидаторов (read-only)
    # ═══════════════════════════════════════════════════════════════
    print("\n" + "=" * 70)
    print("ЧАСТЬ 1 — Проверка PoP существующих валидаторов")
    print("=" * 70)
    
    try:
        all_validators = staking.functions.getAllValidators().call()
        print(f"\n   Всего валидаторов: {len(all_validators)}")
        
        checked = 0
        for pool_id in all_validators:
            if checked >= 3:  # Проверяем первые 3
                break
            
            val = staking.functions.getValidator(pool_id).call()
            pop = val[2]  # publicKeyPop
            bls_pop = val[4]  # blsPublicKeyPop
            
            print(f"\n   ── Валидатор #{checked + 1} ──")
            print(f"      poolId:            0x{pool_id.hex()}")
            print(f"      owner:             {val[9]}")
            print(f"      status:            {val[6]}")
            print(f"      publicKeyPop:      {pop}")
            print(f"      blsPublicKeyPop:   {bls_pop}")
            
            if pop in ("0x00", "0x", ""):
                print(f"      ⚠  PoP = '{pop}' — произвольное/пустое значение!")
            if bls_pop in ("0x00", "0x", ""):
                print(f"      ⚠  BLS PoP = '{bls_pop}' — произвольное/пустое значение!")
            
            checked += 1
            
    except Exception as e:
        print(f"\n   ❌ Не удалось получить валидаторов: {e}")
    
    # ═══════════════════════════════════════════════════════════════
    # ЧАСТЬ 2: Симуляция key squatting (read-only, расчёт poolId)
    # ═══════════════════════════════════════════════════════════════
    print("\n" + "=" * 70)
    print("ЧАСТЬ 2 — Симуляция key squatting")
    print("=" * 70)
    
    # Генерируем случайный публичный ключ (как если бы это был ключ жертвы)
    dummy_pubkey = "0x1003" + secrets.token_hex(32)
    pool_id = compute_pool_id(dummy_pubkey)
    
    print(f"\n   Сгенерирован публичный ключ (жертва):")
    print(f"      public_key: {dummy_pubkey[:50]}...")
    print(f"      poolId:     0x{pool_id.hex()}")
    
    # Проверяем, не занят ли уже этот poolId
    try:
        val = staking.functions.getValidator(pool_id).call()
        if val[6] == 0 and val[8] == 0 and val[9] == "0x0000000000000000000000000000000000000000":
            print(f"   ✅ poolId свободен — можно зарегистрировать")
            print(f"   ⚠  Для полного PoC нужно отправить транзакцию:")
            print(f"      1. Создать аккаунт с тестовыми PHAROS")
            print(f"      2. Вызвать registerValidator с PoP='0x00'")
            print(f"      3. Проверить, что первый регистрант стал owner")
            print(f"      4. Попробовать зарегистрировать тот же ключ с другого адреса")
        else:
            print(f"   ⚠  poolId уже занят (owner={val[9]})")
    except Exception as e:
        print(f"   ❌ Ошибка: {e}")
    
    # ═══════════════════════════════════════════════════════════════
    # ИТОГ
    # ═══════════════════════════════════════════════════════════════
    print("\n" + "=" * 70)
    print("РЕЗУЛЬТАТ")
    print("=" * 70)
    
    print("""
  ✅ ЛОКАЛЬНО ПОДТВЕРЖДЕНО (Foundry тесты):
     • registerValidator() принимает произвольные PoP
     • Первый регистрант захватывает poolId
     • Валидатор с произвольным PoP становится active

  📋 ЧТО МОЖНО ПРОВЕРИТЬ В TESTNET (с запущенной нодой):
     • Часть 1: Read-only — проверить PoP существующих валидаторов
     • Часть 2: Key squatting — зарегистрировать ключ с PoP="0x00"
     • Часть 3: Активация — дождаться advanceEpoch и проверить статус

  🔑 ДЛЯ ПОЛНОГО PoC НУЖНО:
     • Запустить локальную ноду Atlantic testnet (docker-compose)
     • Иметь funded аккаунт с тестовыми PHAROS для газа и стейка
     • Или найти публичный RPC тестовой сети
    """)


if __name__ == "__main__":
    main()
