import credits.aleo;
import merkle_tree.aleo;
import test_usdcx_multisig_core.aleo;
import test_usdcx_freezelist.aleo;
import test_usdcx_stablecoin.aleo;
import test_usad_multisig_core.aleo;
import test_usad_freezelist.aleo;
import test_usad_stablecoin.aleo;

program dara_lend_v8_credits.aleo;

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

mapping vault_collateral_usdcx:
    key as u8.public;
    value as u128.public;

mapping vault_collateral_usad:
    key as u8.public;
    value as u128.public;

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

mapping used_nonces:
    key as field.public;
    value as boolean.public;

mapping credits_admin:
    key as u8.public;
    value as address.public;

mapping total_fees_collected:
    key as u8.public;
    value as u128.public;

mapping credits_paused:
    key as u8.public;
    value as boolean.public;

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
    output r6 as dara_lend_v8_credits.aleo/update_oracle_price.future;

finalize update_oracle_price:
    input r0 as address.public;
    input r1 as u8.public;
    input r2 as u64.public;
    input r3 as u64.public;
    get credits_admin[0u8] into r4;
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
    set r3 into oracle_price[r1];
    set block.height into price_update_block[r1];
    set r2 into price_round[r1];

function emergency_pause:
    async emergency_pause self.caller into r0;
    output r0 as dara_lend_v8_credits.aleo/emergency_pause.future;

finalize emergency_pause:
    input r0 as address.public;
    get credits_admin[0u8] into r1;
    assert.eq r0 r1;
    set true into credits_paused[0u8];

function resume_protocol:
    async resume_protocol self.caller into r0;
    output r0 as dara_lend_v8_credits.aleo/resume_protocol.future;

finalize resume_protocol:
    input r0 as address.public;
    get credits_admin[0u8] into r1;
    assert.eq r0 r1;
    set false into credits_paused[0u8];

function supply_usdcx_collateral:
    input r0 as test_usdcx_stablecoin.aleo/Token.record;
    input r1 as [test_usdcx_stablecoin.aleo/MerkleProof; 2u32].private;
    input r2 as u128.private;
    input r3 as field.private;
    gte r2 100000u128 into r4;
    assert.eq r4 true;
    hash.bhp256 self.signer into r5 as field;
    add r3 r5 into r6;
    hash.bhp256 r6 into r7 as field;
    cast self.signer 0u64 r2 1u8 0u32 r7 into r8 as CollateralReceipt.record;
    call test_usdcx_stablecoin.aleo/transfer_private_to_public dara_lend_v8_credits.aleo r2 r0 r1 into r9 r10 r11;
    async supply_usdcx_collateral r11 r7 r2 into r12;
    output r8 as CollateralReceipt.record;
    output r12 as dara_lend_v8_credits.aleo/supply_usdcx_collateral.future;

finalize supply_usdcx_collateral:
    input r0 as test_usdcx_stablecoin.aleo/transfer_private_to_public.future;
    input r1 as field.public;
    input r2 as u128.public;
    await r0;
    get.or_use credits_paused[0u8] false into r3;
    not r3 into r4;
    assert.eq r4 true;
    get.or_use used_nonces[r1] false into r5;
    not r5 into r6;
    assert.eq r6 true;
    set true into used_nonces[r1];
    get.or_use vault_collateral_usdcx[0u8] 0u128 into r7;
    add r7 r2 into r8;
    set r8 into vault_collateral_usdcx[0u8];

function supply_usad_collateral:
    input r0 as test_usad_stablecoin.aleo/Token.record;
    input r1 as [test_usad_stablecoin.aleo/MerkleProof; 2u32].private;
    input r2 as u128.private;
    input r3 as field.private;
    gte r2 100000u128 into r4;
    assert.eq r4 true;
    hash.bhp256 self.signer into r5 as field;
    add r3 r5 into r6;
    hash.bhp256 r6 into r7 as field;
    cast self.signer 0u64 r2 2u8 0u32 r7 into r8 as CollateralReceipt.record;
    call test_usad_stablecoin.aleo/transfer_private_to_public dara_lend_v8_credits.aleo r2 r0 r1 into r9 r10 r11;
    async supply_usad_collateral r11 r7 r2 into r12;
    output r8 as CollateralReceipt.record;
    output r12 as dara_lend_v8_credits.aleo/supply_usad_collateral.future;

