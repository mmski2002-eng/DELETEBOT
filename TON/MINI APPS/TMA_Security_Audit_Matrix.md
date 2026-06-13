# Telegram Mini Apps Security Audit Matrix

## Scope and Triage Priority

This checklist is oriented toward Telegram Mini Apps (TMA) used in real bug bounty programs, with focus on web attack surface, authentication boundaries, wallet binding, and TON transaction trust.

### Highest-priority findings to hunt first

1. Missing or broken backend validation of `initData`
2. Backend trust in `window.Telegram.WebApp` / `initDataUnsafe`
3. Broken Telegram user to TON wallet binding
4. Client-side only payment or transaction verification
5. XSS through Telegram-controlled fields or `start_param`
6. Replay of auth or payment artifacts
7. Weak `postMessage` / iframe origin validation
8. Bot token exposure in frontend or public assets

---

## 1. `initData` Validation

### 1.1 Missing backend validation of `initData`

- Attack vector:
  Backend accepts Telegram identity claims from the client without verifying Telegram's signature.
- What to test:
  Send API requests with a forged `user.id`, `username`, or full fake `initData` object. Try direct API access without launching from Telegram.
- Reproduction ideas:
  Intercept the request from the TMA, replace `initData` or identity fields, replay to the backend, and observe whether the session is created or another user's data becomes accessible.
- Evidence of vulnerability:
  Server authenticates or registers a user even when `hash` is missing, invalid, stale, or fully attacker-controlled.
- Impact / severity:
  Usually `Critical` due to authentication bypass or account takeover.
- Vulnerable implementation:
  Backend trusts `user.id` from request JSON or `initDataUnsafe`.
- Safe implementation:
  Backend validates raw `initData` using Telegram's HMAC procedure, checks `auth_date`, and then issues its own session.

### 1.2 Incorrect HMAC-SHA256 validation logic

- Attack vector:
  Signature verification is implemented incorrectly, causing valid forgeries or verification bypass.
- What to test:
  Try shuffled field order, duplicate parameters, omitted parameters, modified URL encoding, modified nested `user` object, and stale `hash`.
- Reproduction ideas:
  Capture one valid `initData`, then mutate:
  `auth_date`, `query_id`, `user.id`, parameter order, URL encoding, duplicate keys, and presence of `hash`.
- Evidence of vulnerability:
  Server accepts malformed or modified `initData` that should fail verification.
- Impact / severity:
  `High` to `Critical`, depending on whether impersonation is possible.
- Common mistakes:
  Not sorting fields correctly, including `hash` in the checked string, validating parsed objects rather than raw input, using the wrong secret derivation, or skipping constant-time compare.
- Safe implementation:
  Canonicalize exactly as required by Telegram, compare computed and supplied `hash` in constant time, and reject malformed input.

### 1.3 Ignoring `auth_date` and replaying old `initData`

- Attack vector:
  Old but valid `initData` is accepted indefinitely.
- What to test:
  Replay a previously captured valid `initData` hours or days later. Try using it after logout or from another device / IP.
- Reproduction ideas:
  Save one successful login request and resend it later unchanged.
- Evidence of vulnerability:
  Backend accepts expired `initData` and creates a fresh authenticated session.
- Impact / severity:
  Usually `Medium` to `High`; can become `Critical` if it enables durable session theft or account takeover.
- Vulnerable implementation:
  Signature is checked, but freshness is not.
- Safe implementation:
  Enforce a narrow TTL, reject stale `auth_date`, and ideally bind login exchange to one-time server-side session setup.

### 1.4 Can `initData` be forged without the bot token?

- Security property:
  If validation is correct and the bot token is secret, forging `initData` should not be practical.
- What this means for testing:
  If forgery succeeds, look for one of these instead:
  broken validation, raw trust in client data, token leakage, or replay.
- Severity if token is exposed:
  `Critical`.

---

## 2. `window.Telegram.WebApp` Client Object

### 2.1 Trust in `initDataUnsafe` or client-side `user`

- Attack vector:
  App treats client-side Telegram object values as authoritative identity or authorization data.
