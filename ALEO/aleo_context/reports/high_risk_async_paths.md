# Async, delayed, conditional, bridge/proof-sensitive paths

Selection criteria: `async`, `finalize`, `.future`, `block.height`, branches/assertions/ternaries, `snark.verify`, or names indicating bridge/oracle/staking/token economic paths.

## mainnet
### `credits.aleo` (64268 calls, token/credit flow)
State mappings: `committee`, `delegated`, `metadata`, `bonded`, `unbonding`, `account`, `withdraw`, `pool`
- `bond_validator`: async, finalize
- `bond_public`: async, finalize
- `unbond_public`: async, finalize, block.height delay
- `claim_unbond_public`: async, finalize, block.height delay
- `set_validator_state`: async, finalize
- `transfer_public`: async, finalize
- `transfer_public_as_signer`: async, finalize
- `transfer_private_to_public`: async, finalize
- `transfer_public_to_private`: async, finalize
- `fee_private`: conditional
- `fee_public`: async, finalize
- `upgrade`: async, finalize

### `puzzle_arcade_coin_v002.aleo` (12992 calls, NFT/game asset)
- `mint`: conditional
- `spend`: conditional

### `puzzle_arcade_ticket_v002.aleo` (5487 calls, NFT/game asset)
State mappings: `registry`
- `add_program_to_registry`: async, finalize
- `mint`: async, finalize
- `spend`: conditional
- `join`: conditional
- `join3`: conditional
- `join4`: conditional
- `join5`: conditional

### `par_giveaways_v1.aleo` (2160 calls, application/other)
Cross-contract refs: `puzzle_arcade_ticket_v002.aleo`
State mappings: `is_open`, `max_entries`, `entries`, `user_entries`, `total_entries`, `winners`, `has_won`, `total_winners`
- `open`: async, finalize
- `close`: async, finalize
- `draw_winner`: async, finalize
- `buy_one_entry`: async, finalize, cross-contract
- `buy_two_entries`: async, finalize, cross-contract
- `buy_three_entries`: async, finalize, cross-contract
- `buy_four_entries`: async, finalize, cross-contract
- `buy_five_entries`: async, finalize, cross-contract
- `buy_six_entries`: async, finalize, cross-contract
- `buy_seven_entries`: async, finalize, cross-contract
- `buy_eight_entries`: async, finalize, cross-contract
- `buy_nine_entries`: async, finalize, cross-contract
- `buy_ten_entries`: async, finalize, cross-contract

### `puzzle_spinner_v003.aleo` (1961 calls, application/other)
Cross-contract refs: `puzzle_arcade_coin_v002.aleo`, `puzzle_arcade_ticket_v002.aleo`
State mappings: `used_nonces`
- `spin`: async, finalize, cross-contract

### `mystery_city_v001.aleo` (1065 calls, application/other)
Cross-contract refs: `puzzle_arcade_coin_v002.aleo`, `puzzle_arcade_ticket_v002.aleo`
State mappings: `used_nonces`
- `submit_game`: async, finalize, cross-contract

### `token_registry.aleo` (1008 calls, token/credit flow)
State mappings: `registered_tokens`, `balances`, `authorized_balances`, `allowances`, `roles`
- `transfer_public`: async, finalize, block.height delay
- `transfer_public_as_signer`: async, finalize, block.height delay
- `transfer_private`: async, finalize, block.height delay
- `transfer_private_to_public`: async, finalize, block.height delay
- `transfer_public_to_private`: async, finalize, block.height delay
- `join`: conditional
- `split`: conditional
- `initialize`: async, finalize
- `register_token`: async, finalize
- `update_token_management`: async, finalize
- `set_role`: async, finalize
- `remove_role`: async, finalize
- `mint_public`: async, finalize
- `mint_private`: async, finalize
- `burn_public`: async, finalize
- `burn_private`: async, finalize
- `prehook_public`: async, finalize, block.height delay
- `prehook_private`: async, finalize
- `approve_public`: async, finalize
- `unapprove_public`: async, finalize
- `transfer_from_public`: async, finalize, block.height delay
- `transfer_from_public_to_private`: async, finalize, block.height delay

### `whalepool_easystaking_v2.aleo` (831 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`
State mappings: `recharger`, `scope_check`, `bonding_limit`, `un_bonding_limit`, `bonded`, `unbonding`, `totals`, `pool_info`
- `initialize`: async, finalize, cross-contract
- `bond_recharger`: async, finalize, cross-contract
- `set_recharger`: async, finalize
- `set_scope_check`: async, finalize
- `set_pool_state`: async, finalize
- `bond_public`: async, finalize, cross-contract
- `unbond_public`: async, finalize, block.height delay, cross-contract
- `unbond_pos_rewards`: async, finalize, cross-contract
- `claim_unbond_public`: async, finalize, block.height delay, cross-contract
- `transfer_public`: async, finalize, cross-contract
- `fallback_unbond_if_removed`: async, finalize, block.height delay

### `arcn_pool_v2_2_2.aleo` (299 calls, DeFi pool/lending)
Cross-contract refs: `arcn_access_manager_v1.aleo`, `arcn_whitelist.aleo`, `token_registry.aleo`
State mappings: `amm_pools`, `amm_deposits`, `amm_extras`, `protocol_fee`, `accrued_protocol_fees`, `whitelisted_fee_tiers`
- `initialize`: async, finalize
- `set_protocol_fee_public`: async, finalize, cross-contract
- `set_fee_whitelist_public`: async, finalize, cross-contract
- `withdraw_protocol_fee`: async, finalize, cross-contract
- `create_pool`: async, finalize, cross-contract
- `transfer_lp_receipt_by_salt`: async, finalize
- `add_amm_liquidity`: async, finalize, cross-contract
- `remove_amm_liquidity_part`: async, finalize, cross-contract
- `swap_amm`: async, finalize, cross-contract
- `redeem_voucher`: async, finalize, cross-contract
- `swap_stable`: async, finalize, cross-contract

### `whalepool_easystaking_v3.aleo` (255 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`
State mappings: `scope_check`, `bonding_limit`, `un_bonding_limit`, `bonded`, `unbonding`, `totals`, `pool_info`, `employee__`
- `transfer_public`: async, finalize, cross-contract
- `claim_unbond_public`: async, finalize, block.height delay, cross-contract
- `unbond_public`: async, finalize, block.height delay, cross-contract
- `unbond_pos_rewards`: async, finalize, cross-contract
- `admin_change_validator_stake`: async, finalize, cross-contract
- `admin_unbond_credits`: async, finalize, cross-contract
- `bond_public`: async, finalize, cross-contract
- `set_scope_check`: async, finalize
- `set_pool_state`: async, finalize
- `set_employee`: async, finalize
- `initialize`: async, finalize, cross-contract

### `betastaking.aleo` (185 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`
State mappings: `account`, `approvals`, `metadata`, `state`, `settings`, `unstakings`, `admins`, `stakers`
- `transfer_public`: async, finalize
- `transfer_private_to_public`: async, finalize
- `transfer_public_to_private`: async, finalize
- `stake_public`: async, finalize, cross-contract
- `stake_private`: async, finalize, cross-contract
- `unstake_token`: async, finalize, block.height delay
- `unstake_aleo`: async, finalize, block.height delay
- `withdraw`: async, finalize, block.height delay, cross-contract
- `withdraw_private`: async, finalize, block.height delay, cross-contract
- `approve_public`: async, finalize
- `unapprove_public`: async, finalize
- `transfer_from_public`: async, finalize
- `notify_reward`: async, finalize
- `pull_aleo`: async, finalize, cross-contract
- `update_settings`: async, finalize
- `set_staker`: async, finalize
- `set_admin`: async, finalize
- `init`: async, finalize

### `arcn_whitelist.aleo` (181 calls, DeFi pool/lending)
Cross-contract refs: `arcn_access_manager_v1.aleo`
State mappings: `whitelist`, `settings`
- `initialize`: async, finalize
- `whitelist_caller`: async, finalize, cross-contract
- `toggle_whitelist`: async, finalize, cross-contract
- `is_caller_eligible`: async, finalize

### `zkwork_staker_v1.aleo` (148 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`, `withdrawaler.aleo`, `zkwork_staking.aleo`
State mappings: `state`
- `bond`: async, finalize, cross-contract
- `notify_reward`: async, finalize, cross-contract
- `withdraw_puzzle`: async, finalize, cross-contract
- `init`: async, finalize

### `pondo_protocol.aleo` (147 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`, `delegator1.aleo`, `delegator2.aleo`, `delegator3.aleo`, `delegator4.aleo`, `delegator5.aleo`, `paleo_token.aleo`, `pondo_protocol_token.aleo`, `token_registry.aleo`, `validator_oracle.aleo`, `wrapped_credits.aleo`
State mappings: `validator_set`, `protocol_state`, `balances`, `owed_commission`, `last_rebalance_epoch`, `withdrawals`
- `initialize`: async, finalize, block.height delay, cross-contract
- `prep_rebalance`: async, finalize, block.height delay, cross-contract
- `deposit_public_as_signer`: async, finalize, cross-contract
- `deposit_public`: async, finalize, cross-contract
- `distribute_deposits`: async, finalize, cross-contract
- `instant_withdraw_public`: async, finalize, cross-contract
- `instant_withdraw_public_signer`: async, finalize, cross-contract
- `withdraw_public`: async, finalize, block.height delay, cross-contract
- `withdraw_public_as_signer`: async, finalize, block.height delay, cross-contract
- `claim_withdrawal_public`: async, finalize, block.height delay, cross-contract
- `rebalance_retrieve_credits`: async, finalize, cross-contract
- `rebalance_redistribute`: async, finalize, cross-contract
- `set_oracle_tvl`: async, finalize, block.height delay, cross-contract

### `arcn_compliance_v1.aleo` (146 calls, DeFi pool/lending)
- `report`: conditional
- `report_voucher`: conditional

