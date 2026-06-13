import merkle_tree.aleo;
import test_usdcx_multisig_core.aleo;
import test_usdcx_freezelist.aleo;
import test_usdcx_stablecoin.aleo;

program humanity_link_aid_v9d.aleo;

mapping admin_address:
    key as u8.public;
    value as address.public;

mapping flags:
    key as u8.public;
    value as boolean.public;

mapping authorized_issuers:
    key as address.public;
    value as boolean.public;

mapping whitelisted_merchants:
    key as address.public;
    value as boolean.public;

mapping bridge_address:
    key as u8.public;
    value as address.public;

mapping last_merch_offramp:
    key as address.public;
    value as u32.public;

mapping merchant_vault:
    key as address.public;
    value as u128.public;

mapping clocks:
    key as u8.public;
    value as u32.public;

mapping limits:
    key as u8.public;
    value as u64.public;

mapping total_issued:
    key as u8.public;
    value as u128.public;

mapping total_spent:
    key as u8.public;
    value as u128.public;

mapping total_ben_offramp:
    key as u8.public;
    value as u128.public;

mapping total_merch_offramp:
    key as u8.public;
    value as u128.public;

function transfer_admin:
    input r0 as address.private;
    async transfer_admin self.caller r0 into r1;
    output r1 as humanity_link_aid_v9d.aleo/transfer_admin.future;

finalize transfer_admin:
    input r0 as address.public;
    input r1 as address.public;
    get admin_address[0u8] into r2;
    assert.eq r0 r2;
    set r1 into admin_address[0u8];

function authorize_issuer:
    input r0 as address.private;
    async authorize_issuer self.caller r0 into r1;
    output r1 as humanity_link_aid_v9d.aleo/authorize_issuer.future;

finalize authorize_issuer:
    input r0 as address.public;
    input r1 as address.public;
    get admin_address[0u8] into r2;
    assert.eq r0 r2;
    set true into authorized_issuers[r1];

function revoke_issuer:
    input r0 as address.private;
    async revoke_issuer self.caller r0 into r1;
    output r1 as humanity_link_aid_v9d.aleo/revoke_issuer.future;

finalize revoke_issuer:
    input r0 as address.public;
    input r1 as address.public;
    get admin_address[0u8] into r2;
    assert.eq r0 r2;
    set false into authorized_issuers[r1];

function whitelist_merchant:
    input r0 as address.private;
    async whitelist_merchant self.caller r0 into r1;
    output r1 as humanity_link_aid_v9d.aleo/whitelist_merchant.future;

finalize whitelist_merchant:
    input r0 as address.public;
    input r1 as address.public;
    get admin_address[0u8] into r2;
    assert.eq r0 r2;
    set true into whitelisted_merchants[r1];

function revoke_merchant:
    input r0 as address.private;
    async revoke_merchant self.caller r0 into r1;
    output r1 as humanity_link_aid_v9d.aleo/revoke_merchant.future;

finalize revoke_merchant:
    input r0 as address.public;
    input r1 as address.public;
    get admin_address[0u8] into r2;
    assert.eq r0 r2;
    set false into whitelisted_merchants[r1];

function set_bridge_address:
    input r0 as address.private;
    async set_bridge_address self.caller r0 into r1;
    output r1 as humanity_link_aid_v9d.aleo/set_bridge_address.future;

finalize set_bridge_address:
    input r0 as address.public;
    input r1 as address.public;
    get admin_address[0u8] into r2;
    assert.eq r0 r2;
    set r1 into bridge_address[0u8];

function set_merch_offramp_period:
    input r0 as u32.private;
    gt r0 0u32 into r1;
    assert.eq r1 true;
    async set_merch_offramp_period self.caller r0 into r2;
    output r2 as humanity_link_aid_v9d.aleo/set_merch_offramp_period.future;

finalize set_merch_offramp_period:
    input r0 as address.public;
    input r1 as u32.public;
    get admin_address[0u8] into r2;
    assert.eq r0 r2;
    set r1 into clocks[0u8];