- What to test:
  Override `window.Telegram.WebApp.initDataUnsafe.user.id`, `username`, `language_code`, `is_premium`, or related flags in DevTools and retry actions.
- Reproduction ideas:
  Monkey-patch values before a fetch/XHR or edit request payloads directly through the proxy.
- Evidence of vulnerability:
  Backend behavior changes based on attacker-modified client values.
- Impact / severity:
  `High` to `Critical` if it enables impersonation or privilege changes.
- Vulnerable implementation:
  API uses `user.id` from frontend payload to decide whose data to load.
- Safe implementation:
  Client sends raw `initData`; backend derives user identity itself after signature verification.

### 2.2 Username-based authorization or business logic

- Attack vector:
  App grants access, rewards, or admin behavior based on `username` rather than validated account identity.
- What to test:
  Change `username` client-side or find flows where only `username` appears in the request.
- Reproduction ideas:
  Attempt to impersonate a privileged user by editing `username`, or change a profile to match an allowlisted handle.
- Evidence of vulnerability:
  Role changes, account access, or resource exposure tied to username alone.
- Impact / severity:
  Usually `Medium` to `High`; can be `Critical` if admin access is affected.
- Safe implementation:
  Authorization must be bound to verified Telegram `id` plus server-managed roles.

### 2.3 `start_param` / `startapp` abuse

- Attack vector:
  Deep-link parameters drive sensitive behavior without validation.
- What to test:
  Feed arbitrary referral codes, tenant IDs, promo identifiers, feature switches, or URLs through Telegram start parameters.
- Reproduction ideas:
  Launch the app with crafted `startapp` / `start_param` values and monitor backend routing, rewards, or context selection.
- Evidence of vulnerability:
  Referral fraud, unauthorized tenant selection, hidden feature access, IDOR, or open redirect behavior.
- Impact / severity:
  Usually `Medium` to `High`.
- Vulnerable implementation:
  Start parameter is used directly as a trusted key or URL.
- Safe implementation:
  Treat it as untrusted input, validate against a strict schema, and bind sensitive actions to server-side state.

---

## 3. TON Connect (`@tonconnect/ui`, `@tonconnect/sdk`)

### 3.1 Wallet address spoofing during binding

- Attack vector:
  Backend records a wallet address supplied by the client without cryptographic proof that the user controls it.
- What to test:
  Modify the wallet address in requests during or after connection. Try binding someone else's address to your Telegram account.
- Reproduction ideas:
  Intercept wallet-linking calls and replace the submitted address with an arbitrary one.
- Evidence of vulnerability:
  Wallet binding succeeds without a signed challenge from the wallet.
- Impact / severity:
  `High` to `Critical`, depending on what wallet ownership enables.
- Vulnerable implementation:
  Backend trusts `walletAddress` from frontend state after a UI "connected" event.
- Safe implementation:
  Backend issues a nonce, wallet signs it, backend verifies signature and binds the address once.

### 3.2 Trust in frontend "wallet connected" state

- Attack vector:
  App assumes UI connection status proves ownership or authorization.
- What to test:
  Trigger flows that require a wallet after only manipulating client state or simulating TonConnect callbacks.
- Reproduction ideas:
  Patch local app state, `postMessage` events, or API requests to make the app think a wallet is connected.
- Evidence of vulnerability:
  Protected flows succeed without real wallet proof.
- Impact / severity:
  `High`.
- Safe implementation:
  Treat connection state as UX only; ownership must be backed by server-verified signature.

### 3.3 Payload manipulation before signature

- Attack vector:
  Attacker or injected script alters transaction parameters before the wallet prompts the user.
- What to test:
  Modify `to`, `amount`, `payload`, `stateInit`, and expiration in the exact request passed to `sendTransaction`.
- Reproduction ideas:
  Hook the TonConnect call in DevTools and swap payload fields before the wallet receives them.
- Evidence of vulnerability:
  App or backend assumes one transaction was intended while a materially different one can be signed.
- Impact / severity:
  `High`.