### `zkwork_staking.aleo` (137 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`
State mappings: `account`, `approvals`, `metadata`, `state`, `settings`, `unstakings`, `admins`, `stakers`
- `stake_public`: async, finalize, cross-contract
- `stake_private`: async, finalize, cross-contract
- `unstake_token`: async, finalize, block.height delay
- `unstake_aleo`: async, finalize, block.height delay
- `withdraw`: async, finalize, block.height delay, cross-contract
- `withdraw_private`: async, finalize, block.height delay, cross-contract
- `transfer_public`: async, finalize
- `transfer_public_to_private`: async, finalize
- `transfer_private_to_public`: async, finalize
- `approve_public`: async, finalize
- `unapprove_public`: async, finalize
- `transfer_from_public`: async, finalize
- `notify_reward`: async, finalize
- `pull_aleo`: async, finalize, cross-contract
- `update_settings`: async, finalize
- `set_staker`: async, finalize
- `set_admin`: async, finalize
- `init`: async, finalize

### `squash_v4.aleo` (116 calls, application/other)
Cross-contract refs: `puzzle_arcade_coin_v002.aleo`, `puzzle_arcade_ticket_v002.aleo`, `squash_v3.aleo`
State mappings: `day_start`
- `mint`: async, finalize, cross-contract
- `water`: async, finalize
- `water_and_level_up`: async, finalize, cross-contract
- `set_day_start`: async, finalize
- `migrate_from_v3`: cross-contract
- `mint_arbitrary_squash`: async, finalize

### `autojoin_credits_2_10.aleo` (97 calls, token/credit flow)
Cross-contract refs: `credits.aleo`
- `join_2`: cross-contract
- `join_3`: cross-contract
- `join_4`: cross-contract
- `join_5`: cross-contract
- `join_6`: cross-contract
- `join_7`: cross-contract
- `join_8`: cross-contract
- `join_9`: cross-contract
- `join_10`: cross-contract

### `connection_v1.aleo` (90 calls, bridge/cross-chain)
Cross-contract refs: `credits.aleo`, `gmp_checksum_v1.aleo`, `gmp_lib_v1.aleo`
State mappings: `already_processed`, `chain_id`, `owner_conn`, `total_validators`, `validators`, `threshold`, `messages`
- `initialize`: async, finalize, cross-contract
- `send_message`: async, finalize, cross-contract
- `verify_message`: async, finalize, cross-contract
- `update_validators`: async, finalize, cross-contract
- `update_threshold`: async, finalize
- `transfer_ownership`: async, finalize
- `withdraw`: async, finalize, cross-contract

### `par_store_inventory_v1.aleo` (88 calls, application/other)
State mappings: `sku_prices`, `sku_stock`
- `set_sku_price`: async, finalize
- `mint`: async, finalize
- `validate_purchase`: async, finalize
- `fulfill`: conditional
- `shutdown`: async, finalize

### `asset_manager_helper_v1.aleo` (86 calls, application/other)
Cross-contract refs: `gmp_checksum_v1.aleo`, `gmp_lib_v1.aleo`
State mappings: `owner_amh`, `hub_chain_id`, `hub_am_address`
- `initialize`: async, finalize
- `transfer_message_external`: async, finalize, cross-contract
- `recv_message_external`: async, finalize, cross-contract

### `asset_manager_core_v1.aleo` (86 calls, application/other)
Cross-contract refs: `asset_manager_helper_v1.aleo`, `connection_v1.aleo`, `credits.aleo`, `gmp_checksum_v1.aleo`, `gmp_lib_v1.aleo`, `rate_limit_v1.aleo`, `token_registry.aleo`
State mappings: `gmp_payload`
- `transfer_native_public`: async, finalize, cross-contract
- `transfer_token_public`: async, finalize, cross-contract
- `recv_message`: async, finalize, cross-contract

### `wrapped_credits.aleo` (83 calls, token/credit flow)
Cross-contract refs: `credits.aleo`, `token_registry.aleo`
- `deposit_credits_public_signer`: async, finalize, cross-contract
- `deposit_credits_private`: async, finalize, cross-contract
- `withdraw_credits_public`: async, finalize, cross-contract
- `withdraw_credits_public_signer`: async, finalize, cross-contract
- `withdraw_credits_private`: async, finalize, cross-contract

### `arcn_pub_v2_2_3.aleo` (79 calls, DeFi pool/lending)
Cross-contract refs: `arcn_compliance_v1.aleo`, `arcn_pool_v2_2_2.aleo`, `token_registry.aleo`
- `create_pool`: async, finalize, cross-contract
- `swap_amm`: async, finalize, cross-contract
- `redeem_voucher`: async, finalize, cross-contract
- `swap_stable`: async, finalize, cross-contract
- `add_amm_liq`: async, finalize, cross-contract
- `remove_amm_liq_part`: async, finalize, cross-contract

### `arcn_priv_v2_2_3.aleo` (64 calls, DeFi pool/lending)
Cross-contract refs: `arcn_compliance_v1.aleo`, `arcn_pool_v2_2_2.aleo`, `token_registry.aleo`
- `create_pool`: async, finalize, cross-contract
- `swap_amm`: async, finalize, cross-contract
- `redeem_voucher`: async, finalize, cross-contract
- `swap_stable`: async, finalize, cross-contract
- `add_amm_liq`: async, finalize, cross-contract
- `remove_amm_liq_part`: async, finalize, cross-contract

### `usdcx_stablecoin.aleo` (62 calls, token/credit flow)
Cross-contract refs: `usdcx_freezelist.aleo`, `usdcx_multisig_core.aleo`
State mappings: `token_info`, `balances`, `allowances`, `address_to_role`, `pause`
- `update_role`: async, finalize
- `initialize`: async, finalize
- `get_credentials`: async, finalize, block.height delay
- `mint_public`: async, finalize
- `mint_private`: async, finalize
- `burn_public`: async, finalize
- `burn_private`: async, finalize
- `transfer_public`: async, finalize
- `transfer_public_as_signer`: async, finalize
- `approve_public`: async, finalize
- `unapprove_public`: async, finalize
- `transfer_from_public`: async, finalize
- `transfer_public_to_private`: async, finalize
- `transfer_from_public_to_private`: async, finalize
- `transfer_private`: async, finalize, block.height delay
- `transfer_private_to_public`: async, finalize, block.height delay
- `set_pause_status`: async, finalize
- `transfer_private_with_creds`: async, finalize, block.height delay

### `usad_stablecoin.aleo` (58 calls, token/credit flow)
Cross-contract refs: `usad_freezelist.aleo`, `usad_multisig_core.aleo`
State mappings: `token_info`, `balances`, `allowances`, `address_to_role`, `pause`
- `update_role`: async, finalize
- `initialize`: async, finalize
- `get_credentials`: async, finalize, block.height delay
- `mint_public`: async, finalize
- `mint_private`: async, finalize
- `burn_public`: async, finalize
- `burn_private`: async, finalize
- `transfer_public`: async, finalize
- `transfer_public_as_signer`: async, finalize
- `approve_public`: async, finalize
- `unapprove_public`: async, finalize
- `transfer_from_public`: async, finalize
- `transfer_public_to_private`: async, finalize
- `transfer_from_public_to_private`: async, finalize
- `transfer_private`: async, finalize, block.height delay
- `transfer_private_to_public`: async, finalize, block.height delay
- `set_pause_status`: async, finalize
- `transfer_private_with_creds`: async, finalize, block.height delay

### `rate_limit_v1.aleo` (43 calls, oracle/governance guard)
Cross-contract refs: `gmp_checksum_v1.aleo`
State mappings: `owner_rate_limit`, `asset_manager_core`, `pause_status`, `token_config`
- `initialize`: async, finalize
- `set_asset_manager`: async, finalize
- `pause`: async, finalize
- `unpause`: async, finalize
- `set_rate_limit`: async, finalize
- `reset_rate_limit`: async, finalize
- `verify_withdraw`: async, finalize
- `transfer_ownership`: async, finalize

### `gmp_lib_v1.aleo` (43 calls, bridge/cross-chain)
- `u128_to_bytes32`: async, finalize

### `mining_jouny_test_v2.aleo` (31 calls, application/other)
Cross-contract refs: `credits.aleo`
State mappings: `scope_check`, `bonding_limit`, `un_bonding_limit`, `bonded`, `unbonding`, `totals`, `pool_info`, `employee__`
- `transfer_public`: async, finalize, cross-contract
- `claim_unbond_public`: async, finalize, block.height delay, cross-contract
- `unbond_public`: async, finalize, block.height delay, cross-contract
- `unbond_pos_rewards`: async, finalize, cross-contract
- `admin_change_validator_stake`: async, finalize, cross-contract
- `admin_unbond_credits`: async, finalize, cross-contract
- `bond_public`: async, finalize, cross-contract
- `set_scope_check`: async, finalize
- `set_pool_state`: async, finalize
- `set_employee`: async, finalize
- `initialize`: async, finalize, cross-contract

### `arcn_puc_out_helper_swap_v2_2_6.aleo` (26 calls, DeFi pool/lending)
Cross-contract refs: `arcn_access_manager_v1.aleo`, `arcn_pool_v2_2_2.aleo`, `credits.aleo`, `token_registry.aleo`, `wrapped_credits.aleo`
- `withdraw_protocol_fee`: async, finalize, cross-contract
- `swap_amm_credits_out`: async, finalize, cross-contract

### `withdrawaler.aleo` (20 calls, application/other)
Cross-contract refs: `credits.aleo`
State mappings: `admins`, `operators`, `miners`, `state`
- `unbond`: async, finalize, cross-contract
- `claim`: async, finalize, cross-contract
- `push_aleo`: async, finalize, cross-contract
- `claim_and_push`: async, finalize, cross-contract
- `set_operator`: async, finalize
- `set_admin`: async, finalize
- `set_miner`: async, finalize
- `init`: async, finalize

