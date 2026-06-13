# Pharos Mainnet Gas Accounting Triage

Scope: Pharos Mainnet, chainId `1672 / 0x688`.

Focus: whether real sender balance deltas indicate fee charging by `gasLimit` instead of actual `gasUsed`, or whether explorer/API fee reporting differs from balance movement.

## 1. Candidate selection method

- Used SocialScan recent transaction pages to find high-signal transactions.
- Pulled full transaction details from SocialScan.
- Pulled RPC transaction, receipt, and sender balances from `https://rpc.pharos.xyz`.
- For each tx at block `N`, read sender native balance at `N-1` and `N`.
- Chose 5 transactions covering:
  - one failed transaction with very high `gasLimit` and low `gasUsed`
  - one OffRamp `Commit`
  - one `Claim`
  - one WPROS `Deposit` with native value movement
  - one complex LiFi/Glacis bridge-start call with large native value and high gas limit

I also did a quick recent-page search for a simple ERC20 `transfer` transaction with value `0` and `receipt_gas_used > 21000`; no suitable direct example appeared quickly in the sampled pages, so I did not spend more time on that low-promise subpath.

## 2. Five selected transactions

| Tx | Block/time | From | To | Method | Status | Gas limit | Gas used | Gas price | Value | Why high-signal |
|---|---:|---|---|---|---:|---:|---:|---:|---:|---|
| `0xd350dfdd711a38ce1b72a5ca4603d6b0ffde9bb6318b03e7f8477ec902d48fe4` | `7199552`, `2026-05-13T13:10:12Z` | `0x2b9025a26a9996a2cb09388523955e1ebf3f8dde` | `0x0ed7f1994907ec81e0522141cb33947a8e78e024` | `0x0989b6b9` | failed | `10000000` | `43736` | `30000000000` | `0` | failed tx, huge unused gas limit |
| `0x148dbb71955996ab660789eceed30771083b266564b89345875696303441543a` | `7199542`, `2026-05-13T13:10:04Z` | `0x37557c61dbcb7ab4e6743306a679974a8d670b75` | `0x40858070814a57fdf33a613ae84fe0a8b4a874f7` | `Commit` | success | `500000` | `125792` | `10000000000` | `0` | contract call, large gas gap |
| `0x075800a6279f4f424ed20ba76edf9b03c5a970ff08a234c121105af4b222e368` | `7199495`, `2026-05-13T13:09:27Z` | `0x5ab0a5fbb4543dc3b87f60377b49ae5151a0efa9` | `0x7c06f7d4e0f77b5e1d6499f2a1dc291de044f100` | `Claim` | success | `448881` | `113923` | `10000000000` | `0` | claim lifecycle call, large gas gap |
| `0x441186b42dd43aa5e90fab9ed6606760c8cb94e4a4511a02aeca2e77a0bc8b7e` | `7199432`, `2026-05-13T13:08:36Z` | `0x5570fbe72d27f140c996191f3c669e767a1fdbd1` | `0x52c48d4213107b20bc583832b0d951fb9ca8f0b0` | `Deposit` | success | `110205` | `27842` | `10000000000` | `10000000000000000` | native value plus token-side wrapper event |
| `0x53183357ffdc6ebe83e6d7e062e2e54e6e324e7ec983338860683e04f2887419` | `7197111`, `2026-05-13T12:38:10Z` | `0x7cc6eed5fb840fb7a72ff8157a0c7c21158a978a` | `0xff70f4a1d11995621854f3692acf286d8acd04b2` | `Swap And Start Bridge Tokens Via Glacis` | success | `1193400` | `421471` | `10000000000` | `2299839688929768999443` | complex call, large value and large gas gap |

## 3. Balance delta table

