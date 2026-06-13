import credits.aleo;
import merkle_tree.aleo;
import test_usdcx_multisig_core.aleo;
import test_usdcx_freezelist.aleo;
import test_usdcx_stablecoin.aleo;
import test_usad_multisig_core.aleo;
import test_usad_freezelist.aleo;
import test_usad_stablecoin.aleo;

program dara_flash_v1.aleo;

record FlashLoanReceipt:
    owner as address.private;
    borrow_amount as u128.private;
    borrow_token as u8.private;
    collateral_amount as u128.private;
    collateral_token as u8.private;
    fee_amount as u128.private;
    nonce_hash as field.private;

record FlashRepayReceipt:
    owner as address.private;
    amount_repaid as u128.private;
    collateral_returned as u128.private;
    collateral_token as u8.private;
    nonce_hash as field.private;

mapping flash_admin:
    key as u8.public;
    value as address.public;

mapping flash_paused:
    key as u8.public;
    value as boolean.public;

mapping oracle_price:
    key as u8.public;
    value as u64.public;

mapping price_round:
    key as u8.public;
    value as u64.public;

mapping price_update_block:
    key as u8.public;
    value as u32.public;

mapping price_history:
    key as u8.public;
    value as u64.public;

mapping total_flash_loans:
    key as u8.public;
    value as u64.public;

mapping total_flash_volume:
    key as u8.public;
    value as u128.public;

mapping total_fees_earned:
    key as u8.public;
    value as u128.public;

mapping active_flash_count:
    key as u8.public;
    value as u64.public;

mapping used_nonces:
    key as field.public;
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
    output r6 as dara_flash_v1.aleo/update_oracle_price.future;

finalize update_oracle_price:
    input r0 as address.public;
    input r1 as u8.public;
    input r2 as u64.public;
    input r3 as u64.public;
    get flash_admin[0u8] into r4;
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

function flash_borrow_usdcx:
    input r0 as credits.aleo/credits.record;
    input r1 as u64.private;
    input r2 as u128.private;
    input r3 as u64.private;
    input r4 as field.private;
    gte r2 100000u128 into r5;
    assert.eq r5 true;
    lte r2 10000000000u128 into r6;
    assert.eq r6 true;
    gte r1 100000u64 into r7;
    assert.eq r7 true;
    mul r2 9u128 into r8;
    div r8 10000u128 into r9;
    hash.bhp256 self.signer into r10 as field;
    add r4 r10 into r11;
    hash.bhp256 r11 into r12 as field;
    cast r1 into r13 as u128;
    cast self.signer r2 1u8 r13 0u8 r9 r12 into r14 as FlashLoanReceipt.record;
    call credits.aleo/transfer_private_to_public r0 dara_flash_v1.aleo r1 into r15 r16;
    async flash_borrow_usdcx r16 r12 r3 r1 r2 into r17;
    output r14 as FlashLoanReceipt.record;
    output r17 as dara_flash_v1.aleo/flash_borrow_usdcx.future;

finalize flash_borrow_usdcx:
    input r0 as credits.aleo/transfer_private_to_public.future;
    input r1 as field.public;
    input r2 as u64.public;
    input r3 as u64.public;
    input r4 as u128.public;
    await r0;
    get.or_use flash_paused[0u8] false into r5;
    not r5 into r6;
    assert.eq r6 true;
    get.or_use used_nonces[r1] false into r7;
    not r7 into r8;
    assert.eq r8 true;
    set true into used_nonces[r1];
    get oracle_price[0u8] into r9;
    assert.eq r2 r9;
    cast r3 into r10 as u128;
    cast r2 into r11 as u128;
    mul r10 r11 into r12;
    div r12 1000000u128 into r13;
    mul r4 10200u128 into r14;
    div r14 10000u128 into r15;
    gte r13 r15 into r16;
    assert.eq r16 true;
    get.or_use total_flash_loans[0u8] 0u64 into r17;
    add r17 1u64 into r18;
    set r18 into total_flash_loans[0u8];
    get.or_use total_flash_volume[0u8] 0u128 into r19;
    add r19 r4 into r20;
    set r20 into total_flash_volume[0u8];
    get.or_use active_flash_count[0u8] 0u64 into r21;
    add r21 1u64 into r22;
    set r22 into active_flash_count[0u8];

