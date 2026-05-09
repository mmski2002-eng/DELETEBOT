# 🟠 02 — Невозврат ставки при mode=2 с недостаточным газом (HIGH)

**Файл:** `nft-auction.func:~230-260`  
**CWE:** CWE-252 (Unchecked Return Value)

## Суть

В аукционном контракте при получении новой ставки (`bid`) предыдущая ставка возвращается предыдущему лидеру через `send_raw_message(msg, 2)`. Флаг `mode=2` означает `SEND_MODE_IGNORE_ERRORS` — если сообщение вернуть не удастся, bounced **не генерируется**. Если предыдущему лидеру отправить средства не удалось (недостаточно газа, неверный адрес), его ставка **теряется навсегда**.

## Цепочка атаки

```
Bidder1 → bid(10 TON) → Auction
  save_data(current_bid=10, ...)

Bidder2 → bid(15 TON) → Auction
  → send_raw_message(Bidder1, 10 TON, mode=2)  [FAIL — mode=2, bounced не будет]
  → save_data(current_bid=15, ...)
```

## Ущерб

Ставка предыдущего лидера — до полной стоимости NFT.