| Tx | Status | gasLimit | gasUsed | effectiveGasPrice | value | balanceBefore | balanceAfter | observedDelta | expectedFeeByGasUsed | expectedFeeByGasLimit | unexplainedDelta | Matches gasUsed | Matches gasLimit |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| `0xd350dfdd...48fe4` | `0x0` | `10000000` | `43736` | `30000000000` | `0` | `3003079490000000000` | `3001767410000000000` | `1312080000000000` | `1312080000000000` | `300000000000000000` | `0` | yes | no |
| `0x148dbb71...543a` | `0x1` | `500000` | `125792` | `10000000000` | `0` | `43771484583840766000` | `43770226663840766000` | `1257920000000000` | `1257920000000000` | `5000000000000000` | `0` | yes | no |
| `0x075800a6...e368` | `0x1` | `448881` | `113923` | `10000000000` | `0` | `7289002000000000000` | `7287862770000000000` | `1139230000000000` | `1139230000000000` | `4488810000000000` | `0` | yes | no |
| `0x441186b4...8b7e` | `0x1` | `110205` | `27842` | `10000000000` | `10000000000000000` | `2254586573367190725` | `2244308153367190725` | `10278420000000000` | `278420000000000` | `1102050000000000` | `0` | yes | no |
| `0x53183357...7419` | `0x1` | `1193400` | `421471` | `10000000000` | `2299839688929768999443` | `2309583546483366029997` | `9739642843597030554` | `2299843903639768999443` | `4214710000000000` | `11934000000000000` | `0` | yes | no |

Formula used:

`unexplainedDelta = balanceBefore - balanceAfter - tx.value - (gasUsed * effectiveGasPrice)`

All five have `unexplainedDelta = 0`.

## 4. Explorer/API fee comparison

| Tx | RPC gasUsed | RPC effectiveGasPrice | SocialScan/explorer fee | Balance delta result | Classification |
|---|---:|---:|---:|---|---|
| `0xd350dfdd...48fe4` | `43736` | `30000000000` | `1312080000000000` | matches gasUsed model | A |
| `0x148dbb71...543a` | `125792` | `10000000000` | `1257920000000000` | matches gasUsed model | A |
| `0x075800a6...e368` | `113923` | `10000000000` | `1139230000000000` | matches gasUsed model | A |
| `0x441186b4...8b7e` | `27842` | `10000000000` | `278420000000000` | matches gasUsed model after subtracting tx value | A |
| `0x53183357...7419` | `421471` | `10000000000` | `4214710000000000` | matches gasUsed model after subtracting tx value | A |

## 5. Refund expectation observations

- The failed tx `0xd350...48fe4` is the strongest gas-limit test:
  - gas limit: `10,000,000`
  - gas used: `43,736`
  - balance delta: `1,312,080,000,000,000`
  - gas-limit fee would have been `300,000,000,000,000,000`
  - observed delta matches `gasUsed * gasPrice`, not gas limit.
- No storage-clearing or opcode-level refund-heavy transaction was identified quickly. I did not expand the search because the high-gas-limit failed tx already directly tests the main triage question.

## 6. Suspicious states

None in Stage 1.

Not observed:

- sender balance decreasing by `gasLimit * effectiveGasPrice`
- explorer fee using `gasUsed` while balance delta suggests `gasLimit`
- failed tx charging beyond receipt `gasUsed`
- unexplained fee delta after subtracting tx value
- mismatch between SocialScan fee fields and RPC receipt fields

## 7. Disproved/cosmetic differences

- Large unused gas limit is cosmetic from a final-cost perspective in the sampled txs.
- Failed status did not imply gas-limit charging in the sampled failed tx.
- Explorer/SocialScan fee fields matched `gasUsed * effectiveGasPrice`.

## 8. Triage decision

STOP.

All five sampled transactions match normal `gasUsed * effectiveGasPrice` sender balance deltas after subtracting `tx.value` where applicable. No concrete fee/balance observer disagreement was found.

## 9. Recommended next target

Next highest-value target: `PROSPixel event-vs-storage`.

Final judgment:

STOP: No strong lead in sampled gas accounting behavior.
