import merkle_tree.aleo;
import test_usdcx_multisig_core.aleo;
import test_usdcx_freezelist.aleo;
import test_usdcx_stablecoin.aleo;
import test_btc_v1.aleo;

program dara_dp_btc_v5.aleo;

record OrderCommitment:
    owner as address.private;
    order_id as field.private;
    direction as u8.private;
    size as u128.private;
    limit_price as u64.private;
    expiry_block as u32.private;
    batch_id as u64.private;

record OrderAuth:
    owner as address.private;
    trader as address.private;
    order_id as field.private;
    direction as u8.private;
    size as u128.private;
    limit_price as u64.private;
    expiry_block as u32.private;

record FillReceipt:
    owner as address.private;
    order_id as field.private;
    direction as u8.private;
    filled_size as u128.private;
    clearing_price as u64.private;
    fee_paid as u128.private;
    batch_id as u64.private;

record ResidualOrder:
    owner as address.private;
    order_id as field.private;
    parent_order_id as field.private;
    direction as u8.private;
    remaining_size as u128.private;
    limit_price as u64.private;
    expiry_block as u32.private;

record ResidualAuth:
    owner as address.private;
    trader as address.private;
    order_id as field.private;
    direction as u8.private;
    remaining_size as u128.private;
    limit_price as u64.private;
    expiry_block as u32.private;

mapping initialized:
    key as u8.public;
    value as boolean.public;

mapping operators:
    key as u8.public;
    value as address.public;

mapping pool_paused:
    key as u8.public;
    value as boolean.public;

mapping order_consumed:
    key as field.public;
    value as boolean.public;

mapping fee_vault:
    key as u8.public;
    value as u128.public;

mapping fee_bps:
    key as u8.public;
    value as u64.public;

mapping total_trades:
    key as u8.public;
    value as u64.public;

mapping total_volume:
    key as u8.public;
    value as u128.public;

mapping oracle_price:
    key as u8.public;
    value as u64.public;

mapping oracle_round:
    key as u8.public;
    value as u64.public;

mapping twap_cum_price:
    key as u8.public;
    value as u128.public;

mapping twap_cum_count:
    key as u8.public;
    value as u64.public;

mapping twap_last_reset:
    key as u8.public;
    value as u32.public;

mapping twap_window_blocks:
    key as u8.public;
    value as u32.public;

mapping twap_max_deviation_bps:
    key as u8.public;
    value as u64.public;

mapping current_batch:
    key as u8.public;
    value as u64.public;

mapping batch_approved:
    key as u64.public;
    value as boolean.public;

mapping batch_proposed_price:
    key as u64.public;
    value as u64.public;

mapping batch_proposer:
    key as u64.public;
    value as address.public;

mapping batch_approval_count:
    key as u64.public;
    value as u8.public;

mapping operator_approved_batch:
    key as field.public;
    value as boolean.public;

mapping batch_start_block:
    key as u64.public;
    value as u32.public;

mapping min_batch_blocks:
    key as u8.public;
    value as u32.public;

function initialize:
    input r0 as address.private;
    async initialize self.caller r0 into r1;
    output r1 as dara_dp_btc_v5.aleo/initialize.future;

finalize initialize:
    input r0 as address.public;
    input r1 as address.public;
    get.or_use initialized[0u8] false into r2;
    not r2 into r3;
    assert.eq r3 true;
    is.eq r0 r1 into r4;
    assert.eq r4 true;
    set true into initialized[0u8];
    set r1 into operators[0u8];

function set_operators:
    input r0 as address.private;
    input r1 as address.private;
    input r2 as address.private;
    async set_operators self.caller r0 r1 r2 into r3;
    output r3 as dara_dp_btc_v5.aleo/set_operators.future;

finalize set_operators:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as address.public;
    input r3 as address.public;
    get operators[0u8] into r4;
    assert.eq r0 r4;
    set r1 into operators[1u8];
    set r2 into operators[2u8];
    set r3 into operators[3u8];

function update_oracle_price:
    input r0 as u64.private;
    input r1 as u64.private;
    gt r0 0u64 into r2;
    assert.eq r2 true;
    lte r0 100000000u64 into r3;
    assert.eq r3 true;
    async update_oracle_price self.caller r1 r0 into r4;
    output r4 as dara_dp_btc_v5.aleo/update_oracle_price.future;

