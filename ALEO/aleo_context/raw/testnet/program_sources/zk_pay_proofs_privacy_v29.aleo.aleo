import credits.aleo;
import merkle_tree.aleo;
import test_usdcx_multisig_core.aleo;
import test_usdcx_freezelist.aleo;
import test_usdcx_stablecoin.aleo;
import test_usad_multisig_core.aleo;
import test_usad_freezelist.aleo;
import test_usad_stablecoin.aleo;

program zk_pay_proofs_privacy_v29.aleo;

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

record Invoice:
    owner as address.private;
    invoice_hash as field.private;
    amount as u64.private;
    token_type as u8.private;
    invoice_type as u8.private;
    salt as field.private;
    title as field.private;
    memo as field.private;
    wallet_type as u8.private;

struct InvoiceData:
    expiry_height as u32;
    status as u8;
    invoice_type as u8;
    token_type as u8;
    wallet_type as u8;

mapping invoices:
    key as field.public;
    value as InvoiceData.public;

mapping salt_to_invoice:
    key as field.public;
    value as field.public;

function create_invoice:
    input r0 as address.private;
    input r1 as u64.private;
    input r2 as field.private;
    input r3 as field.private;
    input r4 as field.private;
    input r5 as u32.public;
    input r6 as u8.public;
    input r7 as u8.public;
    cast r0 into r8 as field;
    cast r1 into r9 as field;
    hash.bhp256 r8 into r10 as field;
    hash.bhp256 r9 into r11 as field;
    hash.bhp256 r2 into r12 as field;
    add r10 r11 into r13;
    add r13 r12 into r14;
    cast r0 r14 r1 0u8 r6 r2 r3 r4 r7 into r15 as Invoice.record;
    async create_invoice r5 r6 r7 r14 r2 into r16;
    output r15 as Invoice.record;
    output r14 as field.public;
    output r16 as zk_pay_proofs_privacy_v29.aleo/create_invoice.future;

finalize create_invoice:
    input r0 as u32.public;
    input r1 as u8.public;
    input r2 as u8.public;
    input r3 as field.public;
    input r4 as field.public;
    mul r0 360u32 into r5;
    is.neq r0 0u32 into r6;
    add block.height r5 into r7;
    ternary r6 r7 0u32 into r8;
    cast r8 0u8 r1 0u8 r2 into r9 as InvoiceData;
    set r9 into invoices[r3];
    set r3 into salt_to_invoice[r4];

function create_invoice_usdcx:
    input r0 as address.private;
    input r1 as u128.private;
    input r2 as field.private;
    input r3 as field.private;
    input r4 as field.private;
    input r5 as u32.public;
    input r6 as u8.public;
    input r7 as u8.public;
    cast r0 into r8 as field;
    cast r1 into r9 as field;
    hash.bhp256 r8 into r10 as field;
    hash.bhp256 r9 into r11 as field;
    hash.bhp256 r2 into r12 as field;
    add r10 r11 into r13;
    add r13 r12 into r14;
    cast r1 into r15 as u64;
    cast r0 r14 r15 1u8 r6 r2 r3 r4 r7 into r16 as Invoice.record;
    async create_invoice_usdcx r5 r6 r7 r14 r2 into r17;
    output r16 as Invoice.record;
    output r14 as field.public;
    output r17 as zk_pay_proofs_privacy_v29.aleo/create_invoice_usdcx.future;

finalize create_invoice_usdcx:
    input r0 as u32.public;
    input r1 as u8.public;
    input r2 as u8.public;
    input r3 as field.public;
    input r4 as field.public;
    mul r0 360u32 into r5;
    is.neq r0 0u32 into r6;
    add block.height r5 into r7;
    ternary r6 r7 0u32 into r8;
    cast r8 0u8 r1 1u8 r2 into r9 as InvoiceData;
    set r9 into invoices[r3];
    set r3 into salt_to_invoice[r4];