finalize supply_usad_collateral:
    input r0 as test_usad_stablecoin.aleo/transfer_private_to_public.future;
    input r1 as field.public;
    input r2 as u128.public;
    await r0;
    get.or_use credits_paused[0u8] false into r3;
    not r3 into r4;
    assert.eq r4 true;
    get.or_use used_nonces[r1] false into r5;
    not r5 into r6;
    assert.eq r6 true;
    set true into used_nonces[r1];
    get.or_use vault_collateral_usad[0u8] 0u128 into r7;
    add r7 r2 into r8;
    set r8 into vault_collateral_usad[0u8];

function borrow_credits:
    input r0 as CollateralReceipt.record;
    input r1 as u64.private;
    input r2 as u64.private;
    input r3 as u64.private;
    input r4 as address.private;
    gt r1 0u64 into r5;
    assert.eq r5 true;
    is.eq r0.token_type 1u8 into r6;
    is.eq r0.token_type 2u8 into r7;
    or r6 r7 into r8;
    assert.eq r8 true;
    cast r2 into r9 as u128;
    mul r0.collateral_amount_u128 r9 into r10;
    div r10 1000000u128 into r11;
    cast r1 into r12 as u128;
    cast r3 into r13 as u128;
    mul r12 r13 into r14;
    div r14 1000000u128 into r15;
    mul r11 7000u128 into r16;
    div r16 10000u128 into r17;
    lte r15 r17 into r18;
    assert.eq r18 true;
    mul r12 50u128 into r19;
    div r19 10000u128 into r20;
    sub r12 r20 into r21;
    cast r21 into r22 as u64;
    mul r15 10000u128 into r23;
    mul r23 1000000u128 into r24;
    mul r0.collateral_amount_u128 8000u128 into r25;
    div r24 r25 into r26;
    cast r26 into r27 as u64;
    hash.bhp256 r0.nonce_hash into r28 as field;
    hash.bhp256 self.signer into r29 as field;
    cast self.signer 0u64 r0.collateral_amount_u128 r0.token_type r12 0u8 r27 r28 into r30 as DebtPosition.record;
    cast r4 r28 0u64 r0.collateral_amount_u128 r0.token_type r12 0u8 r27 r29 into r31 as LiquidationAuth.record;
    call credits.aleo/transfer_public_to_private self.caller r22 into r32 r33;
    async borrow_credits r33 r0.token_type r2 r3 r12 r20 r28 into r34;
    output r30 as DebtPosition.record;
    output r31 as LiquidationAuth.record;
    output r34 as dara_lend_v8_credits.aleo/borrow_credits.future;

finalize borrow_credits:
    input r0 as credits.aleo/transfer_public_to_private.future;
    input r1 as u8.public;
    input r2 as u64.public;
    input r3 as u64.public;
    input r4 as u128.public;
    input r5 as u128.public;
    input r6 as field.public;
    await r0;
    get.or_use credits_paused[0u8] false into r7;
    not r7 into r8;
    assert.eq r8 true;
    get oracle_price[r1] into r9;
    assert.eq r2 r9;
    get oracle_price[0u8] into r10;
    assert.eq r3 r10;
    get.or_use pool_total_borrowed[0u8] 0u128 into r11;
    add r11 r4 into r12;
    lte r12 100000000000u128 into r13;
    assert.eq r13 true;
    set r12 into pool_total_borrowed[0u8];
    get.or_use total_fees_collected[0u8] 0u128 into r14;
    add r14 r5 into r15;
    set r15 into total_fees_collected[0u8];
    get.or_use loan_count[0u8] 0u64 into r16;
    add r16 1u64 into r17;
    set r17 into loan_count[0u8];
    hash.bhp256 r6 into r18 as field;
    set true into active_loans[r18];