finalize update_oracle_price:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as u64.public;
    get operators[1u8] into r3;
    get operators[2u8] into r4;
    get operators[3u8] into r5;
    is.eq r0 r3 into r6;
    is.eq r0 r4 into r7;
    or r6 r7 into r8;
    is.eq r0 r5 into r9;
    or r8 r9 into r10;
    assert.eq r10 true;
    get.or_use pool_paused[0u8] false into r11;
    not r11 into r12;
    assert.eq r12 true;
    get.or_use oracle_round[0u8] 0u64 into r13;
    gt r1 r13 into r14;
    assert.eq r14 true;
    set r1 into oracle_round[0u8];
    get.or_use oracle_price[0u8] 0u64 into r15;
    gt r15 0u64 into r16;
    branch.eq r16 false to end_then_0_0;
    gte r2 r15 into r17;
    ternary r17 r2 r15 into r18;
    lt r2 r15 into r19;
    ternary r19 r2 r15 into r20;
    sub r18 r20 into r21;
    mul r15 1500u64 into r22;
    div r22 10000u64 into r23;
    lte r21 r23 into r24;
    assert.eq r24 true;
    branch.eq true true to end_otherwise_0_1;
    position end_then_0_0;
    position end_otherwise_0_1;
    set r2 into oracle_price[0u8];
    get.or_use twap_window_blocks[0u8] 3600u32 into r25;
    get.or_use twap_last_reset[0u8] 0u32 into r26;
    sub block.height r26 into r27;
    gte r27 r25 into r28;
    branch.eq r28 false to end_then_0_2;
    cast r2 into r29 as u128;
    set r29 into twap_cum_price[0u8];
    set 1u64 into twap_cum_count[0u8];
    set block.height into twap_last_reset[0u8];
    branch.eq true true to end_otherwise_0_3;
    position end_then_0_2;
    get.or_use twap_cum_price[0u8] 0u128 into r30;
    cast r2 into r31 as u128;
    add r30 r31 into r32;
    set r32 into twap_cum_price[0u8];
    get.or_use twap_cum_count[0u8] 0u64 into r33;
    add r33 1u64 into r34;
    set r34 into twap_cum_count[0u8];
    position end_otherwise_0_3;

function submit_buy_order:
    input r0 as test_usdcx_stablecoin.aleo/Token.record;
    input r1 as [test_usdcx_stablecoin.aleo/MerkleProof; 2u32].private;
    input r2 as u128.private;
    input r3 as u64.private;
    input r4 as u32.private;
    input r5 as address.private;
    input r6 as field.private;
    gte r2 100000u128 into r7;
    assert.eq r7 true;
    gt r3 0u64 into r8;
    assert.eq r8 true;
    lte r3 100000000u64 into r9;
    assert.eq r9 true;
    cast r3 into r10 as u128;
    mul r2 r10 into r11;
    div r11 1000000u128 into r12;
    gt r12 0u128 into r13;
    assert.eq r13 true;
    hash.bhp256 self.signer into r14 as field;
    add r6 r14 into r15;
    hash.bhp256 r15 into r16 as field;
    cast self.signer r16 0u8 r2 r3 r4 0u64 into r17 as OrderCommitment.record;
    cast r5 self.signer r16 0u8 r2 r3 r4 into r18 as OrderAuth.record;
    call test_usdcx_stablecoin.aleo/transfer_private_to_public dara_dp_btc_v5.aleo r12 r0 r1 into r19 r20 r21;
    async submit_buy_order r21 r16 r4 r2 into r22;
    output r17 as OrderCommitment.record;
    output r18 as OrderAuth.record;
    output r22 as dara_dp_btc_v5.aleo/submit_buy_order.future;

finalize submit_buy_order:
    input r0 as test_usdcx_stablecoin.aleo/transfer_private_to_public.future;
    input r1 as field.public;
    input r2 as u32.public;
    input r3 as u128.public;
    await r0;
    get.or_use pool_paused[0u8] false into r4;
    not r4 into r5;
    assert.eq r5 true;
    get.or_use order_consumed[r1] false into r6;
    not r6 into r7;
    assert.eq r7 true;
    gt r2 block.height into r8;
    assert.eq r8 true;
    get.or_use total_trades[0u8] 0u64 into r9;
    add r9 1u64 into r10;
    set r10 into total_trades[0u8];
    get.or_use total_volume[0u8] 0u128 into r11;
    add r11 r3 into r12;
    set r12 into total_volume[0u8];

