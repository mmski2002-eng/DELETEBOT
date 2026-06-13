# 🔴 07 — Неатомарная покупка с жетонами (Jetton) — CRITICAL

**Файл:** `nft-fixprice-sale-v4r1.fc:63-95, 428-468`  
**CWE:** CWE-362 (Race Condition via Async Messages) + CWE-252 (Unchecked Return Value)

## Суть

При покупке NFT за жетоны (Jetton) контракт выполняет **4 последовательные операции** без двухфазного коммита:
1. `send_jettons(owner_wallet, user_amount)` — жетоны продавцу
2. `send_jettons(fee_wallet, fee_amount)` — комиссия маркетплейсу
3. `send_jettons(royalty_wallet, royalty_amount)` — роялти автору
4. `transfer_nft(nft_address, buyer)` — перевод NFT покупателю

Каждый вызов `send_jettons` отправляет сообщение с `nobounce` (`0x10`), а `transfer_nft` — с флагом `130` (`SEND_MODE_CARRY_ALL_REMAINING_BALANCE + SEND_MODE_IGNORE_ERRORS`). Если любой из этих шагов не удастся, деньги уже ушли, а NFT может не дойти.

## Цепочка атаки

```
Покупатель → JettonTransfer(price) → Sale Contract
  → send_jettons(owner, user)                      [успех]
  → send_jettons(fee_addr, fee)                    [успех]
  → send_jettons(royalty_addr, royalty)             [успех]
  → transfer_nft(nft_addr, buyer)                  [FAIL — Bounced]
  → save_data(is_complete=1)
  → Строка 172: if (flags & 1) { return (); }      [ИГНОР]
```

## Ущерб

Полная стоимость NFT в жетонах + комиссии.