- Vulnerable implementation:
  App renders one order summary but signs mutable client-side transaction data with no server-side reconciliation.
- Safe implementation:
  Generate transaction intent from server state, verify final on-chain settlement against expected recipient, amount, and payload.

### 3.4 MITM or message spoofing between TMA and wallet

- Attack vector:
  The real risk is often not classic TLS MITM but in-app message spoofing, XSS, bridge misuse, or fake callbacks.
- What to test:
  Review wallet communication flow, bridge endpoints, callback handling, and any trust placed in client-reported success.
- Reproduction ideas:
  Simulate wallet success/cancel states, alter bridge responses where possible, or use XSS to modify pre-signature state.
- Evidence of vulnerability:
  Backend finalizes sensitive actions based only on client callback or UI result.
- Impact / severity:
  `High`.
- Safe implementation:
  Final state changes must rely on server-side verification, not just wallet UI callbacks.

---

## 4. Direct Smart Contract Interaction

### 4.1 Backend trusts client claim that a transaction was sent

- Attack vector:
  User reports a tx hash or success flag, and backend grants assets or completes orders without on-chain validation.
- What to test:
  Skip the real transaction and submit fake success artifacts, fake hashes, or another unrelated transaction hash.
- Reproduction ideas:
  Replay purchase-complete endpoints with arbitrary transaction references or direct frontend success flags.
- Evidence of vulnerability:
  Goods, credits, or access are granted without a matching on-chain payment.
- Impact / severity:
  `Critical`.
- Vulnerable implementation:
  Fulfillment keyed off the TonConnect callback result only.
- Safe implementation:
  Backend verifies on-chain transaction details through a trusted node or indexer before fulfillment.

### 4.2 Weak sender verification

- Attack vector:
  System sees the contract was paid, but does not verify the sender is the expected wallet for that user or order.
- What to test:
  Pay from a different wallet, relay, or proxy and see whether the action still counts toward the target account.
- Reproduction ideas:
  Reuse a transaction from another wallet or trigger settlement with mismatched Telegram user to wallet identity.
- Evidence of vulnerability:
  Payment or action is credited to the wrong user or without proof of intended ownership.
- Impact / severity:
  `High`.
- Safe implementation:
  Verify sender address, recipient address, amount, payload, and linkage to a pre-created order.

### 4.3 Replay attacks on TON transaction references

- Attack vector:
  One successful transaction can be reused to satisfy multiple actions.
- What to test:
  Resubmit the same tx hash, logical order reference, payload memo, or signed intent multiple times.
- Reproduction ideas:
  Complete one purchase and then call the fulfillment endpoint again with the same transaction identifiers.
- Evidence of vulnerability:
  Double credit, double mint, repeated reward claims, or multiple state changes from one transaction.
- Impact / severity:
  `High` to `Critical`.
- Vulnerable implementation:
  No consumed-state tracking for transaction IDs, order IDs, or unique payload references.
- Safe implementation:
  Use one-time order IDs, unique payload markers, and processed-record checks.

---

## 5. Common Web Vulnerabilities in TMA Context

### 5.1 XSS via Telegram-controlled profile fields

- Attack vector:
  Telegram user-controlled fields are rendered unsafely in the DOM.
- Inputs to focus on:
  `username`, `first_name`, `last_name`, `photo_url`, bio-like mirrored fields, and any values reflected from `start_param`.
- What to test:
  Stored and reflected XSS through unsafe sinks such as `innerHTML`, template injection, markdown renderers, or unsafe component APIs.
- Reproduction ideas:
  Set a crafted profile field where possible, or inject payloads through any mirrored backend storage, then open the TMA and admin views.
- Evidence of vulnerability:
  JavaScript execution, token theft, forced actions, or wallet-flow manipulation.
- Impact / severity:
  Usually `High`; `Critical` if it leads to account takeover, wallet drain, or privileged backend actions.
- Vulnerable implementation:
  Rendering user fields as raw HTML.
- Safe implementation:
  Use text-only rendering or a hardened sanitizer for genuinely rich content.

### 5.2 CSRF applicability in TMA