function flash_claim_usdcx:
    input r0 as FlashLoanReceipt.record;
    is.eq r0.borrow_token 1u8 into r1;
    assert.eq r1 true;
    cast r0.owner r0.borrow_amount r0.borrow_token r0.collateral_amount r0.collateral_token r0.fee_amount r0.nonce_hash into r2 as FlashLoanReceipt.record;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private self.caller r0.borrow_amount into r3 r4 r5;
    async flash_claim_usdcx r5 into r6;
    output r2 as FlashLoanReceipt.record;
    output r6 as dara_flash_v1.aleo/flash_claim_usdcx.future;

finalize flash_claim_usdcx:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    await r0;

function flash_repay_usdcx:
    input r0 as FlashLoanReceipt.record;
    input r1 as test_usdcx_stablecoin.aleo/Token.record;
    input r2 as [test_usdcx_stablecoin.aleo/MerkleProof; 2u32].private;
    is.eq r0.borrow_token 1u8 into r3;
    assert.eq r3 true;
    add r0.borrow_amount r0.fee_amount into r4;
    cast self.signer r4 r0.collateral_amount r0.collateral_token r0.nonce_hash into r5 as FlashRepayReceipt.record;
    call test_usdcx_stablecoin.aleo/transfer_private_to_public dara_flash_v1.aleo r4 r1 r2 into r6 r7 r8;
    async flash_repay_usdcx r8 r0.fee_amount into r9;
    output r5 as FlashRepayReceipt.record;
    output r9 as dara_flash_v1.aleo/flash_repay_usdcx.future;

finalize flash_repay_usdcx:
    input r0 as test_usdcx_stablecoin.aleo/transfer_private_to_public.future;
    input r1 as u128.public;
    await r0;
    get.or_use total_fees_earned[0u8] 0u128 into r2;
    add r2 r1 into r3;
    set r3 into total_fees_earned[0u8];
    get.or_use active_flash_count[0u8] 0u64 into r4;
    gt r4 0u64 into r5;
    sub r4 1u64 into r6;
    ternary r5 r6 0u64 into r7;
    set r7 into active_flash_count[0u8];

function flash_withdraw_aleo:
    input r0 as FlashRepayReceipt.record;
    is.eq r0.collateral_token 0u8 into r1;
    assert.eq r1 true;
    cast r0.collateral_returned into r2 as u64;
    call credits.aleo/transfer_public_to_private self.caller r2 into r3 r4;
    async flash_withdraw_aleo r4 into r5;
    output r5 as dara_flash_v1.aleo/flash_withdraw_aleo.future;

finalize flash_withdraw_aleo:
    input r0 as credits.aleo/transfer_public_to_private.future;
    await r0;

function flash_borrow_aleo:
    input r0 as test_usdcx_stablecoin.aleo/Token.record;
    input r1 as [test_usdcx_stablecoin.aleo/MerkleProof; 2u32].private;
    input r2 as u128.private;
    input r3 as u64.private;
    input r4 as u64.private;
    input r5 as field.private;
    gte r2 100000u128 into r6;
    assert.eq r6 true;
    gte r3 100000u64 into r7;
    assert.eq r7 true;
    cast r3 into r8 as u128;
    mul r8 9u128 into r9;
    div r9 10000u128 into r10;
    hash.bhp256 self.signer into r11 as field;
    add r5 r11 into r12;
    hash.bhp256 r12 into r13 as field;
    cast self.signer r8 0u8 r2 1u8 r10 r13 into r14 as FlashLoanReceipt.record;
    call test_usdcx_stablecoin.aleo/transfer_private_to_public dara_flash_v1.aleo r2 r0 r1 into r15 r16 r17;
    async flash_borrow_aleo r17 r13 r4 r8 r2 into r18;
    output r14 as FlashLoanReceipt.record;
    output r18 as dara_flash_v1.aleo/flash_borrow_aleo.future;

finalize flash_borrow_aleo:
    input r0 as test_usdcx_stablecoin.aleo/transfer_private_to_public.future;
    input r1 as field.public;
    input r2 as u64.public;
    input r3 as u128.public;
    input r4 as u128.public;
    await r0;
    get.or_use flash_paused[0u8] false into r5;
    not r5 into r6;
    assert.eq r6 true;
    get.or_use used_nonces[r1] false into r7;
    not r7 into r8;
    assert.eq r8 true;
    set true into used_nonces[r1];
    get oracle_price[0u8] into r9;
    assert.eq r2 r9;
    cast r2 into r10 as u128;
    mul r3 r10 into r11;
    div r11 1000000u128 into r12;
    mul r12 10200u128 into r13;
    div r13 10000u128 into r14;
    gte r4 r14 into r15;
    assert.eq r15 true;
    get.or_use total_flash_loans[0u8] 0u64 into r16;
    add r16 1u64 into r17;
    set r17 into total_flash_loans[0u8];
    get.or_use total_flash_volume[0u8] 0u128 into r18;
    add r18 r3 into r19;
    set r19 into total_flash_volume[0u8];
    get.or_use active_flash_count[0u8] 0u64 into r20;
    add r20 1u64 into r21;
    set r21 into active_flash_count[0u8];

