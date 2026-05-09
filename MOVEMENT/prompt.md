You are a senior Move / DeFi security researcher.

Targets:
1. Meridian on Movement Network
2. Yuzu on Movement Network
3. Echelon Market on Movement Network

Goal:
Find only Critical or High-risk vulnerabilities in active production deployments of these protocols on Movement mainnet.

Strict output rule:
Do not report Medium, Low, Informational, best-practice, code-quality, gas, documentation, or theoretical issues. Report only vulnerabilities with a realistic Critical or High impact.

Important scope rule:
Analyze only active, currently used production contracts/modules/markets/pools on Movement mainnet.

Do not analyze:
- Deprecated contracts
- Testnet deployments
- Old GitHub code
- Unused modules
- Historical addresses
- Example code
- Documentation-only addresses
- Inactive pools
- Inactive markets
- Forked code that is not deployed
- Contracts/modules with no active liquidity, no recent transactions, and no active protocol role

Before analyzing any module, pool, or market, first prove it is active.

Active-use evidence may include:
- Official frontend/config references
- Current Movement mainnet deployment references
- Recent transactions
- Recent events
- Non-trivial TVL
- Active pool liquidity
- Active trading volume
- Active lending supply/borrow
- Active oracle usage
- Explorer-verified deployed module/package data
- References from official docs, frontend API, or indexer configs

If active-use evidence is missing, classify the item as “inactive / unconfirmed” and do not spend time auditing it.

Primary assets to inspect:
- MOVE
- USDC.e
- USDT.e
- USDCx
- WETH.e
- WBTC.e
- BTC derivatives if actively used
- Any LP tokens, position NFTs, receipt tokens, collateral tokens, debt tokens, or vault shares created by Meridian, Yuzu, or Echelon

Main hypothesis:
Look for Critical/High vulnerabilities caused by asset identity confusion, decimals mismatch, bridged/native stablecoin mismatch, oracle manipulation, pool math errors, share accounting errors, liquidation bugs, and integration bugs between DEX liquidity and lending markets.

Special focus:
- USDC.e vs USDCx confusion
- USDC.e vs USDT.e assumption errors
- WETH.e / WBTC.e decimals and oracle normalization
- Fake or wrong asset accepted as a real bridged asset
- LP token or position token accepted at incorrect value
- DEX pool price used as lending oracle
- Router/aggregator route affects lending collateral value
- Thin pool manipulation causing bad debt
- CLMM tick/fee accounting edge cases
- Lending liquidation math bugs

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
- Issues requiring a privileged role to intentionally act maliciously
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
- LP pool drain
- Incorrect swap output that drains a pool
- Unauthorized minting or redemption of LP/position/receipt tokens
- Oracle manipulation causing lending or pool loss
- Share inflation leading to fund extraction
- Interest index manipulation causing fund extraction
- Accepted fake asset or wrong asset as collateral/liquidity
- Bypass of collateral factor or liquidation checks
- Permanent freezing of significant protocol funds
- Cross-asset accounting bug involving USDC.e / USDCx / USDT.e / WBTC.e
- Loss of funds through active integrations among Meridian, Yuzu, and Echelon

Do not report:
- Missing events
- Poor naming
- Inefficient code
- Centralization risk alone
- Admin can pause/unpause
- Admin can list a bad pool or market
- Admin can change oracle
- Admin can upgrade contract
- User can choose bad slippage
- User can trade against a bad price knowingly
- User can deposit a fake token into an unrelated fake pool
- Low-liquidity manipulation with no protocol loss
- Theoretical issue with no executable attack path
- Any issue affecting only inactive contracts, markets, or pools

Project-specific focus:

A. Meridian
Protocol type:
DEX / liquidity engine on Movement.

Analyze only active Meridian pools, routers, LP tokens, and integrations.

Focus on:
- Constant-product or stable-swap math if present
- Pool initialization
- LP mint/burn accounting
- Swap output calculation
- Fee accounting
- Token pair identity
- Decimals normalization
- Stablecoin pools involving USDC.e, USDT.e, USDCx
- MOVE / stable pools
- WETH.e / WBTC.e pools
- LP share inflation
- Donation attacks
- Incorrect reserve accounting
- Router path validation
- Fake token or fake pool acceptance
- Pool price used by external protocols