### `vlink_token_bridge_v3.aleo` (19 calls, bridge/cross-chain)
State mappings: `bridge_settings`, `owner_TB`, `attestors`, `in_packet_consumed`, `out_packets`, `supported_chains`, `supported_services`, `sequences`
- `initialize_tb`: async, finalize
- `migrate_eth_seq`: async, finalize
- `transfer_ownership_tb`: async, finalize
- `add_attestor_tb`: async, finalize
- `remove_attestor_tb`: async, finalize
- `update_threshold_tb`: async, finalize
- `add_chain_tb`: async, finalize
- `remove_chain_tb`: async, finalize
- `add_service_tb`: async, finalize
- `remove_service_tb`: async, finalize
- `pause_tb`: async, finalize
- `unpause_tb`: async, finalize
- `publish`: async, finalize, block.height delay
- `consume`: async, finalize

### `betastaker_1.aleo` (18 calls, staking/liquid staking)
Cross-contract refs: `betastaking.aleo`, `credits.aleo`
State mappings: `admins`, `operators`, `state`
- `notify_reward`: async, finalize, cross-contract
- `set_admin`: async, finalize
- `init`: async, finalize
- `bond`: async, finalize, cross-contract
- `unbond`: async, finalize, cross-contract
- `claim`: async, finalize, cross-contract
- `push_aleo`: async, finalize, cross-contract
- `claim_and_push`: async, finalize, cross-contract
- `set_operator`: async, finalize

### `betastaker_3.aleo` (16 calls, staking/liquid staking)
Cross-contract refs: `betastaking.aleo`, `credits.aleo`
State mappings: `admins`, `operators`, `state`
- `notify_reward`: async, finalize, cross-contract
- `set_admin`: async, finalize
- `init`: async, finalize
- `bond`: async, finalize, cross-contract
- `unbond`: async, finalize, cross-contract
- `claim`: async, finalize, cross-contract
- `push_aleo`: async, finalize, cross-contract
- `claim_and_push`: async, finalize, cross-contract
- `set_operator`: async, finalize

### `betastaker_2.aleo` (14 calls, staking/liquid staking)
Cross-contract refs: `betastaking.aleo`, `credits.aleo`
State mappings: `admins`, `operators`, `state`
- `notify_reward`: async, finalize, cross-contract
- `set_admin`: async, finalize
- `init`: async, finalize
- `bond`: async, finalize, cross-contract
- `unbond`: async, finalize, cross-contract
- `claim`: async, finalize, cross-contract
- `push_aleo`: async, finalize, cross-contract
- `claim_and_push`: async, finalize, cross-contract
- `set_operator`: async, finalize

### `betastaker_4.aleo` (14 calls, staking/liquid staking)
Cross-contract refs: `betastaking.aleo`, `credits.aleo`
State mappings: `admins`, `operators`, `state`
- `notify_reward`: async, finalize, cross-contract
- `set_admin`: async, finalize
- `init`: async, finalize
- `bond`: async, finalize, cross-contract
- `unbond`: async, finalize, cross-contract
- `claim`: async, finalize, cross-contract
- `push_aleo`: async, finalize, cross-contract
- `claim_and_push`: async, finalize, cross-contract
- `set_operator`: async, finalize

### `aj_usdcx_stablecoin_2_10.aleo` (13 calls, token/credit flow)
Cross-contract refs: `usdcx_stablecoin.aleo`
- `join_2`: cross-contract
- `join_3`: cross-contract
- `join_4`: cross-contract
- `join_5`: cross-contract
- `join_6`: cross-contract
- `join_7`: cross-contract
- `join_8`: cross-contract
- `join_9`: cross-contract
- `join_10`: cross-contract

### `ans_registrar_usd2.aleo` (13 calls, application/other)
Cross-contract refs: `aleo_name_service_registry.aleo`, `ans_coupon_card.aleo`, `credits.aleo`
State mappings: `general_settings`, `price_data`
- `transfer_public`: async, finalize, cross-contract
- `initialize_registrar`: async, finalize
- `update_setting`: async, finalize
- `set_unit_price`: async, finalize
- `change_admin`: async, finalize
- `register_free`: async, finalize, cross-contract
- `register_fld`: async, finalize, cross-contract
- `register_fld_public`: async, finalize, cross-contract
- `register_fld_with_coupon`: async, finalize, cross-contract
- `register_fld_with_coupon_public`: async, finalize, cross-contract

### `delegator3.aleo` (13 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`, `validator_oracle.aleo`
State mappings: `state_mapping`, `validator_mapping`, `banned_validators`
- `initialize`: async, finalize
- `ban_validator`: async, finalize, cross-contract
- `prep_rebalance`: async, finalize
- `set_validator`: async, finalize
- `bond`: async, finalize, cross-contract
- `unbond`: async, finalize, cross-contract
- `terminal_state`: async, finalize
- `transfer_to_core_protocol`: async, finalize, cross-contract
- `bond_failed`: async, finalize

### `delegator4.aleo` (12 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`, `validator_oracle.aleo`
State mappings: `state_mapping`, `validator_mapping`, `banned_validators`
- `initialize`: async, finalize
- `ban_validator`: async, finalize, cross-contract
- `prep_rebalance`: async, finalize
- `set_validator`: async, finalize
- `bond`: async, finalize, cross-contract
- `unbond`: async, finalize, cross-contract
- `terminal_state`: async, finalize
- `transfer_to_core_protocol`: async, finalize, cross-contract
- `bond_failed`: async, finalize

### `vlink_token_service_cd_v3.aleo` (12 calls, bridge/cross-chain)
Cross-contract refs: `credits.aleo`, `vlink_holding_cd_v3.aleo`, `vlink_token_bridge_v3.aleo`
State mappings: `owner_TS`, `total_supply`, `min_transfers`, `max_transfers`, `status`, `token_holding`, `other_chain_token_service`, `other_chain_token_address`, `platform_fee`
- `initialize_ts`: async, finalize
- `transfer_ownership_ts`: async, finalize
- `update_other_chain_tokenservice`: async, finalize
- `update_other_chain_tokenaddress`: async, finalize
- `remove_other_chain_addresses`: async, finalize
- `add_token_info`: async, finalize
- `pause_token_ts`: async, finalize
- `unpause_token_ts`: async, finalize
- `update_min_transfer_ts`: async, finalize
- `update_max_transfer_ts`: async, finalize
- `token_send_public`: async, finalize, cross-contract
- `token_receive_public`: async, finalize, cross-contract
- `add_chain_to_existing_token`: async, finalize
- `holding_release`: async, finalize, cross-contract
- `holding_transfer_ownership`: async, finalize, cross-contract
- `update_fees`: async, finalize

### `delegator2.aleo` (12 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`, `validator_oracle.aleo`
State mappings: `state_mapping`, `validator_mapping`, `banned_validators`
- `initialize`: async, finalize
- `ban_validator`: async, finalize, cross-contract
- `prep_rebalance`: async, finalize
- `set_validator`: async, finalize
- `bond`: async, finalize, cross-contract
- `unbond`: async, finalize, cross-contract
- `terminal_state`: async, finalize
- `transfer_to_core_protocol`: async, finalize, cross-contract
- `bond_failed`: async, finalize

### `delegator1.aleo` (12 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`, `validator_oracle.aleo`
State mappings: `state_mapping`, `validator_mapping`, `banned_validators`
- `initialize`: async, finalize
- `ban_validator`: async, finalize, cross-contract
- `prep_rebalance`: async, finalize
- `set_validator`: async, finalize
- `bond`: async, finalize, cross-contract
- `unbond`: async, finalize, cross-contract
- `terminal_state`: async, finalize
- `transfer_to_core_protocol`: async, finalize, cross-contract
- `bond_failed`: async, finalize

### `delegator5.aleo` (12 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`, `validator_oracle.aleo`
State mappings: `state_mapping`, `validator_mapping`, `banned_validators`
- `initialize`: async, finalize
- `ban_validator`: async, finalize, cross-contract
- `prep_rebalance`: async, finalize
- `set_validator`: async, finalize
- `bond`: async, finalize, cross-contract
- `unbond`: async, finalize, cross-contract
- `terminal_state`: async, finalize
- `transfer_to_core_protocol`: async, finalize, cross-contract
- `bond_failed`: async, finalize

### `aj_usad_stablecoin_2_10.aleo` (10 calls, token/credit flow)
Cross-contract refs: `usad_stablecoin.aleo`
- `join_2`: cross-contract
- `join_3`: cross-contract
- `join_4`: cross-contract
- `join_5`: cross-contract
- `join_6`: cross-contract
- `join_7`: cross-contract
- `join_8`: cross-contract
- `join_9`: cross-contract
- `join_10`: cross-contract

### `betastaking_ext.aleo` (10 calls, staking/liquid staking)
Cross-contract refs: `betastaking.aleo`
- `stake`: async, finalize, cross-contract

### `hyp_mailbox.aleo` (10 calls, bridge/cross-chain)
Cross-contract refs: `hyp_ism_manager.aleo`, `hyp_multisig_core.aleo`
State mappings: `deliveries`, `dispatch_events`, `dispatch_id_events`, `process_events`, `mailbox`, `process_event_index`, `dispatch_event_index`, `registered_applications`
- `init`: async, finalize
- `set_dispatch_proxy`: async, finalize
- `set_owner`: async, finalize
- `set_default_ism`: async, finalize
- `set_default_hook`: async, finalize
- `set_required_hook`: async, finalize
- `register_application`: async, finalize
- `process`: async, finalize, block.height delay, cross-contract
- `dispatch`: async, finalize, block.height delay