function submit_sell_order:
    input r0 as test_btc_v1.aleo/Token.record;
    input r1 as u64.private;
    input r2 as u64.private;
    input r3 as u32.private;
    input r4 as address.private;
    input r5 as field.private;
    gte r1 100000u64 into r6;
    assert.eq r6 true;
    gt r2 0u64 into r7;
    assert.eq r7 true;
    lte r2 100000000u64 into r8;
    assert.eq r8 true;
    cast r1 into r9 as u128;
    hash.bhp256 self.signer into r10 as field;
    add r5 r10 into r11;
    hash.bhp256 r11 into r12 as field;
    cast self.signer r12 1u8 r9 r2 r3 0u64 into r13 as OrderCommitment.record;
    cast r4 self.signer r12 1u8 r9 r2 r3 into r14 as OrderAuth.record;
    call test_btc_v1.aleo/transfer_private_to_public r0 dara_dp_btc_v5.aleo r1 into r15 r16;
    async submit_sell_order r16 r12 r3 r9 into r17;
    output r13 as OrderCommitment.record;
    output r14 as OrderAuth.record;
    output r17 as dara_dp_btc_v5.aleo/submit_sell_order.future;

finalize submit_sell_order:
    input r0 as test_btc_v1.aleo/transfer_private_to_public.future;
    input r1 as field.public;
    input r2 as u32.public;
    input r3 as u128.public;
    await r0;
    get.or_use pool_paused[0u8] false into r4;
    not r4 into r5;
    assert.eq r5 true;
    get.or_use order_consumed[r1] false into r6;
    not r6 into r7;
    assert.eq r7 true;
    gt r2 block.height into r8;
    assert.eq r8 true;
    get.or_use total_trades[0u8] 0u64 into r9;
    add r9 1u64 into r10;
    set r10 into total_trades[0u8];
    get.or_use total_volume[0u8] 0u128 into r11;
    add r11 r3 into r12;
    set r12 into total_volume[0u8];

function propose_settlement:
    input r0 as u64.private;
    input r1 as u64.private;
    gt r1 0u64 into r2;
    assert.eq r2 true;
    lte r1 100000000u64 into r3;
    assert.eq r3 true;
    async propose_settlement self.caller r0 r1 into r4;
    output r4 as dara_dp_btc_v5.aleo/propose_settlement.future;

finalize propose_settlement:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as u64.public;
    get.or_use pool_paused[0u8] false into r3;
    not r3 into r4;
    assert.eq r4 true;
    get operators[1u8] into r5;
    get operators[2u8] into r6;
    get operators[3u8] into r7;
    is.eq r0 r5 into r8;
    is.eq r0 r6 into r9;
    or r8 r9 into r10;
    is.eq r0 r7 into r11;
    or r10 r11 into r12;
    assert.eq r12 true;
    get.or_use current_batch[0u8] 1u64 into r13;
    assert.eq r1 r13;
    get.or_use batch_approved[r1] false into r14;
    not r14 into r15;
    assert.eq r15 true;
    get.or_use batch_start_block[r1] 0u32 into r16;
    get.or_use min_batch_blocks[0u8] 100u32 into r17;
    add r16 r17 into r18;
    gte block.height r18 into r19;
    assert.eq r19 true;
    get.or_use twap_cum_price[0u8] 0u128 into r20;
    get.or_use twap_cum_count[0u8] 0u64 into r21;
    gt r21 0u64 into r22;
    branch.eq r22 false to end_then_0_4;
    cast r21 into r23 as u128;
    div r20 r23 into r24;
    get.or_use twap_max_deviation_bps[0u8] 500u64 into r25;
    cast r2 into r26 as u128;
    gte r26 r24 into r27;
    ternary r27 r26 r24 into r28;
    lt r26 r24 into r29;
    ternary r29 r26 r24 into r30;
    sub r28 r30 into r31;
    cast r25 into r32 as u128;
    mul r24 r32 into r33;
    div r33 10000u128 into r34;
    lte r31 r34 into r35;
    assert.eq r35 true;
    branch.eq true true to end_otherwise_0_5;
    position end_then_0_4;
    position end_otherwise_0_5;
    set r2 into batch_proposed_price[r1];
    set r0 into batch_proposer[r1];
    set 1u8 into batch_approval_count[r1];
    hash.bhp256 r1 into r36 as field;
    hash.bhp256 r0 into r37 as field;
    add r36 r37 into r38;
    hash.bhp256 r38 into r39 as field;
    set true into operator_approved_batch[r39];

