# Aleo context map

Generated at: 2026-05-12T21:23:45.890Z

Scope: active programs returned by Provable `/v2/{network}/metrics/programs`, with full source pulled from `/v2/{network}/program/{program_id}`.
AleoScan registry pages were used as a secondary explorer reference, but local collection avoids Cloudflare-protected scraping.

## Source folders

- `raw/mainnet/program_sources/` and `raw/testnet/program_sources/`: downloaded Aleo Instruction sources.
- `parsed/{network}/`: per-program JSON plus CSV summaries.
- `graphs/dependencies.dot`: cross-program reference graph.
- `reports/high_risk_async_paths.md`: async, delayed, conditional, and bridge/proof-sensitive paths.

## mainnet

- Programs collected: 78
- Metric-window calls represented: 92654
- Download failures: 0

| Program | Calls | Class | Functions | Mappings | Cross refs | Async/conditional paths |
|---|---:|---|---:|---:|---|---:|
| `credits.aleo` | 64268 | token/credit flow | 15 | 8 | - | 12 |
| `puzzle_arcade_coin_v002.aleo` | 12992 | NFT/game asset | 2 | 0 | - | 2 |
| `puzzle_arcade_ticket_v002.aleo` | 5487 | NFT/game asset | 7 | 1 | - | 7 |
| `par_giveaways_v1.aleo` | 2160 | application/other | 13 | 8 | puzzle_arcade_ticket_v002.aleo | 13 |
| `puzzle_spinner_v003.aleo` | 1961 | application/other | 1 | 1 | puzzle_arcade_coin_v002.aleo, puzzle_arcade_ticket_v002.aleo | 1 |
| `mystery_city_v001.aleo` | 1065 | application/other | 1 | 1 | puzzle_arcade_coin_v002.aleo, puzzle_arcade_ticket_v002.aleo | 1 |
| `token_registry.aleo` | 1008 | token/credit flow | 22 | 5 | - | 22 |
| `whalepool_easystaking_v2.aleo` | 831 | staking/liquid staking | 11 | 8 | credits.aleo | 11 |
| `arcn_pool_v2_2_2.aleo` | 299 | DeFi pool/lending | 13 | 6 | arcn_access_manager_v1.aleo, arcn_whitelist.aleo, token_registry.aleo | 11 |
| `whalepool_easystaking_v3.aleo` | 255 | staking/liquid staking | 11 | 8 | credits.aleo | 11 |
| `betastaking.aleo` | 185 | staking/liquid staking | 20 | 8 | credits.aleo | 18 |
| `arcn_whitelist.aleo` | 181 | DeFi pool/lending | 4 | 2 | arcn_access_manager_v1.aleo | 4 |
| `zkwork_staker_v1.aleo` | 148 | staking/liquid staking | 4 | 1 | credits.aleo, withdrawaler.aleo, zkwork_staking.aleo | 4 |
| `pondo_protocol.aleo` | 147 | staking/liquid staking | 13 | 6 | credits.aleo, delegator1.aleo, delegator2.aleo, delegator3.aleo, delegator4.aleo, delegator5.aleo | 13 |
| `arcn_compliance_v1.aleo` | 146 | DeFi pool/lending | 2 | 0 | - | 2 |
| `zkwork_staking.aleo` | 137 | staking/liquid staking | 20 | 8 | credits.aleo | 18 |
| `squash_v4.aleo` | 116 | application/other | 6 | 1 | puzzle_arcade_coin_v002.aleo, puzzle_arcade_ticket_v002.aleo, squash_v3.aleo | 6 |
| `autojoin_credits_2_10.aleo` | 97 | token/credit flow | 9 | 0 | credits.aleo | 9 |
| `connection_v1.aleo` | 90 | bridge/cross-chain | 7 | 7 | credits.aleo, gmp_checksum_v1.aleo, gmp_lib_v1.aleo | 7 |
| `par_store_inventory_v1.aleo` | 88 | application/other | 5 | 2 | - | 5 |
| `asset_manager_helper_v1.aleo` | 86 | application/other | 3 | 3 | gmp_checksum_v1.aleo, gmp_lib_v1.aleo | 3 |
| `asset_manager_core_v1.aleo` | 86 | application/other | 3 | 1 | asset_manager_helper_v1.aleo, connection_v1.aleo, credits.aleo, gmp_checksum_v1.aleo, gmp_lib_v1.aleo, rate_limit_v1.aleo | 3 |
| `wrapped_credits.aleo` | 83 | token/credit flow | 5 | 0 | credits.aleo, token_registry.aleo | 5 |
| `arcn_pub_v2_2_3.aleo` | 79 | DeFi pool/lending | 6 | 0 | arcn_compliance_v1.aleo, arcn_pool_v2_2_2.aleo, token_registry.aleo | 6 |
| `arcn_priv_v2_2_3.aleo` | 64 | DeFi pool/lending | 6 | 0 | arcn_compliance_v1.aleo, arcn_pool_v2_2_2.aleo, token_registry.aleo | 6 |
| `usdcx_stablecoin.aleo` | 62 | token/credit flow | 21 | 5 | usdcx_freezelist.aleo, usdcx_multisig_core.aleo | 18 |
| `usad_stablecoin.aleo` | 58 | token/credit flow | 21 | 5 | usad_freezelist.aleo, usad_multisig_core.aleo | 18 |
| `rate_limit_v1.aleo` | 43 | oracle/governance guard | 8 | 4 | gmp_checksum_v1.aleo | 8 |
| `gmp_lib_v1.aleo` | 43 | bridge/cross-chain | 1 | 0 | - | 1 |
| `mining_jouny_test_v2.aleo` | 31 | application/other | 11 | 8 | credits.aleo | 11 |
| `arcn_puc_out_helper_swap_v2_2_6.aleo` | 26 | DeFi pool/lending | 2 | 0 | arcn_access_manager_v1.aleo, arcn_pool_v2_2_2.aleo, credits.aleo, token_registry.aleo, wrapped_credits.aleo | 2 |
| `withdrawaler.aleo` | 20 | application/other | 8 | 4 | credits.aleo | 8 |
| `vlink_token_bridge_v3.aleo` | 19 | bridge/cross-chain | 14 | 8 | - | 14 |
| `betastaker_1.aleo` | 18 | staking/liquid staking | 9 | 3 | betastaking.aleo, credits.aleo | 9 |
| `betastaker_3.aleo` | 16 | staking/liquid staking | 9 | 3 | betastaking.aleo, credits.aleo | 9 |
| `betastaker_2.aleo` | 14 | staking/liquid staking | 9 | 3 | betastaking.aleo, credits.aleo | 9 |
| `betastaker_4.aleo` | 14 | staking/liquid staking | 9 | 3 | betastaking.aleo, credits.aleo | 9 |
| `aj_usdcx_stablecoin_2_10.aleo` | 13 | token/credit flow | 9 | 0 | usdcx_stablecoin.aleo | 9 |
| `ans_registrar_usd2.aleo` | 13 | application/other | 10 | 2 | aleo_name_service_registry.aleo, ans_coupon_card.aleo, credits.aleo | 10 |
| `delegator3.aleo` | 13 | staking/liquid staking | 9 | 3 | credits.aleo, validator_oracle.aleo | 9 |
| `delegator4.aleo` | 12 | staking/liquid staking | 9 | 3 | credits.aleo, validator_oracle.aleo | 9 |
| `vlink_token_service_cd_v3.aleo` | 12 | bridge/cross-chain | 16 | 9 | credits.aleo, vlink_holding_cd_v3.aleo, vlink_token_bridge_v3.aleo | 16 |
| `delegator2.aleo` | 12 | staking/liquid staking | 9 | 3 | credits.aleo, validator_oracle.aleo | 9 |
| `delegator1.aleo` | 12 | staking/liquid staking | 9 | 3 | credits.aleo, validator_oracle.aleo | 9 |
| `delegator5.aleo` | 12 | staking/liquid staking | 9 | 3 | credits.aleo, validator_oracle.aleo | 9 |
| `aj_usad_stablecoin_2_10.aleo` | 10 | token/credit flow | 9 | 0 | usad_stablecoin.aleo | 9 |
| `betastaking_ext.aleo` | 10 | staking/liquid staking | 1 | 0 | betastaking.aleo | 1 |
| `hyp_mailbox.aleo` | 10 | bridge/cross-chain | 10 | 8 | hyp_ism_manager.aleo, hyp_multisig_core.aleo | 9 |
| `validator_oracle.aleo` | 10 | staking/liquid staking | 15 | 9 | credits.aleo | 15 |
| `arcn_puc_in_helper_swap_v2_2_5.aleo` | 9 | DeFi pool/lending | 2 | 0 | arcn_access_manager_v1.aleo, arcn_pool_v2_2_2.aleo, credits.aleo, token_registry.aleo, wrapped_credits.aleo | 2 |
| `hyp_ism_manager.aleo` | 9 | bridge/cross-chain | 7 | 8 | hyp_multisig_core.aleo | 7 |
| `puzzle_capital_multisig.aleo` | 8 | application/other | 13 | 6 | - | 12 |
| `vlink_token_service_v3.aleo` | 7 | bridge/cross-chain | 23 | 17 | token_registry.aleo, vlink_holding_v3.aleo, vlink_token_bridge_v3.aleo | 23 |
| `usdcx_bridge.aleo` | 7 | bridge/cross-chain | 9 | 4 | usdcx_freezelist.aleo, usdcx_multisig_core.aleo, usdcx_stablecoin.aleo | 8 |
| `vlink_holding_cd_v3.aleo` | 6 | bridge/cross-chain | 4 | 2 | credits.aleo | 4 |
| `puzzle_capital_pool.aleo` | 6 | DeFi pool/lending | 25 | 31 | credits.aleo, puzzle_capital_multisig.aleo | 25 |
| `certchain_equity_v1.aleo` | 5 | application/other | 7 | 8 | - | 7 |
| `vlink_holding_v3.aleo` | 4 | bridge/cross-chain | 5 | 2 | token_registry.aleo | 5 |
| `pubpriv_router_credits_v3.aleo` | 3 | token/credit flow | 2 | 0 | credits.aleo | 2 |
| `shield_wallet_promo_ethdenver.aleo` | 3 | application/other | 3 | 1 | credits.aleo | 3 |
| `hyp_warp_token_sol.aleo` | 2 | bridge/cross-chain | 11 | 4 | hyp_dispatch_proxy.aleo, hyp_mailbox.aleo, hyp_multisig_core.aleo, token_registry.aleo | 10 |
| `hyp_hook_manager.aleo` | 2 | bridge/cross-chain | 9 | 11 | credits.aleo, hyp_mailbox.aleo, hyp_multisig_core.aleo | 9 |
| `lsp_host_ui_v1.aleo` | 2 | application/other | 12 | 4 | credits.aleo, lsp_host_bank_v1.aleo | 12 |
| `hyp_warp_token_usdt.aleo` | 2 | bridge/cross-chain | 11 | 4 | hyp_dispatch_proxy.aleo, hyp_mailbox.aleo, hyp_multisig_core.aleo, token_registry.aleo | 10 |
| `arcn_puc_in_helper_v2_2_4.aleo` | 2 | DeFi pool/lending | 4 | 0 | arcn_compliance_v1.aleo, arcn_pool_v2_2_2.aleo, credits.aleo, token_registry.aleo, wrapped_credits.aleo | 4 |
| `hyp_warp_token_usdc.aleo` | 2 | bridge/cross-chain | 12 | 4 | hyp_dispatch_proxy.aleo, hyp_mailbox.aleo, hyp_multisig_core.aleo, token_registry.aleo | 11 |
| `hyp_warp_token_usad.aleo` | 2 | bridge/cross-chain | 10 | 4 | hyp_dispatch_proxy.aleo, hyp_mailbox.aleo, hyp_multisig_core.aleo, usad_freezelist.aleo, usad_stablecoin.aleo | 9 |
| `phantom_mint.aleo` | 1 | NFT/game asset | 1 | 0 | - | 1 |
| `lsp_host_bank_v1.aleo` | 1 | application/other | 7 | 2 | credits.aleo | 7 |
| `puzzle_proving_partner.aleo` | 1 | application/other | 14 | 9 | credits.aleo, puzzle_capital_multisig.aleo | 14 |
| `hyp_warp_token_wbtc.aleo` | 1 | bridge/cross-chain | 11 | 4 | hyp_dispatch_proxy.aleo, hyp_mailbox.aleo, hyp_multisig_core.aleo, token_registry.aleo | 10 |
| `hyp_warp_token_eth.aleo` | 1 | bridge/cross-chain | 11 | 4 | hyp_dispatch_proxy.aleo, hyp_mailbox.aleo, hyp_multisig_core.aleo, token_registry.aleo | 10 |
| `arcn_credits_in_helper_v2_2_3.aleo` | 1 | token/credit flow | 4 | 0 | arcn_compliance_v1.aleo, arcn_pool_v2_2_2.aleo, credits.aleo, token_registry.aleo, wrapped_credits.aleo | 4 |
| `victim_vault.aleo` | 1 | application/other | 1 | 0 | credits.aleo | 1 |
| `hyp_dispatch_proxy.aleo` | 1 | bridge/cross-chain | 2 | 0 | hyp_hook_manager.aleo, hyp_mailbox.aleo, hyp_multisig_core.aleo | 1 |
| `whalepool_puzzlecapital.aleo` | 1 | staking/liquid staking | 12 | 10 | credits.aleo, puzzle_capital_multisig.aleo | 12 |
| `autojoin_token_registry_2_9.aleo` | 1 | token/credit flow | 8 | 0 | token_registry.aleo | 8 |
| `par_store_v1.aleo` | 1 | application/other | 9 | 0 | par_store_inventory_v1.aleo, puzzle_arcade_ticket_v002.aleo | 9 |