function create_invoice_usad:
    input r0 as address.private;
    input r1 as u128.private;
    input r2 as field.private;
    input r3 as field.private;
    input r4 as field.private;
    input r5 as u32.public;
    input r6 as u8.public;
    input r7 as u8.public;
    cast r0 into r8 as field;
    cast r1 into r9 as field;
    hash.bhp256 r8 into r10 as field;
    hash.bhp256 r9 into r11 as field;
    hash.bhp256 r2 into r12 as field;
    add r10 r11 into r13;
    add r13 r12 into r14;
    cast r1 into r15 as u64;
    cast r0 r14 r15 2u8 r6 r2 r3 r4 r7 into r16 as Invoice.record;
    async create_invoice_usad r5 r6 r7 r14 r2 into r17;
    output r16 as Invoice.record;
    output r14 as field.public;
    output r17 as zk_pay_proofs_privacy_v29.aleo/create_invoice_usad.future;

finalize create_invoice_usad:
    input r0 as u32.public;
    input r1 as u8.public;
    input r2 as u8.public;
    input r3 as field.public;
    input r4 as field.public;
    mul r0 360u32 into r5;
    is.neq r0 0u32 into r6;
    add block.height r5 into r7;
    ternary r6 r7 0u32 into r8;
    cast r8 0u8 r1 2u8 r2 into r9 as InvoiceData;
    set r9 into invoices[r3];
    set r3 into salt_to_invoice[r4];

function create_invoice_any:
    input r0 as address.private;
    input r1 as u128.private;
    input r2 as field.private;
    input r3 as field.private;
    input r4 as field.private;
    input r5 as u32.public;
    input r6 as u8.public;
    input r7 as u8.public;
    cast r0 into r8 as field;
    cast r1 into r9 as field;
    hash.bhp256 r8 into r10 as field;
    hash.bhp256 r9 into r11 as field;
    hash.bhp256 r2 into r12 as field;
    add r10 r11 into r13;
    add r13 r12 into r14;
    cast r1 into r15 as u64;
    cast r0 r14 r15 3u8 r6 r2 r3 r4 r7 into r16 as Invoice.record;
    async create_invoice_any r5 r6 r7 r14 r2 into r17;
    output r16 as Invoice.record;
    output r14 as field.public;
    output r17 as zk_pay_proofs_privacy_v29.aleo/create_invoice_any.future;

finalize create_invoice_any:
    input r0 as u32.public;
    input r1 as u8.public;
    input r2 as u8.public;
    input r3 as field.public;
    input r4 as field.public;
    mul r0 360u32 into r5;
    is.neq r0 0u32 into r6;
    add block.height r5 into r7;
    ternary r6 r7 0u32 into r8;
    cast r8 0u8 r1 3u8 r2 into r9 as InvoiceData;
    set r9 into invoices[r3];
    set r3 into salt_to_invoice[r4];

function pay_donation:
    input r0 as credits.aleo/credits.record;
    input r1 as address.private;
    input r2 as address.public;
    input r3 as u64.private;
    input r4 as field.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.public;
    gt r3 0u64 into r9;
    assert.eq r9 true;
    call credits.aleo/transfer_private r0 r1 r3 into r10 r11;
    cast r1 into r12 as field;
    hash.bhp256 r12 into r13 as field;
    hash.bhp256 0field into r14 as field;
    hash.bhp256 r4 into r15 as field;
    add r13 r14 into r16;
    add r16 r15 into r17;
    hash.bhp256 r4 into r18 as scalar;
    cast r3 into r19 as field;
    hash.bhp256 r19 into r20 as field;
    add r5 r20 into r21;
    add r21 6483909679030553276222748262902265455236698137743464346806854780005049792424field into r22;
    commit.bhp256 r22 r18 into r23 as field;
    cast r2 r1 r23 r17 r3 0u8 r6 0u64 into r24 as PayerReceipt.record;
    cast r1 r23 r17 r3 0u8 r7 into r25 as MerchantReceipt.record;
    async pay_donation r4 r17 into r26;
    output r10 as credits.aleo/credits.record;
    output r11 as credits.aleo/credits.record;
    output r24 as PayerReceipt.record;
    output r25 as MerchantReceipt.record;
    output r26 as zk_pay_proofs_privacy_v29.aleo/pay_donation.future;

