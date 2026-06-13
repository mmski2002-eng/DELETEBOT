# Testnet Verification Checklist

## Goal

Verify whether a Fragment/Telemint signed deploy payload is:

- a public bearer authorization (`telemint_msg_deploy` without sender binding), or
- a sender-bound authorization (`telemint_msg_deploy_v2` with `force_sender_address`).

## What to capture

For each wallet, save the raw TonConnect request as JSON:

```json
{
  "validUntil": 1234567890,
  "messages": [
    {
      "address": "EQ...",
      "amount": "1000000000",
      "payload": "te6cc..."
    }
  ]
}
```

Suggested filenames:

- `wallet-a.json`
- `wallet-b.json`

## Decode one payload

```bash
npm run inspect -- decode wallet-a.json
```

What matters most in the output:

- `decoded.op_name`
- `decoded.restrictions.force_sender_address`
- `decoded.sender_binding_present`
- `decoded.token_name`
- `decoded.auction_config`

## Compare wallet A vs wallet B

```bash
npm run inspect -- compare wallet-a.json wallet-b.json
```

Interpretation:

- `payload_equal: true` plus `sender_binding_*: null` is a strong vulnerable signal.
- `same_signature: true` plus no sender binding is also suspicious even if outer JSON differs.
- `sender_binding_a` equal to wallet A means the flow is likely sender-bound.

## Safe replay test

Only use your own wallets and a low-value testnet flow.

1. Capture payload for wallet A.
2. Do not broadcast from wallet A yet.
3. Send the exact same `address + amount + payload` from wallet B.
4. Observe whether wallet B transaction is accepted.
5. If accepted, inspect whether the created item records wallet B as first bidder or owner.
6. Then try wallet A and confirm whether the same acquisition path is no longer available.

## Evidence to keep

- Raw `wallet-a.json`
- Raw `wallet-b.json`
- Output of `decode`
- Output of `compare`
- Destination collection address
- Result of wallet B replay attempt
- Result of wallet A follow-up attempt
