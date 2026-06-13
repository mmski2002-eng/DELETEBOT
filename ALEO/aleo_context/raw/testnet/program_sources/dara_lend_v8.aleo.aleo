import credits.aleo;
import merkle_tree.aleo;
import test_usdcx_multisig_core.aleo;
import test_usdcx_freezelist.aleo;
import test_usdcx_stablecoin.aleo;
import test_usad_multisig_core.aleo;
import test_usad_freezelist.aleo;
import test_usad_stablecoin.aleo;

program dara_lend_v8.aleo;

record CollateralReceipt:
    owner as address.private;
    collateral_amount as u64.private;
    collateral_amount_u128 as u128.private;
    token_type as u8.private;
    deposit_block as u32.private;
    nonce_hash as field.private;

record DebtPosition:
    owner as address.private;
    collateral_amount as u64.private;
    collateral_amount_u128 as u128.private;
    collateral_token as u8.private;
    debt_amount as u128.private;
    debt_token as u8.private;
    liquidation_price as u64.private;
    loan_id as field.private;

record LiquidationAuth:
    owner as address.private;
    loan_id as field.private;
    collateral_amount as u64.private;
    collateral_amount_u128 as u128.private;
    collateral_token as u8.private;
    debt_amount as u128.private;
    debt_token as u8.private;
    liquidation_price as u64.private;
    borrower_hash as field.private;

record RepaymentReceipt:
    owner as address.private;
    amount_repaid as u128.private;
    collateral_returned as u64.private;
    collateral_returned_u128 as u128.private;
    collateral_token as u8.private;
    loan_id as field.private;

record LiquidationReceipt:
    owner as address.private;
    loan_id as field.private;
    collateral_seized as u64.private;
    collateral_seized_u128 as u128.private;
    collateral_token as u8.private;
    debt_covered as u128.private;

mapping vault_collateral_aleo:
    key as u8.public;
    value as u64.public;

mapping pool_total_borrowed:
    key as u8.public;
    value as u128.public;

mapping loan_count:
    key as u8.public;
    value as u64.public;

mapping active_loans:
    key as field.public;
    value as boolean.public;

mapping oracle_price:
    key as u8.public;
    value as u64.public;

mapping price_update_block:
    key as u8.public;
    value as u32.public;

mapping price_round:
    key as u8.public;
    value as u64.public;

mapping price_history:
    key as u8.public;
    value as u64.public;

mapping used_nonces:
    key as field.public;
    value as boolean.public;

mapping protocol_admin:
    key as u8.public;
    value as address.public;

mapping total_fees_collected:
    key as u8.public;
    value as u128.public;

mapping protocol_paused:
    key as u8.public;
    value as boolean.public;

mapping privacy_version:
    key as u8.public;
    value as u64.public;

mapping rate_base_bps:
    key as u8.public;
    value as u64.public;

mapping rate_slope1_bps:
    key as u8.public;
    value as u64.public;

mapping rate_slope2_bps:
    key as u8.public;
    value as u64.public;

mapping rate_optimal_util:
    key as u8.public;
    value as u64.public;

mapping last_accrual_block:
    key as u8.public;
    value as u32.public;

mapping supply_apy_bps:
    key as u8.public;
    value as u64.public;

mapping borrow_apy_bps:
    key as u8.public;
    value as u64.public;

function update_oracle_price:
    input r0 as u8.private;
    input r1 as u64.private;
    input r2 as u64.private;
    gt r1 0u64 into r3;
    assert.eq r3 true;
    gt r2 0u64 into r4;
    assert.eq r4 true;
    lt r0 6u8 into r5;
    assert.eq r5 true;
    async update_oracle_price self.caller r0 r2 r1 into r6;
    output r6 as dara_lend_v8.aleo/update_oracle_price.future;

finalize update_oracle_price:
    input r0 as address.public;
    input r1 as u8.public;
    input r2 as u64.public;
    input r3 as u64.public;
    get protocol_admin[0u8] into r4;
    assert.eq r0 r4;
    get.or_use price_round[r1] 0u64 into r5;
    gt r2 r5 into r6;
    assert.eq r6 true;
    get.or_use price_update_block[r1] 0u32 into r7;
    sub block.height r7 into r8;
    is.eq r7 0u32 into r9;
    gte r8 5u32 into r10;
    or r9 r10 into r11;
    assert.eq r11 true;
    get.or_use price_history[r1] r3 into r12;
    gte r3 r12 into r13;
    ternary r13 r3 r12 into r14;
    lt r3 r12 into r15;
    ternary r15 r3 r12 into r16;
    sub r14 r16 into r17;
    gt r12 0u64 into r18;
    mul r17 10000u64 into r19;
    div r19 r12 into r20;
    ternary r18 r20 0u64 into r21;
    is.eq r5 0u64 into r22;
    lte r21 1500u64 into r23;
    or r22 r23 into r24;
    assert.eq r24 true;
    set r3 into oracle_price[r1];
    set block.height into price_update_block[r1];
    set r2 into price_round[r1];
    set r3 into price_history[r1];