function set_min_merch_offramp:
    input r0 as u64.private;
    gt r0 0u64 into r1;
    assert.eq r1 true;
    async set_min_merch_offramp self.caller r0 into r2;
    output r2 as humanity_link_aid_v9d.aleo/set_min_merch_offramp.future;

finalize set_min_merch_offramp:
    input r0 as address.public;
    input r1 as u64.public;
    get admin_address[0u8] into r2;
    assert.eq r0 r2;
    set r1 into limits[0u8];

function pause:
    async pause self.caller into r0;
    output r0 as humanity_link_aid_v9d.aleo/pause.future;

finalize pause:
    input r0 as address.public;
    get admin_address[0u8] into r1;
    assert.eq r0 r1;
    set true into flags[0u8];

function unpause:
    async unpause self.caller into r0;
    output r0 as humanity_link_aid_v9d.aleo/unpause.future;

finalize unpause:
    input r0 as address.public;
    get admin_address[0u8] into r1;
    assert.eq r0 r1;
    set false into flags[0u8];

function sweep_vault:
    input r0 as u64.private;
    input r1 as address.private;
    gt r0 0u64 into r2;
    assert.eq r2 true;
    cast r0 into r3 as u128;
    call test_usdcx_stablecoin.aleo/transfer_public r1 r3 into r4;
    async sweep_vault r4 self.caller into r5;
    output r5 as humanity_link_aid_v9d.aleo/sweep_vault.future;

finalize sweep_vault:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public.future;
    input r1 as address.public;
    await r0;
    get admin_address[0u8] into r2;
    assert.eq r1 r2;
    get.or_use flags[0u8] false into r3;
    not r3 into r4;
    assert.eq r4 true;

function settle_merchant:
    input r0 as address.private;
    input r1 as u64.private;
    gt r1 0u64 into r2;
    assert.eq r2 true;
    cast r1 into r3 as u128;
    async settle_merchant self.caller r0 r3 into r4;
    output r4 as humanity_link_aid_v9d.aleo/settle_merchant.future;

finalize settle_merchant:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u128.public;
    get admin_address[0u8] into r3;
    assert.eq r0 r3;
    get.or_use merchant_vault[r1] 0u128 into r4;
    gte r4 r2 into r5;
    assert.eq r5 true;
    sub r4 r2 into r6;
    set r6 into merchant_vault[r1];

function issue_aid:
    input r0 as address.private;
    input r1 as u64.private;
    gt r1 0u64 into r2;
    assert.eq r2 true;
    cast r1 into r3 as u128;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private r0 r3 into r4 r5 r6;
    cast r1 into r7 as u128;
    async issue_aid r6 self.caller r7 into r8;
    output r4 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r5 as test_usdcx_stablecoin.aleo/Token.record;
    output r8 as humanity_link_aid_v9d.aleo/issue_aid.future;

finalize issue_aid:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as address.public;
    input r2 as u128.public;
    await r0;
    get.or_use flags[0u8] false into r3;
    not r3 into r4;
    assert.eq r4 true;
    get.or_use authorized_issuers[r1] false into r5;
    assert.eq r5 true;
    get.or_use total_issued[0u8] 0u128 into r6;
    add r6 r2 into r7;
    set r7 into total_issued[0u8];

function bulk_issue_2:
    input r0 as address.private;
    input r1 as u64.private;
    input r2 as address.private;
    input r3 as u64.private;
    gt r1 0u64 into r4;
    assert.eq r4 true;
    gt r3 0u64 into r5;
    assert.eq r5 true;
    cast r1 into r6 as u128;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private r0 r6 into r7 r8 r9;
    cast r3 into r10 as u128;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private r2 r10 into r11 r12 r13;
    cast r1 into r14 as u128;
    cast r3 into r15 as u128;
    add r14 r15 into r16;
    async bulk_issue_2 r9 r13 self.caller r16 into r17;
    output r7 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r8 as test_usdcx_stablecoin.aleo/Token.record;
    output r11 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r12 as test_usdcx_stablecoin.aleo/Token.record;
    output r17 as humanity_link_aid_v9d.aleo/bulk_issue_2.future;

