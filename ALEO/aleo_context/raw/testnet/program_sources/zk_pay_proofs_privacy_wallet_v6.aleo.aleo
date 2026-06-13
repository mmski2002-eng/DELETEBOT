import credits.aleo;
import merkle_tree.aleo;
import test_usdcx_multisig_core.aleo;
import test_usdcx_freezelist.aleo;
import test_usdcx_stablecoin.aleo;
import test_usad_multisig_core.aleo;
import test_usad_freezelist.aleo;
import test_usad_stablecoin.aleo;

program zk_pay_proofs_privacy_wallet_v6.aleo;

record PayerReceipt:
    owner as address.private;
    merchant as address.private;
    receipt_hash as field.private;
    invoice_hash as field.private;
    amount as u64.private;
    token_type as u8.private;
    payer_note as field.private;
    timestamp as u64.private;

record MerchantReceipt:
    owner as address.private;
    receipt_hash as field.private;
    invoice_hash as field.private;
    amount as u64.private;
    token_type as u8.private;
    merchant_note as field.private;

record BurnerWalletRecord:
    owner as address.private;
    burner_address as address.private;
    password_part as field.private;
    pk_part_1 as field.private;
    pk_part_2 as field.private;
    pk_part_3 as field.private;
    pk_part_4 as field.private;
    pk_part_5 as field.private;
    pk_part_6 as field.private;
    pk_part_7 as field.private;
    pk_part_8 as field.private;
    pk_part_9 as field.private;
    pk_part_10 as field.private;

record CardProfileRecord:
    owner as address.private;
    card_number_hash as field.private;
    profile_version as u8.private;
    encrypted_card_number as [field; 6u32].private;
    encrypted_card_address as [field; 10u32].private;
    encrypted_label as [field; 10u32].private;
    encrypted_hint as [field; 8u32].private;

record GiftCardRecord:
    owner as address.private;
    gift_card_address as address.private;
    gift_private_key as [field; 8u32].private;
    label as field.private;

struct OracleQuote:
    original_amount_micro as u64;
    converted_amount_micro as u64;
    from_token_type as u8;
    to_token_type as u8;
    expires_at as u32;

mapping oracle_address:
    key as u8.public;
    value as address.public;

function backup_password:
    input r0 as field.private;
    cast self.caller self.caller r0 0field 0field 0field 0field 0field 0field 0field 0field 0field 0field into r1 as BurnerWalletRecord.record;
    output r1 as BurnerWalletRecord.record;

function backup_burner_wallet:
    input r0 as address.private;
    input r1 as field.private;
    input r2 as field.private;
    input r3 as field.private;
    input r4 as field.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.private;
    input r9 as field.private;
    input r10 as field.private;
    input r11 as field.private;
    cast self.caller r0 r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11 into r12 as BurnerWalletRecord.record;
    output r12 as BurnerWalletRecord.record;

function create_card_profile:
    input r0 as field.private;
    input r1 as u8.public;
    input r2 as [field; 6u32].private;
    input r3 as [field; 10u32].private;
    input r4 as [field; 10u32].private;
    input r5 as [field; 8u32].private;
    cast self.caller r0 r1 r2 r3 r4 r5 into r6 as CardProfileRecord.record;
    output r6 as CardProfileRecord.record;

function create_gift_card_record:
    input r0 as address.private;
    input r1 as [field; 8u32].private;
    input r2 as field.private;
    cast self.caller r0 r1 r2 into r3 as GiftCardRecord.record;
    output r3 as GiftCardRecord.record;

function delete_card_profile:
    input r0 as CardProfileRecord.record;
    assert.eq r0.owner self.caller;

function set_oracle_address:
    input r0 as address.public;
    assert.eq self.caller aleo1d5hc09stpfpp3y7xhw9v306th9hrjt6qj8jj3h0rxjwv2y4rrypspfycge;
    async set_oracle_address r0 into r1;
    output r1 as zk_pay_proofs_privacy_wallet_v6.aleo/set_oracle_address.future;

finalize set_oracle_address:
    input r0 as address.public;
    set r0 into oracle_address[0u8];