finalize pay_donation:
    input r0 as field.public;
    input r1 as field.public;
    get salt_to_invoice[r0] into r2;
    assert.eq r1 r2;
    get invoices[r2] into r3;
    is.neq r3.token_type 3u8 into r4;
    branch.eq r4 false to end_then_0_0;
    assert.eq r3.token_type 0u8;
    branch.eq true true to end_otherwise_0_1;
    position end_then_0_0;
    position end_otherwise_0_1;
    assert.eq r3.invoice_type 2u8;
    assert.eq r3.status 0u8;
    is.neq r3.expiry_height 0u32 into r5;
    branch.eq r5 false to end_then_0_2;
    lte block.height r3.expiry_height into r6;
    assert.eq r6 true;
    branch.eq true true to end_otherwise_0_3;
    position end_then_0_2;
    position end_otherwise_0_3;

function pay_invoice:
    input r0 as credits.aleo/credits.record;
    input r1 as address.private;
    input r2 as address.public;
    input r3 as u64.private;
    input r4 as field.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.public;
    call credits.aleo/transfer_private r0 r1 r3 into r9 r10;
    cast r1 into r11 as field;
    cast r3 into r12 as field;
    hash.bhp256 r11 into r13 as field;
    hash.bhp256 r12 into r14 as field;
    hash.bhp256 r4 into r15 as field;
    add r13 r14 into r16;
    add r16 r15 into r17;
    hash.bhp256 r4 into r18 as scalar;
    commit.bhp256 r5 r18 into r19 as field;
    cast r2 r1 r19 r17 r3 0u8 r6 0u64 into r20 as PayerReceipt.record;
    cast r1 r19 r17 r3 0u8 r7 into r21 as MerchantReceipt.record;
    async pay_invoice r4 r17 into r22;
    output r9 as credits.aleo/credits.record;
    output r10 as credits.aleo/credits.record;
    output r20 as PayerReceipt.record;
    output r21 as MerchantReceipt.record;
    output r22 as zk_pay_proofs_privacy_v29.aleo/pay_invoice.future;

finalize pay_invoice:
    input r0 as field.public;
    input r1 as field.public;
    get salt_to_invoice[r0] into r2;
    assert.eq r1 r2;
    get invoices[r2] into r3;
    is.neq r3.token_type 3u8 into r4;
    branch.eq r4 false to end_then_0_4;
    assert.eq r3.token_type 0u8;
    branch.eq true true to end_otherwise_0_5;
    position end_then_0_4;
    position end_otherwise_0_5;
    is.neq r3.expiry_height 0u32 into r5;
    branch.eq r5 false to end_then_0_6;
    lte block.height r3.expiry_height into r6;
    assert.eq r6 true;
    branch.eq true true to end_otherwise_0_7;
    position end_then_0_6;
    position end_otherwise_0_7;
    assert.eq r3.status 0u8;
    is.eq r3.invoice_type 0u8 into r7;
    branch.eq r7 false to end_then_0_8;
    cast r3.expiry_height 1u8 r3.invoice_type r3.token_type r3.wallet_type into r8 as InvoiceData;
    set r8 into invoices[r2];
    branch.eq true true to end_otherwise_0_9;
    position end_then_0_8;
    position end_otherwise_0_9;

function pay_invoice_usdcx:
    input r0 as test_usdcx_stablecoin.aleo/Token.record;
    input r1 as address.private;
    input r2 as address.public;
    input r3 as u128.private;
    input r4 as field.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.public;
    input r9 as [test_usdcx_stablecoin.aleo/MerkleProof; 2u32].private;
    call test_usdcx_stablecoin.aleo/transfer_private r1 r3 r0 r9 into r10 r11 r12 r13;
    cast r1 into r14 as field;
    cast r3 into r15 as field;
    hash.bhp256 r14 into r16 as field;
    hash.bhp256 r15 into r17 as field;
    hash.bhp256 r4 into r18 as field;
    add r16 r17 into r19;
    add r19 r18 into r20;
    hash.bhp256 r4 into r21 as scalar;
    commit.bhp256 r5 r21 into r22 as field;
    cast r3 into r23 as u64;
    cast r2 r1 r22 r20 r23 1u8 r6 0u64 into r24 as PayerReceipt.record;
    cast r3 into r25 as u64;
    cast r1 r22 r20 r25 1u8 r7 into r26 as MerchantReceipt.record;
    async pay_invoice_usdcx r13 r4 r20 into r27;
    output r11 as test_usdcx_stablecoin.aleo/Token.record;
    output r12 as test_usdcx_stablecoin.aleo/Token.record;
    output r10 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r24 as PayerReceipt.record;
    output r26 as MerchantReceipt.record;
    output r27 as zk_pay_proofs_privacy_v29.aleo/pay_invoice_usdcx.future;