### `validator_oracle.aleo` (10 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`
State mappings: `delegator_to_validator`, `validator_data`, `top_validators`, `banned_validators`, `pondo_tvl`, `validator_boosting`, `control_addresses`, `delegator_allocation`, `admin_operations`
- `initialize`: async, finalize
- `add_control_address`: async, finalize
- `remove_control_address`: async, finalize
- `update_admin`: async, finalize
- `update_delegator_allocations`: async, finalize
- `propose_delegator`: async, finalize
- `add_delegator`: async, finalize, block.height delay
- `update_data`: async, finalize, block.height delay
- `remove_delegator`: async, finalize, block.height delay
- `pondo_ban_validator`: async, finalize
- `ban_validator`: async, finalize, block.height delay
- `unban_validator`: async, finalize
- `set_pondo_tvl`: async, finalize
- `ban_self`: async, finalize
- `boost_validator`: async, finalize, block.height delay, cross-contract

### `arcn_puc_in_helper_swap_v2_2_5.aleo` (9 calls, DeFi pool/lending)
Cross-contract refs: `arcn_access_manager_v1.aleo`, `arcn_pool_v2_2_2.aleo`, `credits.aleo`, `token_registry.aleo`, `wrapped_credits.aleo`
- `withdraw_protocol_fee`: async, finalize, cross-contract
- `swap_amm_credits_in`: async, finalize, cross-contract

### `hyp_ism_manager.aleo` (9 calls, bridge/cross-chain)
Cross-contract refs: `hyp_multisig_core.aleo`
State mappings: `nonce`, `ism_addresses`, `isms`, `domain_routing_isms`, `routes`, `route_iter`, `route_length`, `message_id_multisigs`
- `init_noop`: async, finalize
- `init_message_id_multisig`: async, finalize
- `init_domain_routing`: async, finalize
- `set_domain`: async, finalize
- `remove_domain`: async, finalize
- `transfer_routing_ism_ownership`: async, finalize
- `verify`: async, finalize

### `puzzle_capital_multisig.aleo` (8 calls, application/other)
State mappings: `program_settings`, `wallets`, `signer_to_index`, `index_to_signer`, `signing_ops`, `completed_signing_ops`
- `create_wallet`: async, finalize
- `add_signer`: async, finalize
- `init_signing_op`: async, finalize, block.height delay
- `sign`: async, finalize
- `exec_signing_op`: async, finalize, block.height delay
- `update_threshold`: async, finalize
- `remove_signer`: async, finalize
- `verify_completed_op`: async, finalize
- `consume_signing_op`: async, finalize
- `emergency_exec_signing_op`: async, finalize
- `disallow_upgrades`: async, finalize
- `set_upgrader_address`: async, finalize

### `vlink_token_service_v3.aleo` (7 calls, bridge/cross-chain)
Cross-contract refs: `token_registry.aleo`, `vlink_holding_v3.aleo`, `vlink_token_bridge_v3.aleo`
State mappings: `owner_TS`, `total_supply`, `added_tokens`, `min_transfers`, `max_transfers`, `token_withdrawal_limits`, `token_snapshot_supply`, `token_snapshot_height`, `token_amount_withdrawn`, `token_status`, `token_holding`, `other_chain_token_service`, `other_chain_token_address`, `public_platform_fee`, `private_platform_fee`, `public_relayer_fee`, `private_relayer_fee`
- `initialize_ts`: async, finalize
- `migrate_previous_sysData`: async, finalize
- `transfer_ownership_ts`: async, finalize
- `update_other_chain_tokenservice`: async, finalize
- `update_other_chain_tokenaddress`: async, finalize
- `remove_other_chain_addresses`: async, finalize
- `add_token_ts`: async, finalize
- `remove_token_ts`: async, finalize
- `pause_token_ts`: async, finalize
- `unpause_token_ts`: async, finalize
- `update_min_transfer_ts`: async, finalize
- `update_max_transfer_ts`: async, finalize
- `update_withdrawal_limit`: async, finalize
- `token_send_public`: async, finalize, block.height delay, cross-contract
- `token_send_private`: async, finalize, block.height delay, cross-contract
- `token_receive_public`: async, finalize, cross-contract
- `token_receive_private`: async, finalize, cross-contract
- `add_chain_to_existing_token`: async, finalize
- `holding_release`: async, finalize, cross-contract
- `holding_release_private`: async, finalize, cross-contract
- `holding_transfer_ownership`: async, finalize, cross-contract
- `update_platform_fee`: async, finalize
- `update_relayer_fee`: async, finalize

### `usdcx_bridge.aleo` (7 calls, bridge/cross-chain)
Cross-contract refs: `usdcx_freezelist.aleo`, `usdcx_multisig_core.aleo`, `usdcx_stablecoin.aleo`
State mappings: `circle_attester`, `minimum_burn_amount`, `nullifier`, `paused`
- `mint_private`: async, finalize, block.height delay, cross-contract
- `mint_public`: async, finalize, cross-contract
- `burn`: async, finalize, cross-contract
- `burn_public`: async, finalize, cross-contract
- `set_pause_status`: async, finalize
- `set_circle_attester`: async, finalize
- `set_minimum_burn_amount`: async, finalize
- `address_to_bytes_raw`: cross-contract

### `vlink_holding_cd_v3.aleo` (6 calls, bridge/cross-chain)
Cross-contract refs: `credits.aleo`
State mappings: `holdings`, `owner_holding`
- `initialize_holding`: async, finalize
- `transfer_ownership_holding`: async, finalize
- `hold_fund`: async, finalize
- `release_fund`: async, finalize, cross-contract

### `puzzle_capital_pool.aleo` (6 calls, DeFi pool/lending)
Cross-contract refs: `credits.aleo`, `puzzle_capital_multisig.aleo`
State mappings: `deposits`, `total_deposited`, `depositor_count`, `deposit_block`, `current_epoch`, `epoch_commitments`, `epoch_total_rewards`, `epoch_fee_taken`, `epoch_restaked`, `epoch_start_block`, `epoch_payout_count`, `committed_depositor_count`, `bonded_snapshot`, `epoch_net_deposits`, `epoch_net_withdrawals`, `epoch_settling`, `last_epoch_block`, `auto_restake`, `claimable`, `is_depositor`, `pending_withdrawals`, `withdrawal_credits`, `epoch_depositor_paid`, `pool_config`, `validator_address`, `treasury`, `backup_address`, `address_to_role`, `initialized`, `max_reward_bps`, `skipped_depositors`
- `initialize`: async, finalize
- `deposit`: async, finalize, block.height delay, cross-contract
- `deposit_v2`: async, finalize, block.height delay, cross-contract
- `request_withdraw`: async, finalize, block.height delay, cross-contract
- `complete_withdraw`: async, finalize, cross-contract
- `set_auto_restake`: async, finalize
- `commit_epoch`: async, finalize, block.height delay
- `apply_epoch_rewards`: async, finalize, block.height delay
- `close_epoch`: async, finalize, block.height delay
- `restake_epoch`: async, finalize, cross-contract
- `withdraw_credits`: async, finalize, cross-contract
- `transfer_claimable`: async, finalize, cross-contract
- `emergency_unseal`: async, finalize
- `force_close_epoch`: async, finalize, block.height delay
- `propose_change_fee`: async, finalize, cross-contract
- `propose_change_validator`: async, finalize, cross-contract
- `propose_update_role`: async, finalize, cross-contract
- `propose_pause`: async, finalize, cross-contract
- `propose_change_max_reward_bps`: async, finalize, cross-contract
- `exec_change_fee`: async, finalize, cross-contract
- `exec_update_role`: async, finalize, cross-contract
- `exec_pause`: async, finalize, cross-contract
- `exec_change_validator`: async, finalize, cross-contract
- `exec_change_max_reward_bps`: async, finalize, cross-contract
- `get_signing_op_id_for_deploy`: cross-contract

### `certchain_equity_v1.aleo` (5 calls, application/other)
State mappings: `cert_exists`, `asset_total_shares`, `asset_admin`, `dividend_per_share`, `dividend_claimed`, `has_voted`, `votes_yes`, `votes_no`
- `register_admin`: async, finalize
- `mint`: async, finalize
- `split`: async, finalize
- `transfer`: conditional
- `declare_dividend`: async, finalize
- `claim_dividend`: async, finalize
- `vote`: async, finalize

### `vlink_holding_v3.aleo` (4 calls, bridge/cross-chain)
Cross-contract refs: `token_registry.aleo`
State mappings: `holdings`, `owner_holding`
- `initialize_holding`: async, finalize
- `transfer_ownership_holding`: async, finalize
- `hold_fund`: async, finalize
- `release_fund`: async, finalize, cross-contract
- `release_fund_private`: async, finalize, cross-contract

### `pubpriv_router_credits_v3.aleo` (3 calls, token/credit flow)
Cross-contract refs: `credits.aleo`
- `transfer_pub_priv_to_pub`: async, finalize, cross-contract
- `transfer_pub_priv_to_priv`: async, finalize, cross-contract

### `shield_wallet_promo_ethdenver.aleo` (3 calls, application/other)
Cross-contract refs: `credits.aleo`
State mappings: `spent`
- `redeem`: async, finalize, cross-contract
- `fund`: async, finalize, cross-contract
- `refund`: async, finalize, cross-contract

### `hyp_warp_token_sol.aleo` (2 calls, bridge/cross-chain)
Cross-contract refs: `hyp_dispatch_proxy.aleo`, `hyp_mailbox.aleo`, `hyp_multisig_core.aleo`, `token_registry.aleo`
State mappings: `remote_routers`, `remote_router_iter`, `remote_router_length`, `app_metadata`
- `init`: async, finalize, cross-contract
- `set_custom_hook`: async, finalize
- `set_custom_ism`: async, finalize
- `set_owner`: async, finalize
- `enroll_remote_router`: async, finalize
- `unroll_remote_router`: async, finalize
- `transfer_remote`: async, finalize, cross-contract
- `transfer_remote_with_hook`: async, finalize, cross-contract
- `process`: async, finalize, cross-contract
- `get_balance_key`: cross-contract

