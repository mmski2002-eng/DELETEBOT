Security Candidate Report: Signed first-bid deploy is not bound to bidder address
Severity

Conditional Critical

Critical only if the real Fragment flow uses signed deploys as user-specific authorization, reserved purchase, fixed-price purchase, buy-now, or instant-finalization sale.

If signed deploys are intentionally public bearer authorizations for open auctions, severity is likely lower: MEV/front-running of first bid, not asset theft.

Summary

The base Telemint NftCollection verifies a signed deploy command, but the signed payload does not include the intended bidder/sender address.

After signature verification, the contract uses the actual inbound sender_address as the first bidder:

deploy_item(sender_address, msg_value, item_code, cmd, full_domain, default_royalty_params)

This means anyone who obtains a valid signed deploy payload before it is used can submit the same payload from another wallet. The collection will accept the signature and create the item with the attacker’s wallet as first bidder.

If the payload corresponds to a user-specific, reserved, fixed-price, buy-now, or instantly-finalized sale, this can allow unauthorized acquisition of the asset.

Affected code

Repository:

https://github.com/TelegramMessenger/telemint

Likely affected contract:

func/nft-collection.fc

Relevant flow:

() recv_internal(int msg_value, cell in_msg_full, slice in_msg_body) impure {
  ...
  slice sender_address = cs~load_msg_addr();
  ...
  cell cmd = unwrap_signed_cmd(in_msg_body, public_key);
  ...
  deploy_item(sender_address, msg_value, item_code, cmd, full_domain, default_royalty_params);
}

The deploy uses the runtime sender_address, not a signed intended bidder.

Relevant TL-B:

telemint_unsigned_deploy

Expected issue:

telemint_unsigned_deploy does not contain bidder address / sender address / intended recipient.

Important contrast:

NftCollectionNoDns / v2 has restrictions, including force_sender_address / rewrite_sender_address.
Base NftCollection does not.

This difference is important because v2 appears to contain a mitigation for sender binding, while the base collection does not.

Security invariant

Expected invariant for user-specific signed deploys:

A signed deploy issued for user/wallet A must not be usable by wallet B.

Observed invariant in base NftCollection:

Any wallet that submits a valid signed deploy first becomes the first bidder.
Attack hypothesis
Scenario
1. Victim wallet A receives a signed deploy payload from Fragment backend.
2. The signed payload authorizes creation/first bid/purchase of asset X.
3. Attacker obtains the payload:
   - from pending transaction body,
   - compromised frontend,
   - shared TonConnect request,
   - browser/network capture,
   - relay/mempool observation.
4. Attacker submits the same payload from wallet B with sufficient value.
5. Base NftCollection verifies the signature.
6. Base NftCollection deploys the NftItem with sender_address = wallet B.
7. Wallet B becomes first bidder or final owner.
8. Victim wallet A’s later transaction cannot create/acquire the same item.
Critical impact condition

This becomes Critical if any real Fragment flow satisfies at least one of:

- signed deploy is issued to a specific wallet/user;
- asset is reserved for a specific user;
- signed deploy is used for direct purchase / fixed-price sale;
- signed deploy is used for buy-now;
- auction can finalize immediately via max_bid or zero/near-zero duration;
- first transaction wins ownership, not merely first bid position.
What agent must verify
Goal

Determine whether real Fragment signed deploy payloads are:

A. user-specific and sender-bound, or
B. public bearer payloads usable by any sender.

And determine whether any such flow is:

A. open auction only, or
B. buy-now / fixed-price / instant-finalization / reserved acquisition.
Verification plan
Step 1 — Capture real Fragment transaction payload

Use a browser with DevTools.

Open Fragment.
Connect wallet A.
Start a flow that creates a transaction:
first bid on username;
buy-now / purchase if available;
start auction / reserved claim if available.
Do not broadcast yet if possible.
Capture TonConnect transaction request.

Look for fields like:

{
  "validUntil": "...",
  "messages": [
    {
      "address": "...",
      "amount": "...",
      "payload": "..."
    }
  ]
}

Save:

destination address
amount/value
payload BOC/base64
asset name/id
wallet A address
timestamp
Fragment page/action
Step 2 — Repeat with wallet B

Repeat the same flow with another wallet.

Save the same fields:

destination address
amount/value
payload BOC/base64
asset name/id
wallet B address
timestamp
Fragment page/action
Step 3 — Compare payloads

Compare wallet A and wallet B payloads.

Strong vulnerable signal
payload_A == payload_B

or

payloads differ only in outer TonConnect metadata, not in signed deploy body

This suggests the signed deploy is a bearer authorization.

Strong mitigation signal

Payload contains sender-binding restrictions such as:

force_sender_address = wallet A
rewrite_sender_address = wallet A
intended_sender = wallet A

or payload differs because wallet address is inside the signed data.

Step 4 — Decode the payload

The agent should decode the payload BOC and identify whether it is base deploy or v2 deploy.

Expected vulnerable form

Base deploy:

telemint_msg_deploy#4637289a
  sig:bits512
  msg:TelemintUnsignedDeploy

TelemintUnsignedDeploy should include roughly:

subwallet_id
valid_since
valid_till
token_name
content
auction_config
royalty_params

