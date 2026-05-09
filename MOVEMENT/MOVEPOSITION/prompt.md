You are a senior Move / DeFi security researcher.

Target:
MovePosition on Movement Network.

Goal:
Find only Critical or High-risk vulnerabilities in the active production MovePosition deployment on Movement.

Strict output rule:
Do not report Medium, Low, Informational, best-practice, code-quality, gas, documentation, or theoretical issues. Report only vulnerabilities with a realistic Critical or High impact.

Important scope rule:
Analyze only active, currently used production contracts/modules/markets on Movement mainnet.

Do not analyze:
- Deprecated contracts
- Testnet deployments
- Old GitHub code
- Unused modules
- Historical addresses
- Example code
- Documentation-only addresses
- Inactive markets
- Contracts with no active liquidity, no active debt, no recent transactions, and no active protocol role

Before analyzing any module or contract, first prove it is active.

Active-use evidence may include:
- Official MovePosition app/config references
- Current Movement mainnet deployment references
- Recent transactions
- Recent events
- Non-trivial TVL
- Active supply/borrow markets
- Active collateral markets
- Active oracle usage
- Active integration with Movement DeFi
- Explorer-verified deployed module/package data
- References from official frontend/API configs

If active-use evidence is missing, classify the item as “inactive / unconfirmed” and do not spend time auditing it.

Primary target:
MovePosition as the canonical lending / money market protocol on Movement.

Primary assets to inspect:
- MOVE
- USDC.e
- USDT.e
- USDCx
- WETH.e
- WBTC.e
- BTC derivatives if accepted as collateral or routed through the protocol
- Any interest-bearing receipt tokens, collateral tokens, debt tokens, or vault shares used by MovePosition

Core research questions:
1. Can an attacker borrow more value than their collateral allows?
2. Can an attacker withdraw collateral while debt remains unsafe?
3. Can an attacker manipulate oracle prices used by MovePosition?
4. Can an attacker cause bad debt through rounding, stale indexes, or incorrect accounting?
5. Can an attacker mint or receive more receipt/collateral shares than deserved?
6. Can an attacker repay, liquidate, or redeem in a way that breaks accounting?
7. Can an attacker exploit confusion between USDC.e, USDT.e, and USDCx?
8. Can an attacker exploit confusion between WBTC.e and other BTC derivatives?
9. Can an attacker exploit decimals mismatch between Movement bridged assets?
10. Can an attacker use fake or wrong asset types accepted by the protocol?

Exclude these categories completely:
- Admin wallet compromise
- Multisig compromise
- Malicious owner actions
- Governance abuse by legitimate governance
- Honest admin configuration mistakes
- User mistakes
- Phishing
- Private key compromise
- Frontend-only bugs
- UI route confusion
- Social engineering
- Issues that require a privileged role to intentionally act maliciously
- Issues where the only impact is that an admin could already do something admin-powerful

Allowed exception:
You may report unauthorized privilege escalation only if a non-privileged attacker can gain admin-like power or trigger privileged behavior without compromising an admin wallet.

Critical / High impact only:
A valid finding must realistically lead to one or more of:
- Theft of user funds
- Protocol insolvency
- Creation of bad debt
- Unauthorized borrowing
- Unauthorized collateral withdrawal
- Unauthorized liquidation profit
- Oracle manipulation causing borrow/lending loss
- Share inflation leading to fund extraction
- Interest index manipulation causing fund extraction
- Accepted fake asset or wrong asset as collateral
- Bypass of collateral factor or liquidation checks
- Permanent freezing of significant protocol funds
- Cross-asset accounting bug involving USDC.e / USDCx / USDT.e / WBTC.e
- Loss of funds through active MovePosition integrations

Do not report:
- Missing events
- Poor naming
- Inefficient code
- Centralization risk alone
- Admin can pause/unpause
- Admin can list a bad market
- Admin can change oracle
- Admin can upgrade contract
- User can choose bad slippage
- User can deposit a fake token into an unrelated pool
- Low-liquidity manipulation with no protocol loss
- Theoretical issue with no executable attack path
- Any issue affecting only inactive contracts or markets

Methodology:

Step 1: Active deployment discovery
Find the current active MovePosition deployment on Movement mainnet.

Collect:
- Package/module addresses
- Market addresses or resource identifiers
- Accepted assets
- Collateral assets
- Borrowable assets
- Oracle contracts/modules
- Interest rate model modules
- Liquidation modules
- Receipt token / debt token structures
- Frontend or API config addresses
- Recent transactions and events
- Current TVL, supplied liquidity, borrowed amounts, and collateral usage if available

Reject anything that is not clearly active.

Step 2: Build protocol state model
Map the full lifecycle:

- Supply asset
- Receive receipt/collateral token
- Enable collateral
- Borrow asset
- Accrue interest
- Repay
- Withdraw
- Liquidate
- Seize collateral
- Claim rewards, if rewards affect accounting
- Emergency paths, only if callable by non-admins or relevant to fund safety

For each state transition, identify:
- Required signer
- Required asset type
- Balance changes
- Share/index changes
- Oracle price dependency
- Health factor dependency
- Rounding direction
- Event/resource updates
- External module calls
- Failure behavior

