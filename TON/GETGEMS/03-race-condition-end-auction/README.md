# 🟠 03 — Гонка состояний end_auction / repeat_end_auction (HIGH)

**Файл:** `nft-auction.func:~300-420`  
**CWE:** CWE-362 (Concurrent Execution using Shared Resource with Improper Synchronization)

## Суть

Аукционный контракт использует два отдельных сообщения для завершения аукциона: `end_auction` (завершение + перевод NFT) и `repeat_end_auction` (повторная попытка). Между ними нет атомарной блокировки. Атакующий может отправить `end_auction` параллельно с `repeat_end_auction`, создав гонку состояний, где оба сообщения читают `end_time` до того, как одно из них обновит `is_complete`.

## Цепочка атаки

```
Время аукциона истекло.
  → end_auction отправлено (msg1)
  → repeat_end_auction отправлено параллельно (msg2)

msg1: проверяет now() >= end_time → OK, send NFT → save_data(is_complete=1)
msg2: проверяет now() >= end_time → OK (уже прочитано до save_data msg1) → send NFT повторно

Итог: двойной перевод NFT или двойная выплата.
```

## Ущерб

Двойная выплата победителю аукциона, потеря NFT.