finalize pay_invoice_usdcx:
    input r0 as test_usdcx_stablecoin.aleo/transfer_private.future;
    input r1 as field.public;
    input r2 as field.public;
    await r0;
    get salt_to_invoice[r1] into r3;
    assert.eq r2 r3;
    get invoices[r3] into r4;
    is.neq r4.token_type 3u8 into r5;
    branch.eq r5 false to end_then_0_10;
    assert.eq r4.token_type 1u8;
    branch.eq true true to end_otherwise_0_11;
    position end_then_0_10;
    position end_otherwise_0_11;
    is.neq r4.expiry_height 0u32 into r6;
    branch.eq r6 false to end_then_0_12;
    lte block.height r4.expiry_height into r7;
    assert.eq r7 true;
    branch.eq true true to end_otherwise_0_13;
    position end_then_0_12;
    position end_otherwise_0_13;
    assert.eq r4.status 0u8;
    is.eq r4.invoice_type 0u8 into r8;
    branch.eq r8 false to end_then_0_14;
    cast r4.expiry_height 1u8 r4.invoice_type r4.token_type r4.wallet_type into r9 as InvoiceData;
    set r9 into invoices[r3];
    branch.eq true true to end_otherwise_0_15;
    position end_then_0_14;
    position end_otherwise_0_15;

function pay_invoice_usad:
    input r0 as test_usad_stablecoin.aleo/Token.record;
    input r1 as address.private;
    input r2 as address.public;
    input r3 as u128.private;
    input r4 as field.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.public;
    input r9 as [test_usad_stablecoin.aleo/MerkleProof; 2u32].private;
    call test_usad_stablecoin.aleo/transfer_private r1 r3 r0 r9 into r10 r11 r12 r13;
    cast r1 into r14 as field;
    cast r3 into r15 as field;
    hash.bhp256 r14 into r16 as field;
    hash.bhp256 r15 into r17 as field;
    hash.bhp256 r4 into r18 as field;
    add r16 r17 into r19;
    add r19 r18 into r20;
    hash.bhp256 r4 into r21 as scalar;
    commit.bhp256 r5 r21 into r22 as field;
    cast r3 into r23 as u64;
    cast r2 r1 r22 r20 r23 2u8 r6 0u64 into r24 as PayerReceipt.record;
    cast r3 into r25 as u64;
    cast r1 r22 r20 r25 2u8 r7 into r26 as MerchantReceipt.record;
    async pay_invoice_usad r13 r4 r20 into r27;
    output r11 as test_usad_stablecoin.aleo/Token.record;
    output r12 as test_usad_stablecoin.aleo/Token.record;
    output r10 as test_usad_stablecoin.aleo/ComplianceRecord.record;
    output r24 as PayerReceipt.record;
    output r26 as MerchantReceipt.record;
    output r27 as zk_pay_proofs_privacy_v29.aleo/pay_invoice_usad.future;