function repay_credits_usdcx:
    input r0 as DebtPosition.record;
    input r1 as credits.aleo/credits.record;
    is.eq r0.debt_token 0u8 into r2;
    assert.eq r2 true;
    is.eq r0.collateral_token 1u8 into r3;
    assert.eq r3 true;
    cast r0.debt_amount into r4 as u64;
    cast self.signer r0.debt_amount 0u64 r0.collateral_amount_u128 1u8 r0.loan_id into r5 as RepaymentReceipt.record;
    call credits.aleo/transfer_private_to_public r1 dara_lend_v8_credits.aleo r4 into r6 r7;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private self.caller r0.collateral_amount_u128 into r8 r9 r10;
    async repay_credits_usdcx r7 r10 r0.debt_amount r0.collateral_amount_u128 r0.loan_id into r11;
    output r5 as RepaymentReceipt.record;
    output r11 as dara_lend_v8_credits.aleo/repay_credits_usdcx.future;

finalize repay_credits_usdcx:
    input r0 as credits.aleo/transfer_private_to_public.future;
    input r1 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r2 as u128.public;
    input r3 as u128.public;
    input r4 as field.public;
    await r0;
    await r1;
    get pool_total_borrowed[0u8] into r5;
    sub r5 r2 into r6;
    set r6 into pool_total_borrowed[0u8];
    get loan_count[0u8] into r7;
    sub r7 1u64 into r8;
    set r8 into loan_count[0u8];
    get vault_collateral_usdcx[0u8] into r9;
    sub r9 r3 into r10;
    set r10 into vault_collateral_usdcx[0u8];
    hash.bhp256 r4 into r11 as field;
    set false into active_loans[r11];

function repay_credits_usad:
    input r0 as DebtPosition.record;
    input r1 as credits.aleo/credits.record;
    is.eq r0.debt_token 0u8 into r2;
    assert.eq r2 true;
    is.eq r0.collateral_token 2u8 into r3;
    assert.eq r3 true;
    cast r0.debt_amount into r4 as u64;
    cast self.signer r0.debt_amount 0u64 r0.collateral_amount_u128 2u8 r0.loan_id into r5 as RepaymentReceipt.record;
    call credits.aleo/transfer_private_to_public r1 dara_lend_v8_credits.aleo r4 into r6 r7;
    call test_usad_stablecoin.aleo/transfer_public_to_private self.caller r0.collateral_amount_u128 into r8 r9 r10;
    async repay_credits_usad r7 r10 r0.debt_amount r0.collateral_amount_u128 r0.loan_id into r11;
    output r5 as RepaymentReceipt.record;
    output r11 as dara_lend_v8_credits.aleo/repay_credits_usad.future;

finalize repay_credits_usad:
    input r0 as credits.aleo/transfer_private_to_public.future;
    input r1 as test_usad_stablecoin.aleo/transfer_public_to_private.future;
    input r2 as u128.public;
    input r3 as u128.public;
    input r4 as field.public;
    await r0;
    await r1;
    get pool_total_borrowed[0u8] into r5;
    sub r5 r2 into r6;
    set r6 into pool_total_borrowed[0u8];
    get loan_count[0u8] into r7;
    sub r7 1u64 into r8;
    set r8 into loan_count[0u8];
    get vault_collateral_usad[0u8] into r9;
    sub r9 r3 into r10;
    set r10 into vault_collateral_usad[0u8];
    hash.bhp256 r4 into r11 as field;
    set false into active_loans[r11];

function liquidate_usdcx:
    input r0 as LiquidationAuth.record;
    input r1 as u64.private;
    lte r1 r0.liquidation_price into r2;
    assert.eq r2 true;
    is.eq r0.collateral_token 1u8 into r3;
    assert.eq r3 true;
    mul r0.collateral_amount_u128 500u128 into r4;
    div r4 10000u128 into r5;
    add r0.collateral_amount_u128 r5 into r6;
    cast self.signer r0.loan_id 0u64 r6 1u8 r0.debt_amount into r7 as LiquidationReceipt.record;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private self.caller r6 into r8 r9 r10;
    async liquidate_usdcx r10 r1 r6 r0.debt_amount r0.loan_id into r11;
    output r7 as LiquidationReceipt.record;
    output r11 as dara_lend_v8_credits.aleo/liquidate_usdcx.future;