function pay_invoice_credits_via_usdcx:
    input r0 as test_usdcx_stablecoin.aleo/Token.record;
    input r1 as address.private;
    input r2 as address.public;
    input r3 as u64.private;
    input r4 as u128.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.private;
    input r9 as field.public;
    input r10 as [test_usdcx_stablecoin.aleo/MerkleProof; 2u32].private;
    input r11 as signature.private;
    input r12 as u32.public;
    call test_usdcx_stablecoin.aleo/transfer_private r1 r4 r0 r10 into r13 r14 r15 r16;
    cast r1 into r17 as field;
    cast r3 into r18 as field;
    hash.bhp256 r17 into r19 as field;
    hash.bhp256 r18 into r20 as field;
    hash.bhp256 r5 into r21 as field;
    add r19 r20 into r22;
    add r22 r21 into r23;
    cast r4 into r24 as u64;
    cast r3 r24 0u8 1u8 r12 into r25 as OracleQuote;
    hash.bhp256 r25 into r26 as field;
    hash.bhp256 r5 into r27 as scalar;
    commit.bhp256 r6 r27 into r28 as field;
    cast r4 into r29 as u64;
    cast r2 r1 r28 r23 r29 1u8 r7 0u64 into r30 as PayerReceipt.record;
    cast r4 into r31 as u64;
    cast r1 r28 r23 r31 1u8 r8 into r32 as MerchantReceipt.record;
    async pay_invoice_credits_via_usdcx r16 r11 r26 r12 into r33;
    output r14 as test_usdcx_stablecoin.aleo/Token.record;
    output r15 as test_usdcx_stablecoin.aleo/Token.record;
    output r13 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r30 as PayerReceipt.record;
    output r32 as MerchantReceipt.record;
    output r33 as zk_pay_proofs_privacy_wallet_v6.aleo/pay_invoice_credits_via_usdcx.future;

finalize pay_invoice_credits_via_usdcx:
    input r0 as test_usdcx_stablecoin.aleo/transfer_private.future;
    input r1 as signature.public;
    input r2 as field.public;
    input r3 as u32.public;
    await r0;
    get oracle_address[0u8] into r4;
    sign.verify r1 r4 r2 into r5;
    assert.eq r5 true;
    is.neq r3 0u32 into r6;
    branch.eq r6 false to end_then_0_0;
    lte block.height r3 into r7;
    assert.eq r7 true;
    branch.eq true true to end_otherwise_0_1;
    position end_then_0_0;
    position end_otherwise_0_1;

function pay_invoice_credits_via_usad:
    input r0 as test_usad_stablecoin.aleo/Token.record;
    input r1 as address.private;
    input r2 as address.public;
    input r3 as u64.private;
    input r4 as u128.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.private;
    input r9 as field.public;
    input r10 as [test_usad_stablecoin.aleo/MerkleProof; 2u32].private;
    input r11 as signature.private;
    input r12 as u32.public;
    call test_usad_stablecoin.aleo/transfer_private r1 r4 r0 r10 into r13 r14 r15 r16;
    cast r1 into r17 as field;
    cast r3 into r18 as field;
    hash.bhp256 r17 into r19 as field;
    hash.bhp256 r18 into r20 as field;
    hash.bhp256 r5 into r21 as field;
    add r19 r20 into r22;
    add r22 r21 into r23;
    cast r4 into r24 as u64;
    cast r3 r24 0u8 2u8 r12 into r25 as OracleQuote;
    hash.bhp256 r25 into r26 as field;
    hash.bhp256 r5 into r27 as scalar;
    commit.bhp256 r6 r27 into r28 as field;
    cast r4 into r29 as u64;
    cast r2 r1 r28 r23 r29 2u8 r7 0u64 into r30 as PayerReceipt.record;
    cast r4 into r31 as u64;
    cast r1 r28 r23 r31 2u8 r8 into r32 as MerchantReceipt.record;
    async pay_invoice_credits_via_usad r16 r11 r26 r12 into r33;
    output r14 as test_usad_stablecoin.aleo/Token.record;
    output r15 as test_usad_stablecoin.aleo/Token.record;
    output r13 as test_usad_stablecoin.aleo/ComplianceRecord.record;
    output r30 as PayerReceipt.record;
    output r32 as MerchantReceipt.record;
    output r33 as zk_pay_proofs_privacy_wallet_v6.aleo/pay_invoice_credits_via_usad.future;

finalize pay_invoice_credits_via_usad:
    input r0 as test_usad_stablecoin.aleo/transfer_private.future;
    input r1 as signature.public;
    input r2 as field.public;
    input r3 as u32.public;
    await r0;
    get oracle_address[0u8] into r4;
    sign.verify r1 r4 r2 into r5;
    assert.eq r5 true;
    is.neq r3 0u32 into r6;
    branch.eq r6 false to end_then_0_2;
    lte block.height r3 into r7;
    assert.eq r7 true;
    branch.eq true true to end_otherwise_0_3;
    position end_then_0_2;
    position end_otherwise_0_3;