But should not include:

sender address
bidder address
wallet address
recipient address
force_sender_address
rewrite_sender_address
restrictions
Expected safer form

v2 / NoDNS deploy:

telemint_msg_deploy_v2
  ...
  restrictions:(Maybe ^TelemintRestrictions)

Look for:

force_sender_address
rewrite_sender_address

If force_sender_address is present and equals wallet A, then wallet B should not be able to use wallet A’s payload.

Step 5 — Check destination contract type

Confirm whether transaction destination is:

Base NftCollection

or:

NftCollectionNoDns / v2 / another protected collection

Important:

If destination is base NftCollection and payload is base telemint_unsigned_deploy, candidate remains live.
If destination is NoDNS/v2 and force_sender_address is enforced, candidate likely not exploitable for that flow.
Step 6 — Safe replay test with own wallets

Only do this with your own wallets and a low-value/non-sensitive flow.

Test
1. Wallet A obtains signed deploy payload.
2. Do not submit wallet A transaction.
3. Wallet B sends the exact same destination + payload with sufficient value.
4. Observe whether transaction succeeds.
5. If it succeeds, inspect created NftItem state:
   - first bidder should be wallet B;
   - owner may be wallet B if instant-finalized.
6. Then submit wallet A transaction.
7. Observe expected result:
   - wallet A cannot create same item;
   - wallet A receives refund/return path or transaction fails/bounces.
Pass/fail criteria
Vulnerability primitive confirmed if:
Payload issued while using wallet A is accepted from wallet B.
Critical confirmed if additionally:
Wallet B becomes owner of the asset,
or Wallet B acquires a reserved/fixed-price/buy-now asset intended for wallet A.
Not Critical if:
Wallet B only becomes first bidder in a public open auction,
and anyone was allowed to bid anyway.
Step 7 — Check auction config for instant finalization

Decode auction config and look for:

max_bid > 0
first_bid_value >= max_bid
duration = 0
end_time <= now
min_extend_time = 0
fixed sale price
buy-now value

Critical path:

new_bid >= max_bid

In NftItem.process_new_bid, this causes:

if ((max_bid > 0) & (new_bid >= max_bid)) {
  new_end_time = 0;
}

Then maybe_end_auction can assign ownership to the bidder.

Agent should verify whether the captured Fragment payload can cause:

first sender of signed deploy becomes final owner in same transaction or immediately after public finalization.
Expected findings matrix
Result	Interpretation
Payload A works from wallet B, open auction only	Valid front-running primitive, probably Medium/High depending on market impact
Payload A works from wallet B, fixed-price/buy-now/reserved asset	Critical
Payload contains force_sender_address = wallet A and wallet B tx fails	Mitigated
Payload uses v2 restrictions but force_sender_address absent	Still suspicious
Payload differs per wallet but no address binding visible	Investigate hidden nonce/session binding; may still be bearer
Payload is base telemint_unsigned_deploy and identical for both wallets	Strong vulnerable signal
Evidence to collect

For report-quality evidence, save:

1. Raw payload issued to wallet A.
2. Wallet A address.
3. Raw payload issued to wallet B for same asset/action.
4. Diff of decoded payloads.
5. Destination collection address.
6. Proof destination bytecode matches base NftCollection or vulnerable variant.
7. Wallet B transaction using wallet A payload.
8. Resulting NftItem state showing bidder/owner = wallet B.
9. If buy-now/reserved: UI/backend proof that asset/action was intended for wallet A.
10. Wallet A follow-up transaction result showing it cannot acquire same asset.
Minimal PoC description
PoC:
1. Authenticate/connect to Fragment as wallet A.
2. Request transaction for asset X.
3. Extract TonConnect message payload.
4. Submit the same message from wallet B before wallet A submits it.
5. Observe that the collection accepts the signed payload.
6. Observe that deployed NftItem records wallet B as first bidder/final owner.
7. If asset was user-specific/fixed-price/buy-now, wallet B acquired an asset using wallet A’s signed authorization.
Suggested report title
Signed first-bid deploy is not bound to bidder address and can be front-run by another wallet
Suggested impact wording
The signed deploy command acts as a bearer authorization. Since the signed data does not include the intended bidder address, any wallet that obtains the signed payload can submit it first and become the first bidder or owner. If Fragment uses this mechanism for user-specific, reserved, fixed-price, or buy-now flows, an attacker can steal the acquisition opportunity from the intended user.
Suggested fix

For all user-specific or fixed-price flows:

1. Include intended bidder address in the signed payload.
2. Verify intended bidder == actual sender_address in NftCollection.
3. Or migrate all such flows to v2 restrictions with force_sender_address.
4. Ensure signed payload includes domain/collection address/chain/subwallet/context to prevent cross-context replay.
5. Add a nonce/order id if payloads are intended to be one-time authorizations.
Agent focus

Do not spend time on:

- partial refund theory;
- storage reserve payout differences;
- max_bid overpayment UX;
- DNS mutation;
- generic external finalization.

Focus only on:

Can wallet B use wallet A’s signed deploy payload?
Can this lead to ownership or reserved/buy-now acquisition?
Is the real Fragment payload base deploy or v2 restricted deploy?