### `hyp_hook_manager.aleo` (2 calls, bridge/cross-chain)
Cross-contract refs: `credits.aleo`, `hyp_mailbox.aleo`, `hyp_multisig_core.aleo`
State mappings: `nonce`, `hooks`, `hook_addresses`, `igps`, `destination_gas_configs`, `destination_gas_config_iter`, `destination_gas_config_length`, `merkle_tree_hooks`, `gas_payment_events`, `inserted_into_tree_events`, `last_event_index`
- `init_noop`: async, finalize
- `init_igp`: async, finalize
- `set_destination_gas_config`: async, finalize
- `remove_destination_gas_config`: async, finalize
- `claim`: async, finalize, cross-contract
- `pay_for_gas`: async, finalize, block.height delay, cross-contract
- `transfer_igp_ownership`: async, finalize
- `init_merkle_tree`: async, finalize
- `post_dispatch`: async, finalize, block.height delay, cross-contract

### `lsp_host_ui_v1.aleo` (2 calls, application/other)
Cross-contract refs: `credits.aleo`, `lsp_host_bank_v1.aleo`
State mappings: `owned`, `pool`, `authority`, `release_list`
- `initialize`: async, finalize
- `transfer_ownership`: async, finalize
- `accept_ownership`: async, finalize
- `init_pool`: async, finalize
- `deposit`: async, finalize, cross-contract
- `release`: async, finalize
- `complete_release`: async, finalize, cross-contract
- `set_authority`: async, finalize
- `pool_control`: async, finalize
- `report_bond`: async, finalize
- `report_unbond`: async, finalize
- `report_total_unbond`: async, finalize

### `hyp_warp_token_usdt.aleo` (2 calls, bridge/cross-chain)
Cross-contract refs: `hyp_dispatch_proxy.aleo`, `hyp_mailbox.aleo`, `hyp_multisig_core.aleo`, `token_registry.aleo`
State mappings: `remote_routers`, `remote_router_iter`, `remote_router_length`, `app_metadata`
- `init`: async, finalize, cross-contract
- `set_custom_hook`: async, finalize
- `set_custom_ism`: async, finalize
- `set_owner`: async, finalize
- `enroll_remote_router`: async, finalize
- `unroll_remote_router`: async, finalize
- `transfer_remote`: async, finalize, cross-contract
- `transfer_remote_with_hook`: async, finalize, cross-contract
- `process`: async, finalize, cross-contract
- `get_balance_key`: cross-contract

### `arcn_puc_in_helper_v2_2_4.aleo` (2 calls, DeFi pool/lending)
Cross-contract refs: `arcn_compliance_v1.aleo`, `arcn_pool_v2_2_2.aleo`, `credits.aleo`, `token_registry.aleo`, `wrapped_credits.aleo`
- `create_pool_credits_is_token1`: async, finalize, cross-contract
- `swap_amm_credits_in`: async, finalize, cross-contract
- `add_amm_liq_credits_is_token1`: async, finalize, cross-contract
- `remove_liq_credits_is_token1`: async, finalize, cross-contract

### `hyp_warp_token_usdc.aleo` (2 calls, bridge/cross-chain)
Cross-contract refs: `hyp_dispatch_proxy.aleo`, `hyp_mailbox.aleo`, `hyp_multisig_core.aleo`, `token_registry.aleo`
State mappings: `remote_routers`, `remote_router_iter`, `remote_router_length`, `app_metadata`
- `init`: async, finalize, cross-contract
- `migrate_v1_remote_decimals`: async, finalize
- `set_custom_hook`: async, finalize
- `set_custom_ism`: async, finalize
- `set_owner`: async, finalize
- `enroll_remote_router`: async, finalize
- `unroll_remote_router`: async, finalize
- `transfer_remote`: async, finalize, cross-contract
- `transfer_remote_with_hook`: async, finalize, cross-contract
- `process`: async, finalize, cross-contract
- `get_balance_key`: cross-contract

### `hyp_warp_token_usad.aleo` (2 calls, bridge/cross-chain)
Cross-contract refs: `hyp_dispatch_proxy.aleo`, `hyp_mailbox.aleo`, `hyp_multisig_core.aleo`, `usad_freezelist.aleo`, `usad_stablecoin.aleo`
State mappings: `remote_routers`, `remote_router_iter`, `remote_router_length`, `app_metadata`
- `init`: async, finalize, cross-contract
- `set_custom_hook`: async, finalize
- `set_custom_ism`: async, finalize
- `set_owner`: async, finalize
- `enroll_remote_router`: async, finalize
- `unroll_remote_router`: async, finalize
- `transfer_remote`: async, finalize, cross-contract
- `transfer_remote_with_hook`: async, finalize, cross-contract
- `process`: async, finalize, cross-contract

### `phantom_mint.aleo` (1 calls, NFT/game asset)
- `mint`: conditional

### `lsp_host_bank_v1.aleo` (1 calls, application/other)
Cross-contract refs: `credits.aleo`
State mappings: `owned`, `withdrawal`
- `unbond_public`: async, finalize, cross-contract
- `transfer_public`: async, finalize, cross-contract
- `initialize`: async, finalize
- `withdraw`: async, finalize, cross-contract
- `set_withdrawal`: async, finalize
- `transfer_ownership`: async, finalize
- `accept_ownership`: async, finalize

### `puzzle_proving_partner.aleo` (1 calls, application/other)
Cross-contract refs: `credits.aleo`, `puzzle_capital_multisig.aleo`
State mappings: `global_config`, `current_epoch`, `initialized`, `address_to_role`, `partner_active`, `epoch_settled`, `pending_settlements`, `fee_pool`, `treasury`
- `initialize`: async, finalize
- `register_partner`: async, finalize
- `record_proving_rewards`: async, finalize
- `create_epoch_record`: async, finalize
- `settle_partner_epoch`: async, finalize
- `transfer_settlement`: async, finalize, cross-contract
- `advance_epoch`: async, finalize
- `withdraw_fees`: async, finalize, cross-contract
- `update_partner_apr`: async, finalize
- `update_partner_capacity`: async, finalize
- `update_partner_payout_address`: async, finalize
- `deactivate_partner`: async, finalize
- `set_paused`: async, finalize
- `update_role`: async, finalize

### `hyp_warp_token_wbtc.aleo` (1 calls, bridge/cross-chain)
Cross-contract refs: `hyp_dispatch_proxy.aleo`, `hyp_mailbox.aleo`, `hyp_multisig_core.aleo`, `token_registry.aleo`
State mappings: `remote_routers`, `remote_router_iter`, `remote_router_length`, `app_metadata`
- `init`: async, finalize, cross-contract
- `set_custom_hook`: async, finalize
- `set_custom_ism`: async, finalize
- `set_owner`: async, finalize
- `enroll_remote_router`: async, finalize
- `unroll_remote_router`: async, finalize
- `transfer_remote`: async, finalize, cross-contract
- `transfer_remote_with_hook`: async, finalize, cross-contract
- `process`: async, finalize, cross-contract
- `get_balance_key`: cross-contract

### `hyp_warp_token_eth.aleo` (1 calls, bridge/cross-chain)
Cross-contract refs: `hyp_dispatch_proxy.aleo`, `hyp_mailbox.aleo`, `hyp_multisig_core.aleo`, `token_registry.aleo`
State mappings: `remote_routers`, `remote_router_iter`, `remote_router_length`, `app_metadata`
- `init`: async, finalize, cross-contract
- `set_custom_hook`: async, finalize
- `set_custom_ism`: async, finalize
- `set_owner`: async, finalize
- `enroll_remote_router`: async, finalize
- `unroll_remote_router`: async, finalize
- `transfer_remote`: async, finalize, cross-contract
- `transfer_remote_with_hook`: async, finalize, cross-contract
- `process`: async, finalize, cross-contract
- `get_balance_key`: cross-contract

### `arcn_credits_in_helper_v2_2_3.aleo` (1 calls, token/credit flow)
Cross-contract refs: `arcn_compliance_v1.aleo`, `arcn_pool_v2_2_2.aleo`, `credits.aleo`, `token_registry.aleo`, `wrapped_credits.aleo`
- `create_pool_credits_is_token1`: async, finalize, cross-contract
- `swap_amm_credits_in`: async, finalize, cross-contract
- `add_amm_liq_credits_is_token1`: async, finalize, cross-contract
- `remove_liq_credits_is_token1`: async, finalize, cross-contract

### `victim_vault.aleo` (1 calls, application/other)
Cross-contract refs: `credits.aleo`
- `withdraw`: async, finalize, cross-contract

### `hyp_dispatch_proxy.aleo` (1 calls, bridge/cross-chain)
Cross-contract refs: `hyp_hook_manager.aleo`, `hyp_mailbox.aleo`, `hyp_multisig_core.aleo`
- `dispatch`: async, finalize, cross-contract

### `whalepool_puzzlecapital.aleo` (1 calls, staking/liquid staking)
Cross-contract refs: `credits.aleo`, `puzzle_capital_multisig.aleo`
State mappings: `global_config`, `current_epoch`, `initialized`, `address_to_role`, `provers`, `prover_epoch_shares`, `epoch_settlements`, `fee_pool`, `treasury`, `epoch_solutions_submitted`
- `initialize`: async, finalize
- `register_prover`: async, finalize, block.height delay
- `deregister_prover`: async, finalize
- `record_shares`: async, finalize
- `begin_epoch_settlement`: async, finalize
- `distribute_to_prover`: async, finalize, cross-contract
- `advance_epoch`: async, finalize
- `withdraw_fees`: async, finalize, cross-contract
- `update_prover_payout_address`: async, finalize
- `set_paused`: async, finalize
- `update_puzzle_capacity`: async, finalize
- `update_role`: async, finalize