function pay_invoice_usdcx_via_credits:
    input r0 as credits.aleo/credits.record;
    input r1 as address.private;
    input r2 as address.public;
    input r3 as u128.private;
    input r4 as u64.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.private;
    input r9 as field.public;
    input r10 as signature.private;
    input r11 as u32.public;
    call credits.aleo/transfer_private r0 r1 r4 into r12 r13;
    cast r1 into r14 as field;
    cast r3 into r15 as field;
    hash.bhp256 r14 into r16 as field;
    hash.bhp256 r15 into r17 as field;
    hash.bhp256 r5 into r18 as field;
    add r16 r17 into r19;
    add r19 r18 into r20;
    cast r3 into r21 as u64;
    cast r21 r4 1u8 0u8 r11 into r22 as OracleQuote;
    hash.bhp256 r22 into r23 as field;
    hash.bhp256 r5 into r24 as scalar;
    commit.bhp256 r6 r24 into r25 as field;
    cast r2 r1 r25 r20 r4 0u8 r7 0u64 into r26 as PayerReceipt.record;
    cast r1 r25 r20 r4 0u8 r8 into r27 as MerchantReceipt.record;
    async pay_invoice_usdcx_via_credits r10 r23 r11 into r28;
    output r12 as credits.aleo/credits.record;
    output r13 as credits.aleo/credits.record;
    output r26 as PayerReceipt.record;
    output r27 as MerchantReceipt.record;
    output r28 as zk_pay_proofs_privacy_wallet_v6.aleo/pay_invoice_usdcx_via_credits.future;

finalize pay_invoice_usdcx_via_credits:
    input r0 as signature.public;
    input r1 as field.public;
    input r2 as u32.public;
    get oracle_address[0u8] into r3;
    sign.verify r0 r3 r1 into r4;
    assert.eq r4 true;
    is.neq r2 0u32 into r5;
    branch.eq r5 false to end_then_0_4;
    lte block.height r2 into r6;
    assert.eq r6 true;
    branch.eq true true to end_otherwise_0_5;
    position end_then_0_4;
    position end_otherwise_0_5;

function pay_invoice_usdcx_via_usad:
    input r0 as test_usad_stablecoin.aleo/Token.record;
    input r1 as address.private;
    input r2 as address.public;
    input r3 as u128.private;
    input r4 as u128.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.private;
    input r9 as field.public;
    input r10 as [test_usad_stablecoin.aleo/MerkleProof; 2u32].private;
    input r11 as signature.private;
    input r12 as u32.public;
    call test_usad_stablecoin.aleo/transfer_private r1 r4 r0 r10 into r13 r14 r15 r16;
    cast r1 into r17 as field;
    cast r3 into r18 as field;
    hash.bhp256 r17 into r19 as field;
    hash.bhp256 r18 into r20 as field;
    hash.bhp256 r5 into r21 as field;
    add r19 r20 into r22;
    add r22 r21 into r23;
    cast r3 into r24 as u64;
    cast r4 into r25 as u64;
    cast r24 r25 1u8 2u8 r12 into r26 as OracleQuote;
    hash.bhp256 r26 into r27 as field;
    hash.bhp256 r5 into r28 as scalar;
    commit.bhp256 r6 r28 into r29 as field;
    cast r4 into r30 as u64;
    cast r2 r1 r29 r23 r30 2u8 r7 0u64 into r31 as PayerReceipt.record;
    cast r4 into r32 as u64;
    cast r1 r29 r23 r32 2u8 r8 into r33 as MerchantReceipt.record;
    async pay_invoice_usdcx_via_usad r16 r11 r27 r12 into r34;
    output r14 as test_usad_stablecoin.aleo/Token.record;
    output r15 as test_usad_stablecoin.aleo/Token.record;
    output r13 as test_usad_stablecoin.aleo/ComplianceRecord.record;
    output r31 as PayerReceipt.record;
    output r33 as MerchantReceipt.record;
    output r34 as zk_pay_proofs_privacy_wallet_v6.aleo/pay_invoice_usdcx_via_usad.future;

finalize pay_invoice_usdcx_via_usad:
    input r0 as test_usad_stablecoin.aleo/transfer_private.future;
    input r1 as signature.public;
    input r2 as field.public;
    input r3 as u32.public;
    await r0;
    get oracle_address[0u8] into r4;
    sign.verify r1 r4 r2 into r5;
    assert.eq r5 true;
    is.neq r3 0u32 into r6;
    branch.eq r6 false to end_then_0_6;
    lte block.height r3 into r7;
    assert.eq r7 true;
    branch.eq true true to end_otherwise_0_7;
    position end_then_0_6;
    position end_otherwise_0_7;