finalize bulk_issue_2:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r2 as address.public;
    input r3 as u128.public;
    await r0;
    await r1;
    get.or_use flags[0u8] false into r4;
    not r4 into r5;
    assert.eq r5 true;
    get.or_use authorized_issuers[r2] false into r6;
    assert.eq r6 true;
    get.or_use total_issued[0u8] 0u128 into r7;
    add r7 r3 into r8;
    set r8 into total_issued[0u8];

function bulk_issue_4:
    input r0 as address.private;
    input r1 as u64.private;
    input r2 as address.private;
    input r3 as u64.private;
    input r4 as address.private;
    input r5 as u64.private;
    input r6 as address.private;
    input r7 as u64.private;
    gt r1 0u64 into r8;
    assert.eq r8 true;
    gt r3 0u64 into r9;
    assert.eq r9 true;
    gt r5 0u64 into r10;
    assert.eq r10 true;
    gt r7 0u64 into r11;
    assert.eq r11 true;
    cast r1 into r12 as u128;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private r0 r12 into r13 r14 r15;
    cast r3 into r16 as u128;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private r2 r16 into r17 r18 r19;
    cast r5 into r20 as u128;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private r4 r20 into r21 r22 r23;
    cast r7 into r24 as u128;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private r6 r24 into r25 r26 r27;
    cast r1 into r28 as u128;
    cast r3 into r29 as u128;
    add r28 r29 into r30;
    cast r5 into r31 as u128;
    add r30 r31 into r32;
    cast r7 into r33 as u128;
    add r32 r33 into r34;
    async bulk_issue_4 r15 r19 r23 r27 self.caller r34 into r35;
    output r13 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r14 as test_usdcx_stablecoin.aleo/Token.record;
    output r17 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r18 as test_usdcx_stablecoin.aleo/Token.record;
    output r21 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r22 as test_usdcx_stablecoin.aleo/Token.record;
    output r25 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r26 as test_usdcx_stablecoin.aleo/Token.record;
    output r35 as humanity_link_aid_v9d.aleo/bulk_issue_4.future;

finalize bulk_issue_4:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r2 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r3 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r4 as address.public;
    input r5 as u128.public;
    await r0;
    await r1;
    await r2;
    await r3;
    get.or_use flags[0u8] false into r6;
    not r6 into r7;
    assert.eq r7 true;
    get.or_use authorized_issuers[r4] false into r8;
    assert.eq r8 true;
    get.or_use total_issued[0u8] 0u128 into r9;
    add r9 r5 into r10;
    set r10 into total_issued[0u8];

function spend:
    input r0 as test_usdcx_stablecoin.aleo/Token.record;
    input r1 as [test_usdcx_stablecoin.aleo/MerkleProof; 2u32].private;
    input r2 as address.private;
    input r3 as u64.private;
    gt r3 0u64 into r4;
    assert.eq r4 true;
    cast r3 into r5 as u128;
    gte r0.amount r5 into r6;
    assert.eq r6 true;
    cast r3 into r7 as u128;
    call test_usdcx_stablecoin.aleo/transfer_private r2 r7 r0 r1 into r8 r9 r10 r11;
    cast r3 into r12 as u128;
    async spend r11 r2 r12 into r13;
    output r8 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r9 as test_usdcx_stablecoin.aleo/Token.record;
    output r10 as test_usdcx_stablecoin.aleo/Token.record;
    output r13 as humanity_link_aid_v9d.aleo/spend.future;

finalize spend:
    input r0 as test_usdcx_stablecoin.aleo/transfer_private.future;
    input r1 as address.public;
    input r2 as u128.public;
    await r0;
    get.or_use flags[0u8] false into r3;
    not r3 into r4;
    assert.eq r4 true;
    get.or_use whitelisted_merchants[r1] false into r5;
    assert.eq r5 true;
    get.or_use total_spent[0u8] 0u128 into r6;
    add r6 r2 into r7;
    set r7 into total_spent[0u8];