- Attack vector:
  TMA backend uses cookie-based auth and state-changing endpoints without CSRF protection.
- What to test:
  Whether authenticated state-changing requests can be triggered cross-site with cookies attached.
- Reproduction ideas:
  Build a proof-of-concept HTML form or fetch request from another origin and test state-changing endpoints.
- Evidence of vulnerability:
  Profile changes, wallet binding, or actions succeed via cross-site request.
- Impact / severity:
  `Medium` to `High`, depending on action sensitivity.
- Notes:
  If the app uses bearer tokens in headers and correct CORS, classic CSRF may be reduced, but do not assume it away.
- Safe implementation:
  `SameSite` cookies, anti-CSRF tokens, proper CORS, and no state changes via GET.

### 5.3 `postMessage` security in iframe / embedded context

- Attack vector:
  App trusts any posted message or uses wildcard origin rules.
- What to test:
  Inspect listeners for `message` events and determine whether `origin`, `source`, and message schema are validated.
- Reproduction ideas:
  Send crafted `postMessage` payloads from another window or nested context to simulate auth, wallet, or payment events.
- Evidence of vulnerability:
  State changes occur from arbitrary-origin messages.
- Impact / severity:
  `Medium` to `Critical`, depending on reachable action.
- Vulnerable implementation:
  `postMessage('*')` or `window.addEventListener('message', ...)` without strict checks.
- Safe implementation:
  Strict origin allowlist, message type validation, and no trust in client-only success signals.

### 5.4 CSP weaknesses and TMA-specific reality

- Attack vector:
  Weak CSP makes XSS easier to exploit or fails to contain script injection.
- What to test:
  Presence of `unsafe-inline`, `unsafe-eval`, broad script allowlists, JSONP-like gadgets, or trusted third-party script chains.
- Reproduction ideas:
  Review headers and DOM sinks together; CSP alone is not enough if dangerous rendering already exists.
- Evidence of vulnerability:
  CSP meaningfully fails to block exploit chains that should have been constrained.
- Impact / severity:
  Often `Low` by itself, but `High` as part of an XSS chain.
- Safe implementation:
  Tight script-src, nonce- or hash-based script execution, and elimination of unsafe DOM sinks.

---

## 6. Infrastructure and Secret Exposure

### 6.1 Transport interception and HTTPS assumptions

- Attack vector:
  Sensitive traffic is exposed due to plain HTTP, mixed content, weak cookie flags, or trust in hostile devices/proxies.
- What to test:
  Ensure all API calls use HTTPS, check for mixed content, inspect HSTS and cookie flags, and test whether auth tokens leak in URLs.
- Reproduction ideas:
  Proxy the app, inspect all requests, and look for downgrade or plaintext channels.
- Evidence of vulnerability:
  Secrets or session tokens are transmitted insecurely.
- Impact / severity:
  `High` to `Critical` if tokens or personal data are exposed.
- Note:
  Lack of certificate pinning alone is usually not a valid finding.
- Safe implementation:
  HTTPS everywhere, `Secure` and `HttpOnly` cookies, HSTS, and no sensitive data in query strings.

### 6.2 Bot token leakage in frontend or public artifacts

- Attack vector:
  Telegram bot token appears in JavaScript bundles, source maps, config files, logs, or public repositories.
- What to test:
  Search bundles and static assets for bot-related secrets, environment variable leaks, debug endpoints, or exposed CI artifacts.
- Reproduction ideas:
  Grep built JS, source maps, public config, and archived frontend assets for token-shaped patterns.
- Evidence of vulnerability:
  Recoverable bot token or equivalent signing secret.
- Impact / severity:
  Usually `Critical`.
- Safe implementation:
  Bot token remains server-side only, rotated when exposed, and never shipped to clients.

### 6.3 Sensitive data in `localStorage` / `sessionStorage`

- Attack vector:
  Long-lived auth artifacts are readable by any XSS or hostile script in the TMA context.
- What to test:
  Inspect browser storage for session tokens, raw `initData`, wallet binding secrets, order nonces, or privileged flags.
- Reproduction ideas:
  Review storage after login, wallet binding, and purchase flows.