function set_rate_params:
    input r0 as u64.private;
    input r1 as u64.private;
    input r2 as u64.private;
    input r3 as u64.private;
    gt r3 0u64 into r4;
    assert.eq r4 true;
    lte r3 10000u64 into r5;
    assert.eq r5 true;
    async set_rate_params self.caller r0 r1 r2 r3 into r6;
    output r6 as dara_lend_v8.aleo/set_rate_params.future;

finalize set_rate_params:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as u64.public;
    input r3 as u64.public;
    input r4 as u64.public;
    get protocol_admin[0u8] into r5;
    assert.eq r0 r5;
    set r1 into rate_base_bps[0u8];
    set r2 into rate_slope1_bps[0u8];
    set r3 into rate_slope2_bps[0u8];
    set r4 into rate_optimal_util[0u8];

function emergency_pause:
    async emergency_pause self.caller into r0;
    output r0 as dara_lend_v8.aleo/emergency_pause.future;

finalize emergency_pause:
    input r0 as address.public;
    get protocol_admin[0u8] into r1;
    assert.eq r0 r1;
    set true into protocol_paused[0u8];

function resume_protocol:
    async resume_protocol self.caller into r0;
    output r0 as dara_lend_v8.aleo/resume_protocol.future;

finalize resume_protocol:
    input r0 as address.public;
    get protocol_admin[0u8] into r1;
    assert.eq r0 r1;
    set false into protocol_paused[0u8];

function accrue_interest:
    async accrue_interest into r0;
    output r0 as dara_lend_v8.aleo/accrue_interest.future;

finalize accrue_interest:
    get.or_use last_accrual_block[0u8] 0u32 into r0;
    sub block.height r0 into r1;
    gt r1 0u32 into r2;
    gt r0 0u32 into r3;
    and r2 r3 into r4;
    get.or_use rate_base_bps[0u8] 200u64 into r5;
    get.or_use rate_slope1_bps[0u8] 400u64 into r6;
    get.or_use rate_slope2_bps[0u8] 7500u64 into r7;
    get.or_use rate_optimal_util[0u8] 8000u64 into r8;
    get.or_use pool_total_borrowed[0u8] 0u128 into r9;
    get.or_use vault_collateral_aleo[0u8] 0u64 into r10;
    get.or_use oracle_price[0u8] 1000000u64 into r11;
    cast r10 into r12 as u128;
    cast r11 into r13 as u128;
    mul r12 r13 into r14;
    div r14 1000000u128 into r15;
    gt r15 0u128 into r16;
    mul r9 10000u128 into r17;
    div r17 r15 into r18;
    ternary r16 r18 0u128 into r19;
    gt r19 10000u128 into r20;
    ternary r20 10000u128 r19 into r21;
    cast r8 into r22 as u128;
    cast r6 into r23 as u128;
    cast r7 into r24 as u128;
    cast r5 into r25 as u128;
    mul r21 r23 into r26;
    div r26 r22 into r27;
    add r25 r27 into r28;
    gt r21 r22 into r29;
    sub r21 r22 into r30;
    ternary r29 r30 0u128 into r31;
    sub 10000u128 r22 into r32;
    gt r32 0u128 into r33;
    mul r31 r24 into r34;
    div r34 r32 into r35;
    ternary r33 r35 0u128 into r36;
    lte r21 r22 into r37;
    add r25 r23 into r38;
    add r38 r36 into r39;
    ternary r37 r28 r39 into r40;
    mul r40 r21 into r41;
    mul r41 9000u128 into r42;
    div r42 10000u128 into r43;
    div r43 10000u128 into r44;
    cast r1 into r45 as u128;
    mul r9 r40 into r46;
    mul r46 r45 into r47;
    div r47 26280000000u128 into r48;
    ternary r4 r48 0u128 into r49;
    add r9 r49 into r50;
    set r50 into pool_total_borrowed[0u8];
    mul r49 1000u128 into r51;
    div r51 10000u128 into r52;
    get.or_use total_fees_collected[0u8] 0u128 into r53;
    add r53 r52 into r54;
    set r54 into total_fees_collected[0u8];
    cast r40 into r55 as u64;
    set r55 into borrow_apy_bps[0u8];
    cast r44 into r56 as u64;
    set r56 into supply_apy_bps[0u8];
    set block.height into last_accrual_block[0u8];