function approve_settlement:
    input r0 as u64.private;
    input r1 as u64.private;
    async approve_settlement self.caller r0 r1 into r2;
    output r2 as dara_dp_btc_v5.aleo/approve_settlement.future;

finalize approve_settlement:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as u64.public;
    get.or_use pool_paused[0u8] false into r3;
    not r3 into r4;
    assert.eq r4 true;
    get operators[1u8] into r5;
    get operators[2u8] into r6;
    get operators[3u8] into r7;
    is.eq r0 r5 into r8;
    is.eq r0 r6 into r9;
    or r8 r9 into r10;
    is.eq r0 r7 into r11;
    or r10 r11 into r12;
    assert.eq r12 true;
    get.or_use current_batch[0u8] 1u64 into r13;
    assert.eq r1 r13;
    get.or_use batch_approved[r1] false into r14;
    not r14 into r15;
    assert.eq r15 true;
    get batch_proposed_price[r1] into r16;
    assert.eq r2 r16;
    hash.bhp256 r1 into r17 as field;
    hash.bhp256 r0 into r18 as field;
    add r17 r18 into r19;
    hash.bhp256 r19 into r20 as field;
    get.or_use operator_approved_batch[r20] false into r21;
    not r21 into r22;
    assert.eq r22 true;
    set true into operator_approved_batch[r20];
    get.or_use batch_approval_count[r1] 0u8 into r23;
    add r23 1u8 into r24;
    set r24 into batch_approval_count[r1];
    gte r24 2u8 into r25;
    branch.eq r25 false to end_then_0_6;
    set true into batch_approved[r1];
    branch.eq true true to end_otherwise_0_7;
    position end_then_0_6;
    position end_otherwise_0_7;

function execute_match:
    input r0 as OrderAuth.record;
    input r1 as OrderAuth.record;
    input r2 as u64.private;
    input r3 as u64.private;
    input r4 as address.private;
    input r5 as address.private;
    is.eq r0.direction 0u8 into r6;
    assert.eq r6 true;
    is.eq r1.direction 1u8 into r7;
    assert.eq r7 true;
    gt r2 0u64 into r8;
    assert.eq r8 true;
    lte r2 100000000u64 into r9;
    assert.eq r9 true;
    lte r2 r0.limit_price into r10;
    assert.eq r10 true;
    gte r2 r1.limit_price into r11;
    assert.eq r11 true;
    lte r0.size r1.size into r12;
    ternary r12 r0.size r1.size into r13;
    gt r13 0u128 into r14;
    assert.eq r14 true;
    cast r2 into r15 as u128;
    mul r13 r15 into r16;
    div r16 1000000u128 into r17;
    gt r17 0u128 into r18;
    assert.eq r18 true;
    mul r17 5u128 into r19;
    div r19 10000u128 into r20;
    sub r17 r20 into r21;
    cast r13 into r22 as u64;
    cast r4 r0.order_id 0u8 r13 r2 r20 r3 into r23 as FillReceipt.record;
    cast r5 r1.order_id 1u8 r13 r2 0u128 r3 into r24 as FillReceipt.record;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private r5 r21 into r25 r26 r27;
    call test_btc_v1.aleo/transfer_public_to_private r4 r22 into r28 r29;
    async execute_match r27 r29 r3 r0.order_id r1.order_id r17 into r30;
    output r23 as FillReceipt.record;
    output r24 as FillReceipt.record;
    output r30 as dara_dp_btc_v5.aleo/execute_match.future;

finalize execute_match:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as test_btc_v1.aleo/transfer_public_to_private.future;
    input r2 as u64.public;
    input r3 as field.public;
    input r4 as field.public;
    input r5 as u128.public;
    await r0;
    await r1;
    get.or_use pool_paused[0u8] false into r6;
    not r6 into r7;
    assert.eq r7 true;
    get.or_use batch_approved[r2] false into r8;
    assert.eq r8 true;
    get.or_use order_consumed[r3] false into r9;
    not r9 into r10;
    assert.eq r10 true;
    get.or_use order_consumed[r4] false into r11;
    not r11 into r12;
    assert.eq r12 true;
    set true into order_consumed[r3];
    set true into order_consumed[r4];
    get.or_use fee_vault[0u8] 0u128 into r13;
    get.or_use fee_bps[0u8] 5u64 into r14;
    cast r14 into r15 as u128;
    mul r5 r15 into r16;
    div r16 10000u128 into r17;
    add r13 r17 into r18;
    set r18 into fee_vault[0u8];