High-risk hypotheses for Meridian:
- First depositor or donation attack inflates LP share price and drains later deposits
- Decimals mismatch allows pool drain
- Stable pool invariant breaks for USDC.e/USDT.e/USDCx
- Router accepts malicious pool or wrong asset
- LP token can be minted or burned for more value than deserved
- Pool price can be manipulated and used by lending/vault protocols
- Pool accounting breaks with bridged token metadata or wrapper tokens

B. Yuzu
Protocol type:
Concentrated liquidity DEX / CLMM on Movement.

Analyze only active Yuzu pools, position modules, routers, tick accounting, and integrations.

Focus on:
- CLMM tick math
- Price bounds
- Liquidity position creation
- Position modification
- Fee growth accounting
- Tick crossing
- Rounding direction
- Swap exact-in / exact-out behavior
- Zero-liquidity intervals
- Pool initialization price
- Position NFT/resource ownership
- Collect fees
- Burn/decrease liquidity
- Token pair identity
- Decimals normalization
- USDC.e / USDT.e / USDCx pools
- MOVE / stable pools
- WETH.e / WBTC.e pools

High-risk hypotheses for Yuzu:
- Tick crossing miscalculates liquidity and drains pool
- Fee growth accounting lets attacker collect unearned fees
- Position ownership/resource check can be bypassed
- Liquidity removal returns too many tokens
- Pool initialization at extreme price enables share/price manipulation
- Swap math overflows, underflows, or rounds in attacker’s favor
- Exact-out swap bypasses price limit or liquidity limit
- Fake token pair or duplicate pool causes routing loss
- CLMM pool price is used by lending protocol as oracle and can be manipulated

C. Echelon Market
Protocol type:
Lending / money market on Movement.

Analyze only active Echelon markets, collateral assets, borrow assets, oracle modules, receipt/debt tokens, and integrations.

Focus on:
- Supply/borrow accounting
- Collateral factors
- Health factor calculation
- Liquidation logic
- Oracle sources
- Interest accrual
- Borrow index / supply index
- Receipt token mint/burn
- Debt token accounting
- Market listing identity
- Stablecoin collateral and borrow markets
- BTC derivative collateral if active
- WETH.e/WBTC.e markets
- USDC.e/USDT.e/USDCx confusion
- DEX oracle dependency on Meridian/Yuzu/Mosaic pools

High-risk hypotheses for Echelon:
- Attacker can borrow more than collateral value
- Attacker can withdraw collateral while undercollateralized
- Stale or manipulable oracle creates bad debt
- USDC.e and USDCx are valued interchangeably when they should not be
- WBTC.e and BTC derivative are treated as identical
- Decimals mismatch overvalues collateral
- Liquidation seizes too much collateral
- Healthy accounts can be liquidated
- Unhealthy accounts cannot be liquidated
- Interest index desync lets attacker repay less or withdraw more
- First depositor/share inflation attack drains market
- Donation attack inflates collateral value
- Fake asset type can be supplied or used as collateral

Methodology:

Step 1: Active deployment discovery
For each target, find active Movement mainnet deployments.

Collect:
- Package/module addresses
- Pool/market/resource identifiers
- Active asset pairs
- Accepted collateral assets
- Borrowable assets
- Oracle contracts/modules
- Router modules
- LP/position/receipt/debt token structures
- Frontend or API config addresses
- Recent transactions and events
- Current TVL/liquidity/volume/borrow exposure if available

Reject anything that is not clearly active.

Step 2: Build protocol-specific state models

For Meridian:
Map:
- Create pool
- Add liquidity
- Remove liquidity
- Swap
- Claim fees/rewards
- Router multi-hop swap
- LP token mint/burn

For Yuzu:
Map:
- Create CLMM pool
- Initialize price
- Open position
- Add liquidity
- Remove liquidity
- Swap across ticks
- Collect fees
- Close position
- Router multi-hop swap

For Echelon:
Map:
- Supply
- Enable collateral
- Borrow
- Accrue interest
- Repay
- Withdraw
- Liquidate
- Seize collateral
- Claim rewards, if rewards affect accounting

For each transition identify:
- Required signer
- Required asset type
- Balance changes
- Share/index/liquidity changes
- Oracle price dependency
- Health factor dependency if lending-related
- Rounding direction
- Event/resource updates
- External module calls
- Failure behavior