### `autojoin_token_registry_2_9.aleo` (1 calls, token/credit flow)
Cross-contract refs: `token_registry.aleo`
- `join_2`: cross-contract
- `join_3`: cross-contract
- `join_4`: cross-contract
- `join_5`: cross-contract
- `join_6`: cross-contract
- `join_7`: cross-contract
- `join_8`: cross-contract
- `join_9`: cross-contract

### `par_store_v1.aleo` (1 calls, application/other)
Cross-contract refs: `par_store_inventory_v1.aleo`, `puzzle_arcade_ticket_v002.aleo`
- `purchase`: async, finalize, cross-contract
- `purchase2`: async, finalize, cross-contract
- `purchase3`: async, finalize, cross-contract
- `purchase4`: async, finalize, cross-contract
- `purchase5`: async, finalize, cross-contract
- `purchase6`: async, finalize, cross-contract
- `purchase7`: async, finalize, cross-contract
- `purchase8`: async, finalize, cross-contract
- `purchase9`: async, finalize, cross-contract

## testnet
### `credits.aleo` (22343 calls, token/credit flow)
State mappings: `committee`, `delegated`, `metadata`, `bonded`, `unbonding`, `account`, `withdraw`, `pool`
- `bond_validator`: async, finalize
- `bond_public`: async, finalize
- `unbond_public`: async, finalize, block.height delay
- `claim_unbond_public`: async, finalize, block.height delay
- `set_validator_state`: async, finalize
- `transfer_public`: async, finalize
- `transfer_public_as_signer`: async, finalize
- `transfer_private_to_public`: async, finalize
- `transfer_public_to_private`: async, finalize
- `fee_private`: conditional
- `fee_public`: async, finalize
- `upgrade`: async, finalize

### `dara_dp_credit_v5.aleo` (4380 calls, DeFi pool/lending)
Cross-contract refs: `credits.aleo`, `test_usdcx_stablecoin.aleo`
State mappings: `initialized`, `operators`, `pool_paused`, `order_consumed`, `fee_vault`, `fee_bps`, `total_trades`, `total_volume`, `oracle_price`, `oracle_round`, `twap_cum_price`, `twap_cum_count`, `twap_last_reset`, `twap_window_blocks`, `twap_max_deviation_bps`, `current_batch`, `batch_approved`, `batch_proposed_price`, `batch_proposer`, `batch_approval_count`, `operator_approved_batch`, `batch_start_block`, `min_batch_blocks`
- `initialize`: async, finalize
- `set_operators`: async, finalize
- `update_oracle_price`: async, finalize, block.height delay
- `submit_buy_order`: async, finalize, block.height delay, cross-contract
- `submit_sell_order`: async, finalize, block.height delay, cross-contract
- `propose_settlement`: async, finalize, block.height delay
- `approve_settlement`: async, finalize
- `execute_match`: async, finalize, cross-contract
- `execute_partial_fill`: async, finalize, cross-contract
- `cancel_buy_order`: async, finalize, cross-contract
- `cancel_sell_order`: async, finalize, cross-contract
- `advance_batch`: async, finalize, block.height delay
- `withdraw_fees`: async, finalize, cross-contract
- `set_fee_bps`: async, finalize
- `pause_darkpool`: async, finalize
- `resume_darkpool`: async, finalize

### `dara_dp_sol_v5.aleo` (4371 calls, DeFi pool/lending)
Cross-contract refs: `test_sol_v1.aleo`, `test_usdcx_stablecoin.aleo`
State mappings: `initialized`, `operators`, `pool_paused`, `order_consumed`, `fee_vault`, `fee_bps`, `total_trades`, `total_volume`, `oracle_price`, `oracle_round`, `twap_cum_price`, `twap_cum_count`, `twap_last_reset`, `twap_window_blocks`, `twap_max_deviation_bps`, `current_batch`, `batch_approved`, `batch_proposed_price`, `batch_proposer`, `batch_approval_count`, `operator_approved_batch`, `batch_start_block`, `min_batch_blocks`
- `initialize`: async, finalize
- `set_operators`: async, finalize
- `update_oracle_price`: async, finalize, block.height delay
- `submit_buy_order`: async, finalize, block.height delay, cross-contract
- `submit_sell_order`: async, finalize, block.height delay, cross-contract
- `propose_settlement`: async, finalize, block.height delay
- `approve_settlement`: async, finalize
- `execute_match`: async, finalize, cross-contract
- `execute_partial_fill`: async, finalize, cross-contract
- `cancel_buy_order`: async, finalize, cross-contract
- `cancel_sell_order`: async, finalize, cross-contract
- `advance_batch`: async, finalize, block.height delay
- `withdraw_fees`: async, finalize, cross-contract
- `set_fee_bps`: async, finalize
- `pause_darkpool`: async, finalize
- `resume_darkpool`: async, finalize

### `dara_dp_eth_v5.aleo` (4367 calls, DeFi pool/lending)
Cross-contract refs: `test_eth_v1.aleo`, `test_usdcx_stablecoin.aleo`
State mappings: `initialized`, `operators`, `pool_paused`, `order_consumed`, `fee_vault`, `fee_bps`, `total_trades`, `total_volume`, `oracle_price`, `oracle_round`, `twap_cum_price`, `twap_cum_count`, `twap_last_reset`, `twap_window_blocks`, `twap_max_deviation_bps`, `current_batch`, `batch_approved`, `batch_proposed_price`, `batch_proposer`, `batch_approval_count`, `operator_approved_batch`, `batch_start_block`, `min_batch_blocks`
- `initialize`: async, finalize
- `set_operators`: async, finalize
- `update_oracle_price`: async, finalize, block.height delay
- `submit_buy_order`: async, finalize, block.height delay, cross-contract
- `submit_sell_order`: async, finalize, block.height delay, cross-contract
- `propose_settlement`: async, finalize, block.height delay
- `approve_settlement`: async, finalize
- `execute_match`: async, finalize, cross-contract
- `execute_partial_fill`: async, finalize, cross-contract
- `cancel_buy_order`: async, finalize, cross-contract
- `cancel_sell_order`: async, finalize, cross-contract
- `advance_batch`: async, finalize, block.height delay
- `withdraw_fees`: async, finalize, cross-contract
- `set_fee_bps`: async, finalize
- `pause_darkpool`: async, finalize
- `resume_darkpool`: async, finalize

### `dara_dp_btc_v5.aleo` (4363 calls, DeFi pool/lending)
Cross-contract refs: `test_btc_v1.aleo`, `test_usdcx_stablecoin.aleo`
State mappings: `initialized`, `operators`, `pool_paused`, `order_consumed`, `fee_vault`, `fee_bps`, `total_trades`, `total_volume`, `oracle_price`, `oracle_round`, `twap_cum_price`, `twap_cum_count`, `twap_last_reset`, `twap_window_blocks`, `twap_max_deviation_bps`, `current_batch`, `batch_approved`, `batch_proposed_price`, `batch_proposer`, `batch_approval_count`, `operator_approved_batch`, `batch_start_block`, `min_batch_blocks`
- `initialize`: async, finalize
- `set_operators`: async, finalize
- `update_oracle_price`: async, finalize, block.height delay
- `submit_buy_order`: async, finalize, block.height delay, cross-contract
- `submit_sell_order`: async, finalize, block.height delay, cross-contract
- `propose_settlement`: async, finalize, block.height delay
- `approve_settlement`: async, finalize
- `execute_match`: async, finalize, cross-contract
- `execute_partial_fill`: async, finalize, cross-contract
- `cancel_buy_order`: async, finalize, cross-contract
- `cancel_sell_order`: async, finalize, cross-contract
- `advance_batch`: async, finalize, block.height delay
- `withdraw_fees`: async, finalize, cross-contract
- `set_fee_bps`: async, finalize
- `pause_darkpool`: async, finalize
- `resume_darkpool`: async, finalize

### `dara_lend_v8.aleo` (488 calls, DeFi pool/lending)
Cross-contract refs: `credits.aleo`, `test_usad_stablecoin.aleo`, `test_usdcx_stablecoin.aleo`
State mappings: `vault_collateral_aleo`, `pool_total_borrowed`, `loan_count`, `active_loans`, `oracle_price`, `price_update_block`, `price_round`, `price_history`, `used_nonces`, `protocol_admin`, `total_fees_collected`, `protocol_paused`, `privacy_version`, `rate_base_bps`, `rate_slope1_bps`, `rate_slope2_bps`, `rate_optimal_util`, `last_accrual_block`, `supply_apy_bps`, `borrow_apy_bps`
- `update_oracle_price`: async, finalize, block.height delay
- `set_rate_params`: async, finalize
- `emergency_pause`: async, finalize
- `resume_protocol`: async, finalize
- `accrue_interest`: async, finalize, block.height delay
- `supply_collateral`: async, finalize, cross-contract
- `borrow`: async, finalize, cross-contract
- `borrow_usad`: async, finalize, cross-contract
- `repay`: async, finalize, cross-contract
- `repay_usad`: async, finalize, cross-contract
- `liquidate`: async, finalize, cross-contract
- `withdraw_collateral`: async, finalize, cross-contract

### `dara_lend_v8_credits.aleo` (323 calls, token/credit flow)
Cross-contract refs: `credits.aleo`, `test_usad_stablecoin.aleo`, `test_usdcx_stablecoin.aleo`
State mappings: `vault_collateral_usdcx`, `vault_collateral_usad`, `pool_total_borrowed`, `loan_count`, `active_loans`, `oracle_price`, `price_update_block`, `price_round`, `used_nonces`, `credits_admin`, `total_fees_collected`, `credits_paused`
- `update_oracle_price`: async, finalize, block.height delay
- `emergency_pause`: async, finalize
- `resume_protocol`: async, finalize
- `supply_usdcx_collateral`: async, finalize, cross-contract
- `supply_usad_collateral`: async, finalize, cross-contract
- `borrow_credits`: async, finalize, cross-contract
- `repay_credits_usdcx`: async, finalize, cross-contract
- `repay_credits_usad`: async, finalize, cross-contract
- `liquidate_usdcx`: async, finalize, cross-contract
- `liquidate_usad`: async, finalize, cross-contract
- `withdraw_usdcx_collateral`: async, finalize, cross-contract
- `withdraw_usad_collateral`: async, finalize, cross-contract