function execute_partial_fill:
    input r0 as OrderAuth.record;
    input r1 as OrderAuth.record;
    input r2 as u64.private;
    input r3 as u128.private;
    input r4 as u64.private;
    input r5 as address.private;
    input r6 as address.private;
    input r7 as field.private;
    is.eq r0.direction 0u8 into r8;
    assert.eq r8 true;
    is.eq r1.direction 1u8 into r9;
    assert.eq r9 true;
    gt r2 0u64 into r10;
    assert.eq r10 true;
    lte r2 100000000u64 into r11;
    assert.eq r11 true;
    lte r2 r0.limit_price into r12;
    assert.eq r12 true;
    gte r2 r1.limit_price into r13;
    assert.eq r13 true;
    gt r3 0u128 into r14;
    assert.eq r14 true;
    lt r3 r0.size into r15;
    lt r3 r1.size into r16;
    or r15 r16 into r17;
    assert.eq r17 true;
    sub r0.size r3 into r18;
    sub r1.size r3 into r19;
    is.eq r18 0u128 into r20;
    is.eq r19 0u128 into r21;
    or r20 r21 into r22;
    assert.eq r22 true;
    cast r2 into r23 as u128;
    mul r3 r23 into r24;
    div r24 1000000u128 into r25;
    mul r25 5u128 into r26;
    div r26 10000u128 into r27;
    sub r25 r27 into r28;
    cast r3 into r29 as u64;
    cast r2 into r30 as field;
    hash.bhp256 r30 into r31 as field;
    add r7 r31 into r32;
    hash.bhp256 r32 into r33 as field;
    gt r18 0u128 into r34;
    ternary r34 r5 r6 into r35;
    ternary r34 0u8 1u8 into r36;
    ternary r34 r18 r19 into r37;
    ternary r34 r0.limit_price r1.limit_price into r38;
    ternary r34 r0.expiry_block r1.expiry_block into r39;
    ternary r34 r0.order_id r1.order_id into r40;
    cast r5 r0.order_id 0u8 r3 r2 r27 r4 into r41 as FillReceipt.record;
    cast r6 r1.order_id 1u8 r3 r2 0u128 r4 into r42 as FillReceipt.record;
    cast r35 r33 r40 r36 r37 r38 r39 into r43 as ResidualOrder.record;
    cast r0.owner r35 r33 r36 r37 r38 r39 into r44 as ResidualAuth.record;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private r6 r28 into r45 r46 r47;
    call test_btc_v1.aleo/transfer_public_to_private r5 r29 into r48 r49;
    async execute_partial_fill r47 r49 r4 r0.order_id r1.order_id r25 into r50;
    output r41 as FillReceipt.record;
    output r42 as FillReceipt.record;
    output r43 as ResidualOrder.record;
    output r44 as ResidualAuth.record;
    output r50 as dara_dp_btc_v5.aleo/execute_partial_fill.future;

finalize execute_partial_fill:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as test_btc_v1.aleo/transfer_public_to_private.future;
    input r2 as u64.public;
    input r3 as field.public;
    input r4 as field.public;
    input r5 as u128.public;
    await r0;
    await r1;
    get.or_use pool_paused[0u8] false into r6;
    not r6 into r7;
    assert.eq r7 true;
    get.or_use batch_approved[r2] false into r8;
    assert.eq r8 true;
    get.or_use order_consumed[r3] false into r9;
    not r9 into r10;
    assert.eq r10 true;
    get.or_use order_consumed[r4] false into r11;
    not r11 into r12;
    assert.eq r12 true;
    set true into order_consumed[r3];
    set true into order_consumed[r4];
    get.or_use fee_vault[0u8] 0u128 into r13;
    get.or_use fee_bps[0u8] 5u64 into r14;
    cast r14 into r15 as u128;
    mul r5 r15 into r16;
    div r16 10000u128 into r17;
    add r13 r17 into r18;
    set r18 into fee_vault[0u8];

function resubmit_residual:
    input r0 as ResidualOrder.record;
    input r1 as ResidualAuth.record;
    input r2 as address.private;
    cast self.signer r0.order_id r0.direction r0.remaining_size r0.limit_price r0.expiry_block 0u64 into r3 as OrderCommitment.record;
    cast r2 self.signer r0.order_id r0.direction r0.remaining_size r0.limit_price r0.expiry_block into r4 as OrderAuth.record;
    output r3 as OrderCommitment.record;
    output r4 as OrderAuth.record;