function supply_collateral:
    input r0 as credits.aleo/credits.record;
    input r1 as u64.private;
    input r2 as field.private;
    gte r1 100000u64 into r3;
    assert.eq r3 true;
    hash.bhp256 self.signer into r4 as field;
    add r2 r4 into r5;
    hash.bhp256 r5 into r6 as field;
    cast self.signer r1 0u128 0u8 0u32 r6 into r7 as CollateralReceipt.record;
    call credits.aleo/transfer_private_to_public r0 dara_lend_v8.aleo r1 into r8 r9;
    async supply_collateral r9 r6 r1 into r10;
    output r7 as CollateralReceipt.record;
    output r10 as dara_lend_v8.aleo/supply_collateral.future;

finalize supply_collateral:
    input r0 as credits.aleo/transfer_private_to_public.future;
    input r1 as field.public;
    input r2 as u64.public;
    await r0;
    get.or_use protocol_paused[0u8] false into r3;
    not r3 into r4;
    assert.eq r4 true;
    get.or_use used_nonces[r1] false into r5;
    not r5 into r6;
    assert.eq r6 true;
    set true into used_nonces[r1];
    get.or_use vault_collateral_aleo[0u8] 0u64 into r7;
    add r7 r2 into r8;
    set r8 into vault_collateral_aleo[0u8];

function borrow:
    input r0 as CollateralReceipt.record;
    input r1 as u128.private;
    input r2 as u64.private;
    input r3 as address.private;
    gt r1 0u128 into r4;
    assert.eq r4 true;
    is.eq r0.token_type 0u8 into r5;
    assert.eq r5 true;
    cast r0.collateral_amount into r6 as u128;
    cast r2 into r7 as u128;
    mul r6 r7 into r8;
    div r8 1000000u128 into r9;
    mul r9 7000u128 into r10;
    div r10 10000u128 into r11;
    lte r1 r11 into r12;
    assert.eq r12 true;
    mul r1 50u128 into r13;
    div r13 10000u128 into r14;
    sub r1 r14 into r15;
    mul r1 1000000u128 into r16;
    mul r16 10000u128 into r17;
    mul r6 8000u128 into r18;
    div r17 r18 into r19;
    cast r19 into r20 as u64;
    hash.bhp256 r0.nonce_hash into r21 as field;
    hash.bhp256 self.signer into r22 as field;
    cast self.signer r0.collateral_amount 0u128 0u8 r1 1u8 r20 r21 into r23 as DebtPosition.record;
    cast r3 r21 r0.collateral_amount 0u128 0u8 r1 1u8 r20 r22 into r24 as LiquidationAuth.record;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private self.caller r15 into r25 r26 r27;
    async borrow r27 r2 r1 r14 r21 into r28;
    output r23 as DebtPosition.record;
    output r24 as LiquidationAuth.record;
    output r28 as dara_lend_v8.aleo/borrow.future;

finalize borrow:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as u64.public;
    input r2 as u128.public;
    input r3 as u128.public;
    input r4 as field.public;
    await r0;
    get.or_use protocol_paused[0u8] false into r5;
    not r5 into r6;
    assert.eq r6 true;
    get oracle_price[0u8] into r7;
    assert.eq r1 r7;
    get.or_use pool_total_borrowed[0u8] 0u128 into r8;
    add r8 r2 into r9;
    lte r9 100000000000u128 into r10;
    assert.eq r10 true;
    set r9 into pool_total_borrowed[0u8];
    get.or_use total_fees_collected[0u8] 0u128 into r11;
    add r11 r3 into r12;
    set r12 into total_fees_collected[0u8];
    get.or_use loan_count[0u8] 0u64 into r13;
    add r13 1u64 into r14;
    set r14 into loan_count[0u8];
    hash.bhp256 r4 into r15 as field;
    set true into active_loans[r15];

