дтвердить уязвимость. Ты# 🔴 01 — Потеря NFT при Bounced Message (CRITICAL)

**Файл:** `nft-fixprice-sale-v4r1.fc:172, 397-427`  
**CWE:** CWE-252 (Unchecked Return Value) + CWE-362

## Суть

При покупке NFT контракт отправляет 4 сообщения подряд:
1. `send_money(owner)` — деньги продавцу
2. `send_money(fee_address)` — комиссия маркетплейсу
3. `send_money(royalty_address)` — роялти автору
4. `transfer_nft(nft_address)` — перевод NFT покупателю

После отправки ВСЕХ сообщений устанавливается `is_complete = 1`. Если `transfer_nft` вернёт bounced (NFT-контракт отклонил трансфер), контракт **игнорирует** его (`if (flags & 1) { return (); }`), не откатывая `is_complete` и не возвращая средства.

**Результат:** Деньги ушли, NFT не получен, продажа считается завершённой.

## Цепочка атаки

```
Покупатель → msg_value(price+gas) → Sale Contract
  → send_money(owner, price-fee-royalty)      [успех]
  → send_money(fee_addr, fee)                  [успех]
  → send_money(royalty_addr, royalty)           [успех]
  → transfer_nft(nft_addr, buyer)              [BOUNCED]
  → save_data(is_complete=1)
  → Bounced приходит → if (flags & 1) { return (); }  ← ПОЛНЫЙ ИГНОР
```

## Ущерб

Полная стоимость NFT + комиссии — **без上限а**.