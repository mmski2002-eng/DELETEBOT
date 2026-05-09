# NFTFlow — Результаты проверки активного mainnet-использования

## Итог: Активное mainnet-использование НЕ ПОДТВЕРЖДЕНО

**Формат вывода B: No confirmed Critical/High**

---

## Active contracts checked

| Контракт | Адрес | Статус на Shannon Explorer |
|----------|-------|---------------------------|
| NFTFlow (marketplace) | `0x59b670e9fA9D0A427751Af201D676719a970857b` | **Не найден** — `is_contract: false`, нет creation tx, нет transactions |
| NFTFlow (ERC-20 token) | `0x4F055A58f075c04Ea9dDc39Ec45f7cEDaf8C6C81` | **Это ERC-20 токен, НЕ marketplace**. Единственная транзакция — деплой 2025-03-13. Ноль активных вызовов. |
| PaymentStream | `0x68B1D87F95878fE05B998F19b66F4baba5De1aed` | **Не развёрнут** — `is_contract: false`, нет данных |
| ReputationSystem | `0x3Aa5ebB10DC797CAC828524e59A333d0A371443c` | **Не развёрнут** — `is_contract: false`, нет данных |
| Main contract (из README) | `0x20956722fF53760c0e7cB3B03B7c22e03d0228b3` | **Не контракт** — `is_contract: false`, нет creation tx |

## Functions tested

Не применимо — ни один production-контракт NFTFlow не обнаружен на Somnia mainnet.

## Hypotheses tested

1. **NFTFlow marketplace развёрнут и активен на Somnia mainnet** — **Опровергнуто**. Адреса из README не существуют как контракты на Shannon Explorer API. Единственный контракт с именем NFTFlow (`0x4F...C81`) — тривиальный ERC-20 токен (mint/burn/transfer), не имеющий отношения к аренде NFT.

2. **Контракты работают на Somnia Testnet (Shannon) с chainId 50312** — **Подтверждено частично**. Hardhat-конфиг содержит исключительно сеть `somniaTestnet` (chainId 50312). README явно утверждает: *«All contracts are deployed on the Somnia Testnet (Shannon)»*.

3. **Существует mainnet-развёртывание** — **Опровергнуто**. Нет конфигурации mainnet в hardhat.config.js. Нет упоминания mainnet в документации. Нет транзакций на адресах предполагаемых контрактов.

## Why each failed

- **Все адреса из README** либо не существуют как контракты, либо не содержат логики аренды NFT.
- Единственный deployed контракт `0x4F...C81` — ERC-20 токен с ровно 1 транзакцией за всю историю (деплой), без вызовов методов аренды, листинга, escrow.
- Shannon Explorer (`shannon-explorer.somnia.network`) — это **testnet explorer**, не mainnet.

## Missing data

- Адреса контрактов NFTFlow на Somnia **mainnet** (если mainnet вообще запущен)
- RPC URL Somnia mainnet
- Chain ID Somnia mainnet
- Любые транзакции/events аренды NFT на mainnet
- Verified source code контрактов на mainnet explorer
- Активные rental listings, escrow-счета, payment token-ы