function borrow_usad:
    input r0 as CollateralReceipt.record;
    input r1 as u128.private;
    input r2 as u64.private;
    input r3 as address.private;
    gt r1 0u128 into r4;
    assert.eq r4 true;
    is.eq r0.token_type 0u8 into r5;
    assert.eq r5 true;
    cast r0.collateral_amount into r6 as u128;
    cast r2 into r7 as u128;
    mul r6 r7 into r8;
    div r8 1000000u128 into r9;
    mul r9 7000u128 into r10;
    div r10 10000u128 into r11;
    lte r1 r11 into r12;
    assert.eq r12 true;
    mul r1 50u128 into r13;
    div r13 10000u128 into r14;
    sub r1 r14 into r15;
    mul r1 1000000u128 into r16;
    mul r16 10000u128 into r17;
    mul r6 8000u128 into r18;
    div r17 r18 into r19;
    cast r19 into r20 as u64;
    hash.bhp256 r0.nonce_hash into r21 as field;
    hash.bhp256 self.signer into r22 as field;
    cast self.signer r0.collateral_amount 0u128 0u8 r1 2u8 r20 r21 into r23 as DebtPosition.record;
    cast r3 r21 r0.collateral_amount 0u128 0u8 r1 2u8 r20 r22 into r24 as LiquidationAuth.record;
    call test_usad_stablecoin.aleo/transfer_public_to_private self.caller r15 into r25 r26 r27;
    async borrow_usad r27 r2 r1 r14 r21 into r28;
    output r23 as DebtPosition.record;
    output r24 as LiquidationAuth.record;
    output r28 as dara_lend_v8.aleo/borrow_usad.future;

finalize borrow_usad:
    input r0 as test_usad_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as u64.public;
    input r2 as u128.public;
    input r3 as u128.public;
    input r4 as field.public;
    await r0;
    get.or_use protocol_paused[0u8] false into r5;
    not r5 into r6;
    assert.eq r6 true;
    get oracle_price[0u8] into r7;
    assert.eq r1 r7;
    get.or_use pool_total_borrowed[1u8] 0u128 into r8;
    add r8 r2 into r9;
    lte r9 100000000000u128 into r10;
    assert.eq r10 true;
    set r9 into pool_total_borrowed[1u8];
    get.or_use total_fees_collected[0u8] 0u128 into r11;
    add r11 r3 into r12;
    set r12 into total_fees_collected[0u8];
    get.or_use loan_count[0u8] 0u64 into r13;
    add r13 1u64 into r14;
    set r14 into loan_count[0u8];
    hash.bhp256 r4 into r15 as field;
    set true into active_loans[r15];

function repay:
    input r0 as DebtPosition.record;
    is.eq r0.debt_token 1u8 into r1;
    assert.eq r1 true;
    is.eq r0.collateral_token 0u8 into r2;
    assert.eq r2 true;
    cast self.signer r0.debt_amount r0.collateral_amount 0u128 0u8 r0.loan_id into r3 as RepaymentReceipt.record;
    call test_usdcx_stablecoin.aleo/transfer_from_public self.caller dara_lend_v8.aleo r0.debt_amount into r4;
    call credits.aleo/transfer_public_to_private self.caller r0.collateral_amount into r5 r6;
    async repay r4 r6 r0.debt_amount r0.collateral_amount r0.loan_id into r7;
    output r3 as RepaymentReceipt.record;
    output r7 as dara_lend_v8.aleo/repay.future;

finalize repay:
    input r0 as test_usdcx_stablecoin.aleo/transfer_from_public.future;
    input r1 as credits.aleo/transfer_public_to_private.future;
    input r2 as u128.public;
    input r3 as u64.public;
    input r4 as field.public;
    await r0;
    await r1;
    get pool_total_borrowed[0u8] into r5;
    sub r5 r2 into r6;
    set r6 into pool_total_borrowed[0u8];
    get loan_count[0u8] into r7;
    sub r7 1u64 into r8;
    set r8 into loan_count[0u8];
    get vault_collateral_aleo[0u8] into r9;
    sub r9 r3 into r10;
    set r10 into vault_collateral_aleo[0u8];
    hash.bhp256 r4 into r11 as field;
    set false into active_loans[r11];