function cancel_buy_order:
    input r0 as OrderCommitment.record;
    is.eq r0.direction 0u8 into r1;
    assert.eq r1 true;
    cast r0.limit_price into r2 as u128;
    mul r0.size r2 into r3;
    div r3 1000000u128 into r4;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private self.caller r4 into r5 r6 r7;
    async cancel_buy_order r7 r0.order_id into r8;
    output r8 as dara_dp_btc_v5.aleo/cancel_buy_order.future;

finalize cancel_buy_order:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as field.public;
    await r0;
    get.or_use pool_paused[0u8] false into r2;
    not r2 into r3;
    assert.eq r3 true;
    get.or_use order_consumed[r1] false into r4;
    not r4 into r5;
    assert.eq r5 true;
    set true into order_consumed[r1];

function cancel_sell_order:
    input r0 as OrderCommitment.record;
    is.eq r0.direction 1u8 into r1;
    assert.eq r1 true;
    cast r0.size into r2 as u64;
    call test_btc_v1.aleo/transfer_public_to_private self.caller r2 into r3 r4;
    async cancel_sell_order r4 r0.order_id into r5;
    output r5 as dara_dp_btc_v5.aleo/cancel_sell_order.future;

finalize cancel_sell_order:
    input r0 as test_btc_v1.aleo/transfer_public_to_private.future;
    input r1 as field.public;
    await r0;
    get.or_use order_consumed[r1] false into r2;
    not r2 into r3;
    assert.eq r3 true;
    set true into order_consumed[r1];

function advance_batch:
    input r0 as u64.private;
    async advance_batch self.caller r0 into r1;
    output r1 as dara_dp_btc_v5.aleo/advance_batch.future;

finalize advance_batch:
    input r0 as address.public;
    input r1 as u64.public;
    get operators[1u8] into r2;
    get operators[2u8] into r3;
    get operators[3u8] into r4;
    is.eq r0 r2 into r5;
    is.eq r0 r3 into r6;
    or r5 r6 into r7;
    is.eq r0 r4 into r8;
    or r7 r8 into r9;
    assert.eq r9 true;
    get.or_use current_batch[0u8] 1u64 into r10;
    assert.eq r1 r10;
    add r1 1u64 into r11;
    set r11 into current_batch[0u8];
    set block.height into batch_start_block[r11];

function withdraw_fees:
    input r0 as u128.private;
    gt r0 0u128 into r1;
    assert.eq r1 true;
    call test_usdcx_stablecoin.aleo/transfer_public_to_private self.caller r0 into r2 r3 r4;
    async withdraw_fees r4 self.caller r0 into r5;
    output r5 as dara_dp_btc_v5.aleo/withdraw_fees.future;

finalize withdraw_fees:
    input r0 as test_usdcx_stablecoin.aleo/transfer_public_to_private.future;
    input r1 as address.public;
    input r2 as u128.public;
    await r0;
    get operators[0u8] into r3;
    assert.eq r1 r3;
    get.or_use fee_vault[0u8] 0u128 into r4;
    lte r2 r4 into r5;
    assert.eq r5 true;
    sub r4 r2 into r6;
    set r6 into fee_vault[0u8];

function set_fee_bps:
    input r0 as u64.private;
    gte r0 1u64 into r1;
    assert.eq r1 true;
    lte r0 100u64 into r2;
    assert.eq r2 true;
    async set_fee_bps self.caller r0 into r3;
    output r3 as dara_dp_btc_v5.aleo/set_fee_bps.future;

finalize set_fee_bps:
    input r0 as address.public;
    input r1 as u64.public;
    get operators[0u8] into r2;
    assert.eq r0 r2;
    set r1 into fee_bps[0u8];

function pause_darkpool:
    async pause_darkpool self.caller into r0;
    output r0 as dara_dp_btc_v5.aleo/pause_darkpool.future;

finalize pause_darkpool:
    input r0 as address.public;
    get operators[0u8] into r1;
    assert.eq r0 r1;
    set true into pool_paused[0u8];

function resume_darkpool:
    async resume_darkpool self.caller into r0;
    output r0 as dara_dp_btc_v5.aleo/resume_darkpool.future;

finalize resume_darkpool:
    input r0 as address.public;
    get operators[0u8] into r1;
    assert.eq r0 r1;
    set false into pool_paused[0u8];

constructor:
    assert.eq edition 0u16;