function flash_claim_aleo:
    input r0 as FlashLoanReceipt.record;
    is.eq r0.borrow_token 0u8 into r1;
    assert.eq r1 true;
    cast r0.borrow_amount into r2 as u64;
    cast r0.owner r0.borrow_amount r0.borrow_token r0.collateral_amount r0.collateral_token r0.fee_amount r0.nonce_hash into r3 as FlashLoanReceipt.record;
    call credits.aleo/transfer_public_to_private self.caller r2 into r4 r5;
    async flash_claim_aleo r5 into r6;
    output r3 as FlashLoanReceipt.record;
    output r6 as dara_flash_v1.aleo/flash_claim_aleo.future;

finalize flash_claim_aleo:
    input r0 as credits.aleo/transfer_public_to_private.future;
    await r0;

function flash_repay_aleo:
    input r0 as FlashLoanReceipt.record;
    input r1 as credits.aleo/credits.record;
    is.eq r0.borrow_token 0u8 into r2;
    assert.eq r2 true;
    add r0.borrow_amount r0.fee_amount into r3;
    cast r3 into r4 as u64;
    cast r4 into r5 as u128;
    cast self.signer r5 r0.collateral_amount r0.collateral_token r0.nonce_hash into r6 as FlashRepayReceipt.record;
    call credits.aleo/transfer_private_to_public r1 dara_flash_v1.aleo r4 into r7 r8;
    async flash_repay_aleo r8 r0.fee_amount into r9;
    output r6 as FlashRepayReceipt.record;
    output r9 as dara_flash_v1.aleo/flash_repay_aleo.future;

finalize flash_repay_aleo:
    input r0 as credits.aleo/transfer_private_to_public.future;
    input r1 as u128.public;
    await r0;
    get.or_use total_fees_earned[0u8] 0u128 into r2;
    add r2 r1 into r3;
    set r3 into total_fees_earned[0u8];
    get.or_use active_flash_count[0u8] 0u64 into r4;
    gt r4 0u64 into r5;
    sub r4 1u64 into r6;
    ternary r5 r6 0u64 into r7;
    set r7 into active_flash_count[0u8];

function flash_withdraw_usdcx:
    input r0 as FlashRepayReceipt.record;
    is.eq r0.collateral_token 1u8 into r1;
    assert.eq r1 true;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private self.caller r0.collateral_returned into r2 r3 r4;
    async flash_withdraw_usdcx r4 into r5;
    output r5 as dara_flash_v1.aleo/flash_withdraw_usdcx.future;

finalize flash_withdraw_usdcx:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    await r0;

function pause_flash:
    async pause_flash self.caller into r0;
    output r0 as dara_flash_v1.aleo/pause_flash.future;

finalize pause_flash:
    input r0 as address.public;
    get flash_admin[0u8] into r1;
    assert.eq r0 r1;
    set true into flash_paused[0u8];

function resume_flash:
    async resume_flash self.caller into r0;
    output r0 as dara_flash_v1.aleo/resume_flash.future;

finalize resume_flash:
    input r0 as address.public;
    get flash_admin[0u8] into r1;
    assert.eq r0 r1;
    set false into flash_paused[0u8];

constructor:
    set aleo1fcvvertrnraperrdn7p048vlddlxpd89xszelsgyvwnfyxhmcc8skn2cs8 into flash_admin[0u8];
    set false into flash_paused[0u8];
    set 1000000u64 into oracle_price[0u8];
    set 1000000u64 into oracle_price[1u8];
    set 1000000u64 into oracle_price[2u8];
    set 1000000u64 into price_history[0u8];
    set 0u64 into total_flash_loans[0u8];
    set 0u128 into total_flash_volume[0u8];
    set 0u128 into total_fees_earned[0u8];
    set 0u64 into active_flash_count[0u8];