finalize pay_invoice_usad:
    input r0 as test_usad_stablecoin.aleo/transfer_private.future;
    input r1 as field.public;
    input r2 as field.public;
    await r0;
    get salt_to_invoice[r1] into r3;
    assert.eq r2 r3;
    get invoices[r3] into r4;
    is.neq r4.token_type 3u8 into r5;
    branch.eq r5 false to end_then_0_16;
    assert.eq r4.token_type 2u8;
    branch.eq true true to end_otherwise_0_17;
    position end_then_0_16;
    position end_otherwise_0_17;
    is.neq r4.expiry_height 0u32 into r6;
    branch.eq r6 false to end_then_0_18;
    lte block.height r4.expiry_height into r7;
    assert.eq r7 true;
    branch.eq true true to end_otherwise_0_19;
    position end_then_0_18;
    position end_otherwise_0_19;
    assert.eq r4.status 0u8;
    is.eq r4.invoice_type 0u8 into r8;
    branch.eq r8 false to end_then_0_20;
    cast r4.expiry_height 1u8 r4.invoice_type r4.token_type r4.wallet_type into r9 as InvoiceData;
    set r9 into invoices[r3];
    branch.eq true true to end_otherwise_0_21;
    position end_then_0_20;
    position end_otherwise_0_21;

function pay_donation_usdcx:
    input r0 as test_usdcx_stablecoin.aleo/Token.record;
    input r1 as address.private;
    input r2 as address.public;
    input r3 as u128.private;
    input r4 as field.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.public;
    input r9 as [test_usdcx_stablecoin.aleo/MerkleProof; 2u32].private;
    gt r3 0u128 into r10;
    assert.eq r10 true;
    call test_usdcx_stablecoin.aleo/transfer_private r1 r3 r0 r9 into r11 r12 r13 r14;
    cast r1 into r15 as field;
    hash.bhp256 r15 into r16 as field;
    hash.bhp256 0field into r17 as field;
    hash.bhp256 r4 into r18 as field;
    add r16 r17 into r19;
    add r19 r18 into r20;
    hash.bhp256 r4 into r21 as scalar;
    cast r3 into r22 as field;
    hash.bhp256 r22 into r23 as field;
    add r5 r23 into r24;
    add r24 3260460799406925384450789443848721250796883831019095717716089006895746294528field into r25;
    commit.bhp256 r25 r21 into r26 as field;
    cast r3 into r27 as u64;
    cast r2 r1 r26 r20 r27 1u8 r6 0u64 into r28 as PayerReceipt.record;
    cast r3 into r29 as u64;
    cast r1 r26 r20 r29 1u8 r7 into r30 as MerchantReceipt.record;
    async pay_donation_usdcx r14 r4 r20 into r31;
    output r12 as test_usdcx_stablecoin.aleo/Token.record;
    output r13 as test_usdcx_stablecoin.aleo/Token.record;
    output r11 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r28 as PayerReceipt.record;
    output r30 as MerchantReceipt.record;
    output r31 as zk_pay_proofs_privacy_v29.aleo/pay_donation_usdcx.future;

finalize pay_donation_usdcx:
    input r0 as test_usdcx_stablecoin.aleo/transfer_private.future;
    input r1 as field.public;
    input r2 as field.public;
    await r0;
    get salt_to_invoice[r1] into r3;
    assert.eq r2 r3;
    get invoices[r3] into r4;
    is.neq r4.token_type 3u8 into r5;
    branch.eq r5 false to end_then_0_22;
    assert.eq r4.token_type 1u8;
    branch.eq true true to end_otherwise_0_23;
    position end_then_0_22;
    position end_otherwise_0_23;
    assert.eq r4.invoice_type 2u8;
    assert.eq r4.status 0u8;
    is.neq r4.expiry_height 0u32 into r6;
    branch.eq r6 false to end_then_0_24;
    lte block.height r4.expiry_height into r7;
    assert.eq r7 true;
    branch.eq true true to end_otherwise_0_25;
    position end_then_0_24;
    position end_otherwise_0_25;