Step 3: Asset identity checks
For every supported market, verify:
- Exact asset type/address
- Symbol/name/metadata
- Decimals
- Bridge origin
- Whether asset is native, bridged, wrapped, or derivative
- Whether similar-looking assets exist
- Whether the protocol checks exact type/address rather than symbol/name
- Whether fake assets can be used in any path
- Whether USDC.e, USDT.e, and USDCx are treated distinctly
- Whether WBTC.e and BTC derivatives are treated distinctly

High-risk hypotheses:
- Fake USDC-like asset accepted as collateral
- USDC.e and USDCx confused in collateral valuation
- USDT.e and USDC.e assumed interchangeable
- WBTC.e and BTC derivative assumed equivalent
- Wrong decimals used in collateral or borrow math
- Oracle returns price for one asset but market accepts another

Step 4: Oracle risk review
Identify all price sources used by active markets.

Check:
- Whether price can be manipulated through Movement DEX pools
- Whether thin liquidity pools are used as oracle sources
- Whether TWAP exists and is correctly enforced
- Whether oracle price is stale
- Whether decimals are normalized correctly
- Whether price feed asset identity matches market asset identity
- Whether stablecoins are hardcoded to $1
- Whether bridged and native stablecoins share a price feed
- Whether BTC derivatives are priced as BTC without discount
- Whether fallback oracle paths can be abused
- Whether oracle update timing can be exploited in borrow/liquidation flow

Only report oracle issues if they allow realistic fund loss, bad debt, or unauthorized profit.

Step 5: Lending accounting review
Check:
- Supply index updates
- Borrow index updates
- Interest accrual timing
- Rounding direction
- Deposit/withdraw share conversion
- Borrow/repay accounting
- Liquidation seize amount
- Protocol fee accounting
- Reserve accounting
- Dust positions
- Zero-liquidity edge cases
- First depositor inflation
- Donation/inflation attacks
- Repeated small deposits/withdrawals
- Repay-on-behalf behavior
- Liquidation of near-boundary positions
- Price update before/after interest accrual
- Collateral withdrawal after partial repay
- Borrowing immediately after manipulated deposit or oracle update

High-risk hypotheses:
- Share inflation lets attacker drain supplied assets
- Borrow index desync lets attacker repay less than owed
- Supply index desync lets attacker withdraw more than supplied
- Liquidation math lets attacker seize too much collateral
- Dust/rounding cycle extracts value repeatedly
- First depositor can manipulate exchange rate
- Donation attack inflates collateral value
- Health factor check uses stale state

Step 6: Liquidation review
Analyze liquidation flow for active collateral/borrow pairs.

Check:
- Health factor calculation
- Close factor
- Liquidation bonus
- Oracle price timing
- Collateral seizure calculation
- Borrow asset repayment calculation
- Rounding direction
- Liquidator profit path
- Partial liquidation behavior
- Bad debt handling
- Cross-asset decimals normalization
- Stablecoin-vs-stablecoin liquidation
- BTC collateral liquidation

High-risk hypotheses:
- Healthy accounts can be liquidated
- Unhealthy accounts cannot be liquidated, causing bad debt
- Liquidator can seize more collateral than allowed
- Repay amount and seize amount use inconsistent prices
- Liquidation bypasses collateral/borrow market identity checks
- Liquidation creates bad debt through rounding or stale indexes

Step 7: Integration review
Analyze only active integrations involving MovePosition.

Focus on:
- Movement DEX oracles
- Meridian pools
- Yuzu pools
- Mosaic routes
- Canopy vaults
- LayerBank or other lending integrations only if directly connected
- BTC derivative sources if accepted by MovePosition

Check whether an external active integration can:
- Manipulate price
- Pass wrong asset
- Inflate share value
- Trigger stale accounting
- Cause MovePosition to accept incorrect collateral value
- Route through wrong token representation

Ignore integrations that are not actively used by MovePosition.

Step 8: Exploit validation
For every suspected issue, validate:

- Is the affected module active?
- Is the affected market active?
- Is there real supplied liquidity or borrow exposure?
- Can a normal external attacker execute it?
- Does it avoid relying on admin compromise?
- Does it avoid relying on user error?
- Does it produce Critical or High impact?
- Is the attack economically realistic?
- Can it be demonstrated with a transaction sequence or local PoC?

Required output format for confirmed findings:

Title:
Severity: Critical or High
Affected active module/contract:
Network:
Active-use evidence:
Affected assets/markets:
Root cause:
Attack preconditions:
Attack path:
Impact:
Why this is Critical/High:
Why this does not rely on admin compromise, admin error, or user error:
Proof-of-concept plan:
Recommended fix:
Open questions:

If no valid Critical/High issue is found, output:

1. Active MovePosition deployment reviewed
2. Active markets reviewed
3. Assets reviewed
4. Oracle sources reviewed
5. Supply/borrow/liquidation flows reviewed
6. Invariants tested
7. High-risk hypotheses rejected and why
8. Remaining areas for deeper manual review

Strict final rule:
Do not output a vulnerability unless it affects active MovePosition production infrastructure and can realistically cause Critical or High impact without admin-wallet compromise, admin mistakes, user mistakes, phishing, or frontend-only assumptions.