finalize liquidate_usdcx:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as u64.public;
    input r2 as u128.public;
    input r3 as u128.public;
    input r4 as field.public;
    await r0;
    get oracle_price[1u8] into r5;
    assert.eq r1 r5;
    get vault_collateral_usdcx[0u8] into r6;
    sub r6 r2 into r7;
    set r7 into vault_collateral_usdcx[0u8];
    get pool_total_borrowed[0u8] into r8;
    sub r8 r3 into r9;
    set r9 into pool_total_borrowed[0u8];
    get loan_count[0u8] into r10;
    sub r10 1u64 into r11;
    set r11 into loan_count[0u8];
    hash.bhp256 r4 into r12 as field;
    set false into active_loans[r12];

function liquidate_usad:
    input r0 as LiquidationAuth.record;
    input r1 as u64.private;
    lte r1 r0.liquidation_price into r2;
    assert.eq r2 true;
    is.eq r0.collateral_token 2u8 into r3;
    assert.eq r3 true;
    mul r0.collateral_amount_u128 500u128 into r4;
    div r4 10000u128 into r5;
    add r0.collateral_amount_u128 r5 into r6;
    cast self.signer r0.loan_id 0u64 r6 2u8 r0.debt_amount into r7 as LiquidationReceipt.record;
    call test_usad_stablecoin.aleo/transfer_public_to_private self.caller r6 into r8 r9 r10;
    async liquidate_usad r10 r1 r6 r0.debt_amount r0.loan_id into r11;
    output r7 as LiquidationReceipt.record;
    output r11 as dara_lend_v8_credits.aleo/liquidate_usad.future;

finalize liquidate_usad:
    input r0 as test_usad_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as u64.public;
    input r2 as u128.public;
    input r3 as u128.public;
    input r4 as field.public;
    await r0;
    get oracle_price[2u8] into r5;
    assert.eq r1 r5;
    get vault_collateral_usad[0u8] into r6;
    sub r6 r2 into r7;
    set r7 into vault_collateral_usad[0u8];
    get pool_total_borrowed[0u8] into r8;
    sub r8 r3 into r9;
    set r9 into pool_total_borrowed[0u8];
    get loan_count[0u8] into r10;
    sub r10 1u64 into r11;
    set r11 into loan_count[0u8];
    hash.bhp256 r4 into r12 as field;
    set false into active_loans[r12];

function withdraw_usdcx_collateral:
    input r0 as CollateralReceipt.record;
    is.eq r0.token_type 1u8 into r1;
    assert.eq r1 true;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private self.caller r0.collateral_amount_u128 into r2 r3 r4;
    async withdraw_usdcx_collateral r4 r0.collateral_amount_u128 into r5;
    output r5 as dara_lend_v8_credits.aleo/withdraw_usdcx_collateral.future;

finalize withdraw_usdcx_collateral:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as u128.public;
    await r0;
    get vault_collateral_usdcx[0u8] into r2;
    sub r2 r1 into r3;
    set r3 into vault_collateral_usdcx[0u8];

function withdraw_usad_collateral:
    input r0 as CollateralReceipt.record;
    is.eq r0.token_type 2u8 into r1;
    assert.eq r1 true;
    call test_usad_stablecoin.aleo/transfer_public_to_private self.caller r0.collateral_amount_u128 into r2 r3 r4;
    async withdraw_usad_collateral r4 r0.collateral_amount_u128 into r5;
    output r5 as dara_lend_v8_credits.aleo/withdraw_usad_collateral.future;

finalize withdraw_usad_collateral:
    input r0 as test_usad_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as u128.public;
    await r0;
    get vault_collateral_usad[0u8] into r2;
    sub r2 r1 into r3;
    set r3 into vault_collateral_usad[0u8];

constructor:
    set aleo1fcvvertrnraperrdn7p048vlddlxpd89xszelsgyvwnfyxhmcc8skn2cs8 into credits_admin[0u8];
    set 1000000u64 into oracle_price[0u8];
    set 1000000u64 into oracle_price[1u8];
    set 1000000u64 into oracle_price[2u8];
    set false into credits_paused[0u8];