### `dara_flash_v1.aleo` (262 calls, DeFi pool/lending)
Cross-contract refs: `credits.aleo`, `test_usdcx_stablecoin.aleo`
State mappings: `flash_admin`, `flash_paused`, `oracle_price`, `price_round`, `price_update_block`, `price_history`, `total_flash_loans`, `total_flash_volume`, `total_fees_earned`, `active_flash_count`, `used_nonces`
- `update_oracle_price`: async, finalize, block.height delay
- `flash_borrow_usdcx`: async, finalize, cross-contract
- `flash_claim_usdcx`: async, finalize, cross-contract
- `flash_repay_usdcx`: async, finalize, cross-contract
- `flash_withdraw_aleo`: async, finalize, cross-contract
- `flash_borrow_aleo`: async, finalize, cross-contract
- `flash_claim_aleo`: async, finalize, cross-contract
- `flash_repay_aleo`: async, finalize, cross-contract
- `flash_withdraw_usdcx`: async, finalize, cross-contract
- `pause_flash`: async, finalize
- `resume_flash`: async, finalize

### `autojoin_credits_2_10.aleo` (143 calls, token/credit flow)
Cross-contract refs: `credits.aleo`
- `join_2`: cross-contract
- `join_3`: cross-contract
- `join_4`: cross-contract
- `join_5`: cross-contract
- `join_6`: cross-contract
- `join_7`: cross-contract
- `join_8`: cross-contract
- `join_9`: cross-contract
- `join_10`: cross-contract

### `loyalty_token.aleo` (100 calls, token/credit flow)
State mappings: `card_exists`, `total_cards`, `total_points_issued`, `approved_upgrades`
- `approve_upgrade`: async, finalize
- `mint_card`: async, finalize
- `add_points`: async, finalize
- `transfer_card`: async, finalize
- `split_card`: async, finalize
- `split_card_v2`: async, finalize
- `spend_points`: conditional

### `test_usdcx_stablecoin.aleo` (87 calls, token/credit flow)
Cross-contract refs: `test_usdcx_freezelist.aleo`, `test_usdcx_multisig_core.aleo`
State mappings: `token_info`, `balances`, `allowances`, `address_to_role`, `pause`
- `update_role`: async, finalize
- `initialize`: async, finalize
- `get_credentials`: async, finalize, block.height delay
- `mint_public`: async, finalize
- `mint_private`: async, finalize
- `burn_public`: async, finalize
- `burn_private`: async, finalize
- `transfer_public`: async, finalize
- `transfer_public_as_signer`: async, finalize
- `approve_public`: async, finalize
- `unapprove_public`: async, finalize
- `transfer_from_public`: async, finalize
- `transfer_public_to_private`: async, finalize
- `transfer_from_public_to_private`: async, finalize
- `transfer_private`: async, finalize, block.height delay
- `transfer_private_to_public`: async, finalize, block.height delay
- `set_pause_status`: async, finalize
- `transfer_private_with_creds`: async, finalize, block.height delay
- `update_token_info`: async, finalize

### `note_server_messagingv4.aleo` (83 calls, application/other)
- `send_message_chunk`: conditional
- `send_message_chunk_batch_2`: conditional
- `send_message_chunk_batch_3`: conditional
- `send_message_chunk_batch_4`: conditional
- `send_message_chunk_batch_5`: conditional
- `send_message_chunk_batch_6`: conditional

### `loyalty_rewards.aleo` (32 calls, application/other)
Cross-contract refs: `loyalty_token.aleo`
State mappings: `voucher_exists`, `voucher_used`, `redemptions_by_type`, `approved_upgrades`
- `approve_upgrade`: async, finalize
- `redeem_points_for_voucher`: async, finalize, cross-contract
- `use_voucher`: async, finalize
- `transfer_voucher`: async, finalize

### `autojoin_credits_15_16.aleo` (29 calls, token/credit flow)
Cross-contract refs: `credits.aleo`
- `join_15`: cross-contract
- `join_16`: cross-contract

### `test_usad_stablecoin.aleo` (24 calls, token/credit flow)
Cross-contract refs: `test_usad_freezelist.aleo`, `test_usad_multisig_core.aleo`
State mappings: `token_info`, `balances`, `allowances`, `address_to_role`, `pause`
- `update_role`: async, finalize
- `initialize`: async, finalize
- `get_credentials`: async, finalize, block.height delay
- `mint_public`: async, finalize
- `mint_private`: async, finalize
- `burn_public`: async, finalize
- `burn_private`: async, finalize
- `transfer_public`: async, finalize
- `transfer_public_as_signer`: async, finalize
- `approve_public`: async, finalize
- `unapprove_public`: async, finalize
- `transfer_from_public`: async, finalize
- `transfer_public_to_private`: async, finalize
- `transfer_from_public_to_private`: async, finalize
- `transfer_private`: async, finalize, block.height delay
- `transfer_private_to_public`: async, finalize, block.height delay
- `set_pause_status`: async, finalize
- `transfer_private_with_creds`: async, finalize, block.height delay
- `update_token_info`: async, finalize

### `test_usdcx_bridge.aleo` (22 calls, bridge/cross-chain)
Cross-contract refs: `test_usdcx_freezelist.aleo`, `test_usdcx_multisig_core.aleo`, `test_usdcx_stablecoin.aleo`
State mappings: `circle_attester`, `minimum_burn_amount`, `nullifier`, `paused`, `emergency_paused`
- `mint_private`: async, finalize, block.height delay, cross-contract
- `mint_public`: async, finalize, cross-contract
- `burn`: async, finalize, cross-contract
- `burn_public`: async, finalize, cross-contract
- `set_pause_status`: async, finalize
- `set_circle_attester`: async, finalize
- `set_minimum_burn_amount`: async, finalize
- `address_to_bytes_raw`: cross-contract

### `token_registry.aleo` (14 calls, token/credit flow)
State mappings: `registered_tokens`, `balances`, `authorized_balances`, `allowances`, `roles`
- `transfer_public`: async, finalize, block.height delay
- `transfer_public_as_signer`: async, finalize, block.height delay
- `transfer_private`: async, finalize, block.height delay
- `transfer_private_to_public`: async, finalize, block.height delay
- `transfer_public_to_private`: async, finalize, block.height delay
- `join`: conditional
- `split`: conditional
- `initialize`: async, finalize
- `register_token`: async, finalize
- `update_token_management`: async, finalize
- `set_role`: async, finalize
- `remove_role`: async, finalize
- `mint_public`: async, finalize
- `mint_private`: async, finalize
- `burn_public`: async, finalize
- `burn_private`: async, finalize
- `prehook_public`: async, finalize, block.height delay
- `prehook_private`: async, finalize
- `approve_public`: async, finalize
- `unapprove_public`: async, finalize
- `transfer_from_public`: async, finalize, block.height delay
- `transfer_from_public_to_private`: async, finalize, block.height delay

### `ldgbatcher_ppub_28.aleo` (11 calls, application/other)
Cross-contract refs: `credits.aleo`
- `transfer_private_to_public_2`: async, finalize, cross-contract
- `transfer_private_to_public_3`: async, finalize, cross-contract
- `transfer_private_to_public_4`: async, finalize, cross-contract
- `transfer_private_to_public_5`: async, finalize, cross-contract
- `transfer_private_to_public_6`: async, finalize, cross-contract
- `transfer_private_to_public_7`: async, finalize, cross-contract
- `transfer_private_to_public_8`: async, finalize, cross-contract

### `aj_test_usdcx_stablecoin_2_10.aleo` (9 calls, token/credit flow)
Cross-contract refs: `test_usdcx_stablecoin.aleo`
- `join_2`: cross-contract
- `join_3`: cross-contract
- `join_4`: cross-contract
- `join_5`: cross-contract
- `join_6`: cross-contract
- `join_7`: cross-contract
- `join_8`: cross-contract
- `join_9`: cross-contract
- `join_10`: cross-contract

### `ldgbatcher_p28.aleo` (7 calls, application/other)
Cross-contract refs: `credits.aleo`
- `transfer_private_8`: cross-contract

### `f89b0d41ebe03707fd1f37ef95255ac.aleo` (7 calls, application/other)
State mappings: `pool_token0`, `pool_token1`, `pool_reserve0`, `pool_reserve1`, `pool_total_supply`, `pool_fee_bps`, `pool_enabled`, `lp_balances`, `token_balances`, `next_pool_id`
- `create_pool`: async, finalize
- `deposit`: async, finalize
- `withdraw`: async, finalize
- `add_liquidity`: async, finalize
- `remove_liquidity`: async, finalize
- `swap`: async, finalize

### `ldgbatcher_ppub_1114.aleo` (5 calls, application/other)
Cross-contract refs: `credits.aleo`
- `transfer_private_to_public_11`: async, finalize, cross-contract
- `transfer_private_to_public_12`: async, finalize, cross-contract
- `transfer_private_to_public_13`: async, finalize, cross-contract
- `transfer_private_to_public_14`: async, finalize, cross-contract