- Evidence of vulnerability:
  Reusable secrets are stored in JavaScript-readable storage.
- Impact / severity:
  `Medium` to `High`, depending on what is exposed.
- Vulnerable implementation:
  Long-lived bearer tokens in `localStorage`.
- Safe implementation:
  Prefer server-managed sessions or short-lived tokens with rotation; avoid storing high-value secrets in web storage.

---

## Practical Testing Workflow

### Phase 1: Identity boundary

1. Launch the TMA normally and capture all auth-related requests.
2. Determine whether the backend receives raw `initData`, parsed user fields, or both.
3. Replace `user.id`, `username`, and `auth_date` and check whether auth still succeeds.
4. Replay the same valid login payload later to test freshness and replay handling.

### Phase 2: Client trust and deep links

1. Override `window.Telegram.WebApp.initDataUnsafe` values in DevTools.
2. Look for logic keyed off `username`, `is_premium`, or `start_param`.
3. Try arbitrary `startapp` / `start_param` values for referral, tenant, feature, and routing abuse.

### Phase 3: Wallet binding and transaction integrity

1. Identify how wallet connection state is represented in requests.
2. Test whether wallet ownership requires a signed nonce.
3. Intercept TonConnect transaction construction and mutate recipient, amount, and payload.
4. Verify whether server-side fulfillment relies on client-reported success or on-chain confirmation.

### Phase 4: Web attack surface

1. Trace all render paths for Telegram-controlled data.
2. Review `message` event listeners and origin checks.
3. Assess CSP and dangerous DOM APIs together.
4. Check cookie model to determine whether CSRF is applicable.

### Phase 5: Secrets and storage

1. Grep client assets for bot tokens and credentials.
2. Inspect `localStorage`, `sessionStorage`, cookies, and IndexedDB.
3. Review whether sensitive data is sent in URLs, logs, or analytics payloads.

---

## High-Signal Bug Bounty Reporting Angles

### Best report candidates

- Full auth bypass by forging or replaying `initData`
- Account takeover by changing Telegram identity fields trusted by backend
- Wallet ownership spoofing without signed challenge
- Purchase / mint / claim completion without real on-chain validation
- Replay of one payment or transaction for multiple credits
- Stored or reflected XSS leading to session theft or transaction manipulation
- Bot token exposure enabling signature abuse or bot compromise

### Findings that are often weaker alone

- Absence of certificate pinning
- Weak CSP without exploit path
- Client-side spoofing that only changes UI and has no backend effect

---

## Secure Reference Patterns

### Telegram identity

- Server validates raw `initData`
- HMAC computed exactly per Telegram spec
- `auth_date` checked with tight TTL
- Backend issues its own session after validation

### Wallet ownership

- Nonce issued by backend
- Wallet signs nonce
- Backend verifies signature and binds address
- Nonce is one-time and expires quickly

### Payment settlement

- Backend creates order before payment
- Expected recipient, amount, and payload are stored server-side
- Fulfillment occurs only after on-chain verification
- Order and transaction references are marked consumed

### Web security

- Telegram-controlled data rendered as text, not HTML
- Strict `postMessage` origin and schema validation
- No sensitive state changes from client-only success callbacks
- Secrets never shipped to the client

---

## Quick Severity Heuristics

- `Critical`:
  auth bypass, account takeover, fake wallet ownership with monetary impact, payment completion without real payment, bot token exposure
- `High`:
  XSS with session or wallet-flow impact, replay causing duplicate value, weak sender verification, client-side only trust in critical actions
- `Medium`:
  referral abuse, CSRF on non-funds actions, storage exposure of reusable auth artifacts
- `Low` / `Info`:
  UI-only spoofing, pinning absence without additional weakness, hardening gaps without exploitability

---

## Notes for Real Assessments

- Treat everything from the browser or TMA runtime as attacker-controlled unless cryptographically verified server-side.
- Separate three trust questions clearly:
  Telegram identity, wallet ownership, and transaction finality.
- Many high-impact findings come from developers collapsing those three into one assumption.