Step 3: Asset identity checks
For every active pool/market, verify:
- Exact asset type/address
- Symbol/name/metadata
- Decimals
- Bridge origin
- Whether asset is native, bridged, wrapped, or derivative
- Whether similar-looking assets exist
- Whether exact type/address is checked instead of symbol/name
- Whether fake assets can be used in any path
- Whether USDC.e, USDT.e, and USDCx are treated distinctly
- Whether WBTC.e and BTC derivatives are treated distinctly

Step 4: Oracle and price dependency review
Identify all price sources used directly or indirectly.

Check:
- Whether Echelon uses Meridian/Yuzu pools as price source
- Whether external integrations use Meridian/Yuzu pool prices as oracle
- Whether thin liquidity pools can be manipulated
- Whether TWAP exists and is correctly enforced
- Whether oracle price is stale
- Whether decimals are normalized correctly
- Whether price feed asset identity matches market asset identity
- Whether stablecoins are hardcoded to $1
- Whether bridged and native stablecoins share a price feed
- Whether BTC derivatives are priced as BTC without discount
- Whether fallback oracle paths can be abused
- Whether price update timing can be exploited in borrow/liquidation flow

Only report oracle issues if they allow realistic fund loss, bad debt, or unauthorized profit.

Step 5: DEX accounting review
For Meridian and Yuzu, check:
- Pool initialization
- Reserve accounting
- Liquidity accounting
- LP/position token minting
- LP/position token burning
- Fee accounting
- Swap math
- Exact-in/exact-out behavior
- Decimals normalization
- Rounding direction
- Donation attacks
- First depositor attacks
- Low-liquidity manipulation
- Duplicate pool creation
- Fake token pair creation
- Router path validation
- Pool spoofing
- Multi-hop output validation
- Slippage enforcement at contract level
- Protocol fee extraction

High-risk DEX hypotheses:
- Attacker drains real liquidity from active pool
- Attacker mints LP/position claims for less value than received
- Attacker collects unearned fees
- Attacker manipulates pool price to exploit lending/vault protocol
- Attacker routes swaps through spoofed pool/token
- Attacker exploits decimals mismatch to receive excess output
- Attacker initializes duplicate/fake pool that official router accepts

Step 6: Lending accounting review
For Echelon, check:
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

Step 7: Cross-protocol integration review
Analyze active interactions among:
- Meridian pools
- Yuzu pools
- Echelon oracle/markets
- Movement bridge assets
- Aggregators if directly used by these protocols
- Vaults if they deposit into these protocols

Focus on:
- DEX price manipulated to borrow from Echelon
- LP token misvalued as collateral
- Wrong stablecoin accepted in lending or pool
- Route returns wrong asset but is treated as correct
- Pool price used without liquidity threshold
- USDC.e to USDCx migration assumptions
- BTC derivative treated as WBTC.e
- Movement bridged token metadata mismatch

Step 8: Exploit validation
For every suspected issue, validate:
- Is the affected module active?
- Is the affected pool/market active?
- Is there real liquidity, supplied assets, or borrow exposure?
- Can a normal external attacker execute it?
- Does it avoid relying on admin compromise?
- Does it avoid relying on admin mistakes?
- Does it avoid relying on user mistakes?
- Does it avoid relying on frontend-only behavior?
- Does it produce Critical or High impact?
- Is the attack economically realistic?
- Can it be demonstrated with a transaction sequence or local PoC?

Required output format for confirmed findings:

Title:
Severity: Critical or High
Target protocol:
Affected active module/contract:
Network:
Active-use evidence:
Affected assets/pools/markets:
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

1. Active deployments reviewed
2. Active pools/markets reviewed
3. Assets reviewed
4. Oracle/price sources reviewed
5. DEX flows reviewed
6. Lending flows reviewed
7. Cross-protocol integrations reviewed
8. Invariants tested
9. High-risk hypotheses rejected and why
10. Remaining areas for deeper manual review

Strict final rule:
Do not output a vulnerability unless it affects active production infrastructure on Movement and can realistically cause Critical or High impact without admin-wallet compromise, admin mistakes, user mistakes, phishing, or frontend-only assumptions.