### `xyra_lending_v32.aleo` (5 calls, DeFi pool/lending)
Cross-contract refs: `credits.aleo`, `test_usad_stablecoin.aleo`, `test_usdcx_stablecoin.aleo`
State mappings: `total_deposited`, `total_borrowed`, `available_liquidity`, `supply_index`, `borrow_index`, `last_accrual_block`, `protocol_fees`, `supply_apy`, `borrow_apy`, `initialized`, `asset_base_rate`, `asset_slope_rate`, `asset_reserve_factor`, `asset_ltv`, `asset_liq_threshold`, `asset_liq_bonus`, `asset_price`, `flash_enabled`, `flash_premium_bps`, `flash_max_amount`, `flash_strategy_allowed`, `flash_active`, `flash_asset`, `flash_principal`, `flash_min_profit`, `flash_strategy_id`
- `initialize`: async, finalize
- `open_lending_account`: async, finalize
- `deposit_with_credits`: async, finalize, cross-contract
- `deposit_usdcx`: async, finalize, cross-contract
- `deposit_usad`: async, finalize, cross-contract
- `withdraw`: async, finalize
- `borrow`: async, finalize
- `repay_with_credits`: async, finalize, cross-contract
- `repay_usdcx`: async, finalize, cross-contract
- `repay_usad`: async, finalize, cross-contract
- `self_liquidate_and_payout`: async, finalize, cross-contract
- `accrue_interest`: async, finalize, block.height delay
- `set_asset_price`: async, finalize
- `set_asset_params`: async, finalize
- `withdraw_fees`: async, finalize
- `admin_update_asset`: async, finalize
- `set_flash_params`: async, finalize
- `set_flash_strategy_allowed`: async, finalize
- `flash_open`: async, finalize
- `flash_settle_with_credits`: async, finalize, cross-contract
- `flash_settle_with_usdcx`: async, finalize, cross-contract
- `flash_settle_with_usad`: async, finalize, cross-contract

### `humanity_link_aid_v9d.aleo` (4 calls, application/other)
Cross-contract refs: `test_usdcx_stablecoin.aleo`
State mappings: `admin_address`, `flags`, `authorized_issuers`, `whitelisted_merchants`, `bridge_address`, `last_merch_offramp`, `merchant_vault`, `clocks`, `limits`, `total_issued`, `total_spent`, `total_ben_offramp`, `total_merch_offramp`
- `transfer_admin`: async, finalize
- `authorize_issuer`: async, finalize
- `revoke_issuer`: async, finalize
- `whitelist_merchant`: async, finalize
- `revoke_merchant`: async, finalize
- `set_bridge_address`: async, finalize
- `set_merch_offramp_period`: async, finalize
- `set_min_merch_offramp`: async, finalize
- `pause`: async, finalize
- `unpause`: async, finalize
- `sweep_vault`: async, finalize, cross-contract
- `settle_merchant`: async, finalize
- `issue_aid`: async, finalize, cross-contract
- `bulk_issue_2`: async, finalize, cross-contract
- `bulk_issue_4`: async, finalize, cross-contract
- `spend`: async, finalize, cross-contract
- `offramp_beneficiary`: async, finalize, cross-contract
- `offramp_merchant`: async, finalize, block.height delay, cross-contract

### `zk_pay_proofs_privacy_v29.aleo` (3 calls, application/other)
Cross-contract refs: `credits.aleo`, `test_usad_stablecoin.aleo`, `test_usdcx_stablecoin.aleo`
State mappings: `invoices`, `salt_to_invoice`
- `create_invoice`: async, finalize, block.height delay
- `create_invoice_usdcx`: async, finalize, block.height delay
- `create_invoice_usad`: async, finalize, block.height delay
- `create_invoice_any`: async, finalize, block.height delay
- `pay_donation`: async, finalize, block.height delay, cross-contract
- `pay_invoice`: async, finalize, block.height delay, cross-contract
- `pay_invoice_usdcx`: async, finalize, block.height delay, cross-contract
- `pay_invoice_usad`: async, finalize, block.height delay, cross-contract
- `pay_donation_usdcx`: async, finalize, block.height delay, cross-contract
- `pay_donation_usad`: async, finalize, block.height delay, cross-contract
- `settle_invoice`: async, finalize
- `delete_invoice`: async, finalize
- `get_invoice_status`: async, finalize

### `aj_test_usad_stablecoin_2_10.aleo` (3 calls, token/credit flow)
Cross-contract refs: `test_usad_stablecoin.aleo`
- `join_2`: cross-contract
- `join_3`: cross-contract
- `join_4`: cross-contract
- `join_5`: cross-contract
- `join_6`: cross-contract
- `join_7`: cross-contract
- `join_8`: cross-contract
- `join_9`: cross-contract
- `join_10`: cross-contract

### `zk_pay_proofs_privacy_wallet_v6.aleo` (2 calls, application/other)
Cross-contract refs: `credits.aleo`, `test_usad_stablecoin.aleo`, `test_usdcx_stablecoin.aleo`
State mappings: `oracle_address`
- `delete_card_profile`: conditional
- `set_oracle_address`: async, finalize
- `pay_invoice_credits_via_usdcx`: async, finalize, block.height delay, cross-contract
- `pay_invoice_credits_via_usad`: async, finalize, block.height delay, cross-contract
- `pay_invoice_usdcx_via_credits`: async, finalize, block.height delay, cross-contract
- `pay_invoice_usdcx_via_usad`: async, finalize, block.height delay, cross-contract
- `pay_invoice_usad_via_credits`: async, finalize, block.height delay, cross-contract
- `pay_invoice_usad_via_usdcx`: async, finalize, block.height delay, cross-contract

### `cryptsign_v4.aleo` (2 calls, application/other)
- `record_contract`: conditional

### `test_hyp_ism_manager.aleo` (2 calls, bridge/cross-chain)
Cross-contract refs: `test_hyp_multisig_core.aleo`
State mappings: `nonce`, `ism_addresses`, `isms`, `domain_routing_isms`, `routes`, `route_iter`, `route_length`, `message_id_multisigs`
- `init_noop`: async, finalize
- `init_message_id_multisig`: async, finalize
- `init_domain_routing`: async, finalize
- `set_domain`: async, finalize
- `remove_domain`: async, finalize
- `transfer_routing_ism_ownership`: async, finalize
- `verify`: async, finalize

### `test_hyp_mailbox.aleo` (2 calls, bridge/cross-chain)
Cross-contract refs: `test_hyp_ism_manager.aleo`, `test_hyp_multisig_core.aleo`
State mappings: `deliveries`, `dispatch_events`, `dispatch_id_events`, `process_events`, `mailbox`, `process_event_index`, `dispatch_event_index`, `registered_applications`
- `init`: async, finalize
- `set_dispatch_proxy`: async, finalize
- `set_owner`: async, finalize
- `set_default_ism`: async, finalize
- `set_default_hook`: async, finalize
- `set_required_hook`: async, finalize
- `register_application`: async, finalize
- `process`: async, finalize, block.height delay, cross-contract
- `dispatch`: async, finalize, block.height delay

### `test_hyp_warp_token_usad.aleo` (2 calls, bridge/cross-chain)
Cross-contract refs: `test_hyp_dispatch_proxy.aleo`, `test_hyp_mailbox.aleo`, `test_hyp_multisig_core.aleo`, `test_usad_freezelist.aleo`, `test_usad_stablecoin.aleo`
State mappings: `remote_routers`, `remote_router_iter`, `remote_router_length`, `app_metadata`
- `init`: async, finalize, cross-contract
- `set_custom_hook`: async, finalize
- `set_custom_ism`: async, finalize
- `set_owner`: async, finalize
- `enroll_remote_router`: async, finalize
- `unroll_remote_router`: async, finalize
- `transfer_remote`: async, finalize, cross-contract
- `transfer_remote_with_hook`: async, finalize, cross-contract
- `process`: async, finalize, cross-contract

### `woo_genesis_1988.aleo` (2 calls, application/other)
Cross-contract refs: `credits.aleo`
State mappings: `authorized_relayers`, `authorized_vaults`, `is_initialized`, `roles`, `bridge_stats`, `slashed_validators`, `validator_stakes`, `supported_chains`
- `transfer_admin`: async, finalize
- `accept_admin`: async, finalize
- `initialize_bridge`: async, finalize
- `spawn_chain`: async, finalize
- `pause_network`: conditional
- `unpause_network`: conditional
- `emergency_drain`: async, finalize, cross-contract
- `commit_rollup`: conditional
- `mint_gas`: async, finalize
- `stake_validator`: async, finalize, cross-contract
- `slash_validator`: async, finalize
- `slash_and_seize`: async, finalize
- `authorize_relayer`: async, finalize
- `revoke_relayer`: async, finalize
- `bridge_in`: async, finalize, cross-contract
- `bridge_out`: async, finalize, cross-contract

### `wrapped_credits.aleo` (2 calls, token/credit flow)
Cross-contract refs: `credits.aleo`, `token_registry.aleo`
- `deposit_credits_public_signer`: async, finalize, cross-contract
- `deposit_credits_private`: async, finalize, cross-contract
- `withdraw_credits_public`: async, finalize, cross-contract
- `withdraw_credits_public_signer`: async, finalize, cross-contract
- `withdraw_credits_private`: async, finalize, cross-contract

### `autojoin_token_registry_2_9.aleo` (1 calls, token/credit flow)
Cross-contract refs: `token_registry.aleo`
- `join_2`: cross-contract
- `join_3`: cross-contract
- `join_4`: cross-contract
- `join_5`: cross-contract
- `join_6`: cross-contract
- `join_7`: cross-contract
- `join_8`: cross-contract
- `join_9`: cross-contract

### `ldgbatcher_p910.aleo` (1 calls, application/other)
Cross-contract refs: `credits.aleo`
- `transfer_private_10`: cross-contract

### `toka_token.aleo` (1 calls, token/credit flow)
State mappings: `balances`, `approvals`
- `approve_public`: async, finalize
- `unapprove_public`: async, finalize
- `transfer_from_public`: async, finalize
- `transfer_public_as_signer`: async, finalize
- `transfer_public`: async, finalize
- `transfer_private_to_public`: async, finalize
- `transfer_public_to_private`: async, finalize
- `mint_public`: async, finalize

### `ldgbatcher_p1114.aleo` (1 calls, application/other)
Cross-contract refs: `credits.aleo`
- `transfer_private_14`: cross-contract