function pay_donation_usad:
    input r0 as test_usad_stablecoin.aleo/Token.record;
    input r1 as address.private;
    input r2 as address.public;
    input r3 as u128.private;
    input r4 as field.private;
    input r5 as field.private;
    input r6 as field.private;
    input r7 as field.private;
    input r8 as field.public;
    input r9 as [test_usad_stablecoin.aleo/MerkleProof; 2u32].private;
    gt r3 0u128 into r10;
    assert.eq r10 true;
    call test_usad_stablecoin.aleo/transfer_private r1 r3 r0 r9 into r11 r12 r13 r14;
    cast r1 into r15 as field;
    hash.bhp256 r15 into r16 as field;
    hash.bhp256 0field into r17 as field;
    hash.bhp256 r4 into r18 as field;
    add r16 r17 into r19;
    add r19 r18 into r20;
    hash.bhp256 r4 into r21 as scalar;
    cast r3 into r22 as field;
    hash.bhp256 r22 into r23 as field;
    add r5 r23 into r24;
    add r24 3736522601382494394255789052466017870786031735005680174691203879959757105441field into r25;
    commit.bhp256 r25 r21 into r26 as field;
    cast r3 into r27 as u64;
    cast r2 r1 r26 r20 r27 2u8 r6 0u64 into r28 as PayerReceipt.record;
    cast r3 into r29 as u64;
    cast r1 r26 r20 r29 2u8 r7 into r30 as MerchantReceipt.record;
    async pay_donation_usad r14 r4 r20 into r31;
    output r12 as test_usad_stablecoin.aleo/Token.record;
    output r13 as test_usad_stablecoin.aleo/Token.record;
    output r11 as test_usad_stablecoin.aleo/ComplianceRecord.record;
    output r28 as PayerReceipt.record;
    output r30 as MerchantReceipt.record;
    output r31 as zk_pay_proofs_privacy_v29.aleo/pay_donation_usad.future;

finalize pay_donation_usad:
    input r0 as test_usad_stablecoin.aleo/transfer_private.future;
    input r1 as field.public;
    input r2 as field.public;
    await r0;
    get salt_to_invoice[r1] into r3;
    assert.eq r2 r3;
    get invoices[r3] into r4;
    is.neq r4.token_type 3u8 into r5;
    branch.eq r5 false to end_then_0_26;
    assert.eq r4.token_type 2u8;
    branch.eq true true to end_otherwise_0_27;
    position end_then_0_26;
    position end_otherwise_0_27;
    assert.eq r4.invoice_type 2u8;
    assert.eq r4.status 0u8;
    is.neq r4.expiry_height 0u32 into r6;
    branch.eq r6 false to end_then_0_28;
    lte block.height r4.expiry_height into r7;
    assert.eq r7 true;
    branch.eq true true to end_otherwise_0_29;
    position end_then_0_28;
    position end_otherwise_0_29;

function settle_invoice:
    input r0 as field.public;
    input r1 as u64.private;
    cast self.caller into r2 as field;
    cast r1 into r3 as field;
    hash.bhp256 r2 into r4 as field;
    hash.bhp256 r3 into r5 as field;
    hash.bhp256 r0 into r6 as field;
    add r4 r5 into r7;
    add r7 r6 into r8;
    async settle_invoice r0 r8 into r9;
    output r9 as zk_pay_proofs_privacy_v29.aleo/settle_invoice.future;

finalize settle_invoice:
    input r0 as field.public;
    input r1 as field.public;
    get salt_to_invoice[r0] into r2;
    assert.eq r1 r2;
    get invoices[r2] into r3;
    cast r3.expiry_height 1u8 r3.invoice_type r3.token_type r3.wallet_type into r4 as InvoiceData;
    set r4 into invoices[r2];

function delete_invoice:
    input r0 as Invoice.record;
    assert.eq r0.owner self.caller;
    async delete_invoice r0.salt r0.invoice_hash into r1;
    output r1 as zk_pay_proofs_privacy_v29.aleo/delete_invoice.future;

finalize delete_invoice:
    input r0 as field.public;
    input r1 as field.public;
    get salt_to_invoice[r0] into r2;
    assert.eq r1 r2;
    get invoices[r2] into r3;
    assert.eq r3.status 0u8;
    remove invoices[r2];
    remove salt_to_invoice[r0];

function get_invoice_status:
    input r0 as field.public;
    async get_invoice_status r0 into r1;
    output r1 as zk_pay_proofs_privacy_v29.aleo/get_invoice_status.future;

finalize get_invoice_status:
    input r0 as field.public;
    get invoices[r0] into r1;

constructor:
    assert.eq program_owner aleo1yu926k0jqqzfv06js4jlsxnf2ejah47rfqsxmwfx6tvuxxgvrqpqdlq5y0;