function pay_invoice_usad_via_credits:
    input r0 as credits.aleo/credits.record;
    input r1 as address.private;
    input r2 as address.public;
    input r3 as u128.private;
    input r4 as u64.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.private;
    input r9 as field.public;
    input r10 as signature.private;
    input r11 as u32.public;
    call credits.aleo/transfer_private r0 r1 r4 into r12 r13;
    cast r1 into r14 as field;
    cast r3 into r15 as field;
    hash.bhp256 r14 into r16 as field;
    hash.bhp256 r15 into r17 as field;
    hash.bhp256 r5 into r18 as field;
    add r16 r17 into r19;
    add r19 r18 into r20;
    cast r3 into r21 as u64;
    cast r21 r4 2u8 0u8 r11 into r22 as OracleQuote;
    hash.bhp256 r22 into r23 as field;
    hash.bhp256 r5 into r24 as scalar;
    commit.bhp256 r6 r24 into r25 as field;
    cast r2 r1 r25 r20 r4 0u8 r7 0u64 into r26 as PayerReceipt.record;
    cast r1 r25 r20 r4 0u8 r8 into r27 as MerchantReceipt.record;
    async pay_invoice_usad_via_credits r10 r23 r11 into r28;
    output r12 as credits.aleo/credits.record;
    output r13 as credits.aleo/credits.record;
    output r26 as PayerReceipt.record;
    output r27 as MerchantReceipt.record;
    output r28 as zk_pay_proofs_privacy_wallet_v6.aleo/pay_invoice_usad_via_credits.future;

finalize pay_invoice_usad_via_credits:
    input r0 as signature.public;
    input r1 as field.public;
    input r2 as u32.public;
    get oracle_address[0u8] into r3;
    sign.verify r0 r3 r1 into r4;
    assert.eq r4 true;
    is.neq r2 0u32 into r5;
    branch.eq r5 false to end_then_0_8;
    lte block.height r2 into r6;
    assert.eq r6 true;
    branch.eq true true to end_otherwise_0_9;
    position end_then_0_8;
    position end_otherwise_0_9;

function pay_invoice_usad_via_usdcx:
    input r0 as test_usdcx_stablecoin.aleo/Token.record;
    input r1 as address.private;
    input r2 as address.public;
    input r3 as u128.private;
    input r4 as u128.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.private;
    input r9 as field.public;
    input r10 as [test_usdcx_stablecoin.aleo/MerkleProof; 2u32].private;
    input r11 as signature.private;
    input r12 as u32.public;
    call test_usdcx_stablecoin.aleo/transfer_private r1 r4 r0 r10 into r13 r14 r15 r16;
    cast r1 into r17 as field;
    cast r3 into r18 as field;
    hash.bhp256 r17 into r19 as field;
    hash.bhp256 r18 into r20 as field;
    hash.bhp256 r5 into r21 as field;
    add r19 r20 into r22;
    add r22 r21 into r23;
    cast r3 into r24 as u64;
    cast r4 into r25 as u64;
    cast r24 r25 2u8 1u8 r12 into r26 as OracleQuote;
    hash.bhp256 r26 into r27 as field;
    hash.bhp256 r5 into r28 as scalar;
    commit.bhp256 r6 r28 into r29 as field;
    cast r4 into r30 as u64;
    cast r2 r1 r29 r23 r30 1u8 r7 0u64 into r31 as PayerReceipt.record;
    cast r4 into r32 as u64;
    cast r1 r29 r23 r32 1u8 r8 into r33 as MerchantReceipt.record;
    async pay_invoice_usad_via_usdcx r16 r11 r27 r12 into r34;
    output r14 as test_usdcx_stablecoin.aleo/Token.record;
    output r15 as test_usdcx_stablecoin.aleo/Token.record;
    output r13 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r31 as PayerReceipt.record;
    output r33 as MerchantReceipt.record;
    output r34 as zk_pay_proofs_privacy_wallet_v6.aleo/pay_invoice_usad_via_usdcx.future;

finalize pay_invoice_usad_via_usdcx:
    input r0 as test_usdcx_stablecoin.aleo/transfer_private.future;
    input r1 as signature.public;
    input r2 as field.public;
    input r3 as u32.public;
    await r0;
    get oracle_address[0u8] into r4;
    sign.verify r1 r4 r2 into r5;
    assert.eq r5 true;
    is.neq r3 0u32 into r6;
    branch.eq r6 false to end_then_0_10;
    lte block.height r3 into r7;
    assert.eq r7 true;
    branch.eq true true to end_otherwise_0_11;
    position end_then_0_10;
    position end_otherwise_0_11;

constructor:
    assert.eq program_owner aleo1yu926k0jqqzfv06js4jlsxnf2ejah47rfqsxmwfx6tvuxxgvrqpqdlq5y0;