function offramp_beneficiary:
    input r0 as test_usdcx_stablecoin.aleo/Token.record;
    input r1 as [test_usdcx_stablecoin.aleo/MerkleProof; 2u32].private;
    input r2 as address.private;
    input r3 as u64.private;
    gt r3 0u64 into r4;
    assert.eq r4 true;
    cast r3 into r5 as u128;
    gte r0.amount r5 into r6;
    assert.eq r6 true;
    cast r3 into r7 as u128;
    call test_usdcx_stablecoin.aleo/transfer_private r2 r7 r0 r1 into r8 r9 r10 r11;
    cast r3 into r12 as u128;
    async offramp_beneficiary r11 r2 r12 into r13;
    output r8 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r9 as test_usdcx_stablecoin.aleo/Token.record;
    output r10 as test_usdcx_stablecoin.aleo/Token.record;
    output r13 as humanity_link_aid_v9d.aleo/offramp_beneficiary.future;

finalize offramp_beneficiary:
    input r0 as test_usdcx_stablecoin.aleo/transfer_private.future;
    input r1 as address.public;
    input r2 as u128.public;
    await r0;
    get.or_use flags[0u8] false into r3;
    not r3 into r4;
    assert.eq r4 true;
    get.or_use whitelisted_merchants[r1] false into r5;
    assert.eq r5 true;
    get.or_use total_ben_offramp[0u8] 0u128 into r6;
    add r6 r2 into r7;
    set r7 into total_ben_offramp[0u8];

function offramp_merchant:
    input r0 as test_usdcx_stablecoin.aleo/Token.record;
    input r1 as [test_usdcx_stablecoin.aleo/MerkleProof; 2u32].private;
    input r2 as u64.private;
    input r3 as address.private;
    gt r2 0u64 into r4;
    assert.eq r4 true;
    cast r2 into r5 as u128;
    gte r0.amount r5 into r6;
    assert.eq r6 true;
    cast r2 into r7 as u128;
    call test_usdcx_stablecoin.aleo/transfer_private_to_public r3 r7 r0 r1 into r8 r9 r10;
    cast r2 into r11 as u128;
    async offramp_merchant r10 self.signer r2 r3 r11 into r12;
    output r8 as test_usdcx_stablecoin.aleo/ComplianceRecord.record;
    output r9 as test_usdcx_stablecoin.aleo/Token.record;
    output r12 as humanity_link_aid_v9d.aleo/offramp_merchant.future;

finalize offramp_merchant:
    input r0 as test_usdcx_stablecoin.aleo/transfer_private_to_public.future;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as address.public;
    input r4 as u128.public;
    await r0;
    get.or_use flags[0u8] false into r5;
    not r5 into r6;
    assert.eq r6 true;
    get.or_use whitelisted_merchants[r1] false into r7;
    assert.eq r7 true;
    get.or_use limits[0u8] 6000000u64 into r8;
    gte r2 r8 into r9;
    assert.eq r9 true;
    get bridge_address[0u8] into r10;
    assert.eq r3 r10;
    get.or_use last_merch_offramp[r1] 0u32 into r11;
    get.or_use clocks[0u8] 17280u32 into r12;
    add r11 r12 into r13;
    gte block.height r13 into r14;
    assert.eq r14 true;
    set block.height into last_merch_offramp[r1];
    get.or_use total_merch_offramp[0u8] 0u128 into r15;
    add r15 r4 into r16;
    set r16 into total_merch_offramp[0u8];
    get.or_use merchant_vault[r1] 0u128 into r17;
    add r17 r4 into r18;
    set r18 into merchant_vault[r1];

constructor:
    set program_owner into admin_address[0u8];
    set false into flags[0u8];
    set 17280u32 into clocks[0u8];
    set 6000000u64 into limits[0u8];