## testnet

- Programs collected: 37
- Metric-window calls represented: 41503
- Download failures: 0

| Program | Calls | Class | Functions | Mappings | Cross refs | Async/conditional paths |
|---|---:|---|---:|---:|---|---:|
| `credits.aleo` | 22343 | token/credit flow | 15 | 8 | - | 12 |
| `dara_dp_credit_v5.aleo` | 4380 | DeFi pool/lending | 17 | 23 | credits.aleo, test_usdcx_stablecoin.aleo | 16 |
| `dara_dp_sol_v5.aleo` | 4371 | DeFi pool/lending | 17 | 23 | test_sol_v1.aleo, test_usdcx_stablecoin.aleo | 16 |
| `dara_dp_eth_v5.aleo` | 4367 | DeFi pool/lending | 17 | 23 | test_eth_v1.aleo, test_usdcx_stablecoin.aleo | 16 |
| `dara_dp_btc_v5.aleo` | 4363 | DeFi pool/lending | 17 | 23 | test_btc_v1.aleo, test_usdcx_stablecoin.aleo | 16 |
| `dara_lend_v8.aleo` | 488 | DeFi pool/lending | 12 | 20 | credits.aleo, test_usad_stablecoin.aleo, test_usdcx_stablecoin.aleo | 12 |
| `dara_lend_v8_credits.aleo` | 323 | token/credit flow | 12 | 12 | credits.aleo, test_usad_stablecoin.aleo, test_usdcx_stablecoin.aleo | 12 |
| `dara_flash_v1.aleo` | 262 | DeFi pool/lending | 11 | 11 | credits.aleo, test_usdcx_stablecoin.aleo | 11 |
| `autojoin_credits_2_10.aleo` | 143 | token/credit flow | 9 | 0 | credits.aleo | 9 |
| `loyalty_token.aleo` | 100 | token/credit flow | 8 | 4 | - | 7 |
| `test_usdcx_stablecoin.aleo` | 87 | token/credit flow | 22 | 5 | test_usdcx_freezelist.aleo, test_usdcx_multisig_core.aleo | 19 |
| `note_server_messagingv4.aleo` | 83 | application/other | 6 | 0 | - | 6 |
| `loyalty_rewards.aleo` | 32 | application/other | 5 | 4 | loyalty_token.aleo | 4 |
| `autojoin_credits_15_16.aleo` | 29 | token/credit flow | 2 | 0 | credits.aleo | 2 |
| `test_usad_stablecoin.aleo` | 24 | token/credit flow | 22 | 5 | test_usad_freezelist.aleo, test_usad_multisig_core.aleo | 19 |
| `test_usdcx_bridge.aleo` | 22 | bridge/cross-chain | 9 | 5 | test_usdcx_freezelist.aleo, test_usdcx_multisig_core.aleo, test_usdcx_stablecoin.aleo | 8 |
| `token_registry.aleo` | 14 | token/credit flow | 22 | 5 | - | 22 |
| `ldgbatcher_ppub_28.aleo` | 11 | application/other | 7 | 0 | credits.aleo | 7 |
| `aj_test_usdcx_stablecoin_2_10.aleo` | 9 | token/credit flow | 9 | 0 | test_usdcx_stablecoin.aleo | 9 |
| `ldgbatcher_p28.aleo` | 7 | application/other | 7 | 0 | credits.aleo | 1 |
| `f89b0d41ebe03707fd1f37ef95255ac.aleo` | 7 | application/other | 6 | 10 | - | 6 |
| `ldgbatcher_ppub_1114.aleo` | 5 | application/other | 4 | 0 | credits.aleo | 4 |
| `xyra_lending_v32.aleo` | 5 | DeFi pool/lending | 22 | 26 | credits.aleo, test_usad_stablecoin.aleo, test_usdcx_stablecoin.aleo | 22 |
| `humanity_link_aid_v9d.aleo` | 4 | application/other | 18 | 13 | test_usdcx_stablecoin.aleo | 18 |
| `zk_pay_proofs_privacy_v29.aleo` | 3 | application/other | 13 | 2 | credits.aleo, test_usad_stablecoin.aleo, test_usdcx_stablecoin.aleo | 13 |
| `aj_test_usad_stablecoin_2_10.aleo` | 3 | token/credit flow | 9 | 0 | test_usad_stablecoin.aleo | 9 |
| `zk_pay_proofs_privacy_wallet_v6.aleo` | 2 | application/other | 12 | 1 | credits.aleo, test_usad_stablecoin.aleo, test_usdcx_stablecoin.aleo | 8 |
| `cryptsign_v4.aleo` | 2 | application/other | 1 | 0 | - | 1 |
| `test_hyp_ism_manager.aleo` | 2 | bridge/cross-chain | 7 | 8 | test_hyp_multisig_core.aleo | 7 |
| `test_hyp_mailbox.aleo` | 2 | bridge/cross-chain | 10 | 8 | test_hyp_ism_manager.aleo, test_hyp_multisig_core.aleo | 9 |
| `test_hyp_warp_token_usad.aleo` | 2 | bridge/cross-chain | 10 | 4 | test_hyp_dispatch_proxy.aleo, test_hyp_mailbox.aleo, test_hyp_multisig_core.aleo, test_usad_freezelist.aleo, test_usad_stablecoin.aleo | 9 |
| `woo_genesis_1988.aleo` | 2 | application/other | 16 | 8 | credits.aleo | 16 |
| `wrapped_credits.aleo` | 2 | token/credit flow | 5 | 0 | credits.aleo, token_registry.aleo | 5 |
| `autojoin_token_registry_2_9.aleo` | 1 | token/credit flow | 8 | 0 | token_registry.aleo | 8 |
| `ldgbatcher_p910.aleo` | 1 | application/other | 2 | 0 | credits.aleo | 1 |
| `toka_token.aleo` | 1 | token/credit flow | 8 | 2 | - | 8 |
| `ldgbatcher_p1114.aleo` | 1 | application/other | 4 | 0 | credits.aleo | 1 |