function repay_usad:
    input r0 as DebtPosition.record;
    is.eq r0.debt_token 2u8 into r1;
    assert.eq r1 true;
    is.eq r0.collateral_token 0u8 into r2;
    assert.eq r2 true;
    cast self.signer r0.debt_amount r0.collateral_amount 0u128 0u8 r0.loan_id into r3 as RepaymentReceipt.record;
    call test_usad_stablecoin.aleo/transfer_from_public self.caller dara_lend_v8.aleo r0.debt_amount into r4;
    call credits.aleo/transfer_public_to_private self.caller r0.collateral_amount into r5 r6;
    async repay_usad r4 r6 r0.debt_amount r0.collateral_amount r0.loan_id into r7;
    output r3 as RepaymentReceipt.record;
    output r7 as dara_lend_v8.aleo/repay_usad.future;

finalize repay_usad:
    input r0 as test_usad_stablecoin.aleo/transfer_from_public.future;
    input r1 as credits.aleo/transfer_public_to_private.future;
    input r2 as u128.public;
    input r3 as u64.public;
    input r4 as field.public;
    await r0;
    await r1;
    get pool_total_borrowed[1u8] into r5;
    sub r5 r2 into r6;
    set r6 into pool_total_borrowed[1u8];
    get loan_count[0u8] into r7;
    sub r7 1u64 into r8;
    set r8 into loan_count[0u8];
    get vault_collateral_aleo[0u8] into r9;
    sub r9 r3 into r10;
    set r10 into vault_collateral_aleo[0u8];
    hash.bhp256 r4 into r11 as field;
    set false into active_loans[r11];

function liquidate:
    input r0 as LiquidationAuth.record;
    input r1 as u64.private;
    lte r1 r0.liquidation_price into r2;
    assert.eq r2 true;
    is.eq r0.collateral_token 0u8 into r3;
    assert.eq r3 true;
    cast r0.collateral_amount into r4 as u128;
    mul r4 500u128 into r5;
    div r5 10000u128 into r6;
    add r4 r6 into r7;
    cast r7 into r8 as u64;
    cast self.signer r0.loan_id r8 0u128 0u8 r0.debt_amount into r9 as LiquidationReceipt.record;
    call credits.aleo/transfer_public_to_private self.caller r8 into r10 r11;
    async liquidate r11 r1 r8 r0.debt_token r0.debt_amount r0.loan_id into r12;
    output r9 as LiquidationReceipt.record;
    output r12 as dara_lend_v8.aleo/liquidate.future;

finalize liquidate:
    input r0 as credits.aleo/transfer_public_to_private.future;
    input r1 as u64.public;
    input r2 as u64.public;
    input r3 as u8.public;
    input r4 as u128.public;
    input r5 as field.public;
    await r0;
    get oracle_price[0u8] into r6;
    assert.eq r1 r6;
    get vault_collateral_aleo[0u8] into r7;
    sub r7 r2 into r8;
    set r8 into vault_collateral_aleo[0u8];
    is.eq r3 1u8 into r9;
    ternary r9 0u8 1u8 into r10;
    get pool_total_borrowed[r10] into r11;
    sub r11 r4 into r12;
    set r12 into pool_total_borrowed[r10];
    get loan_count[0u8] into r13;
    sub r13 1u64 into r14;
    set r14 into loan_count[0u8];
    hash.bhp256 r5 into r15 as field;
    set false into active_loans[r15];

function withdraw_collateral:
    input r0 as CollateralReceipt.record;
    is.eq r0.token_type 0u8 into r1;
    assert.eq r1 true;
    call credits.aleo/transfer_public_to_private self.caller r0.collateral_amount into r2 r3;
    async withdraw_collateral r3 r0.collateral_amount into r4;
    output r4 as dara_lend_v8.aleo/withdraw_collateral.future;

finalize withdraw_collateral:
    input r0 as credits.aleo/transfer_public_to_private.future;
    input r1 as u64.public;
    await r0;
    get vault_collateral_aleo[0u8] into r2;
    sub r2 r1 into r3;
    set r3 into vault_collateral_aleo[0u8];

constructor:
    set aleo1fcvvertrnraperrdn7p048vlddlxpd89xszelsgyvwnfyxhmcc8skn2cs8 into protocol_admin[0u8];
    set 1000000u64 into oracle_price[0u8];
    set 1000000u64 into oracle_price[1u8];
    set 1000000u64 into oracle_price[2u8];
    set 1000000u64 into price_history[0u8];
    set 1000000u64 into price_history[1u8];
    set 1000000u64 into price_history[2u8];
    set 200u64 into rate_base_bps[0u8];
    set 400u64 into rate_slope1_bps[0u8];
    set 7500u64 into rate_slope2_bps[0u8];
    set 8000u64 into rate_optimal_util[0u8];
    set 4u64 into privacy_version[0u8];
