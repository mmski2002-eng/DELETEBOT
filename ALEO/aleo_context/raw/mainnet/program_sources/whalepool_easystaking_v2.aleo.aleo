import credits.aleo;

program whalepool_easystaking_v2.aleo;

struct bond_state:
    validator as address;
    microcredits as u64;

struct unbond_state:
    microcredits as u64;
    height as u32;

struct PoolInfo:
    validator as address;
    is_open as boolean;

mapping recharger:
    key as address.public;
    value as boolean.public;

mapping scope_check:
    key as u8.public;
    value as boolean.public;

mapping bonding_limit:
    key as u8.public;
    value as u64.public;

mapping un_bonding_limit:
    key as u8.public;
    value as u64.public;

mapping bonded:
    key as address.public;
    value as u64.public;

mapping unbonding:
    key as address.public;
    value as unbond_state.public;

mapping totals:
    key as u8.public;
    value as u64.public;

mapping pool_info:
    key as u8.public;
    value as PoolInfo.public;

function initialize:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public_as_signer whalepool_easystaking_v2.aleo r1 into r2;
    call credits.aleo/bond_public r0 whalepool_easystaking_v2.aleo r1 into r3;
    async initialize self.caller r0 r1 r2 r3 into r4;
    output r4 as whalepool_easystaking_v2.aleo/initialize.future;

finalize initialize:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as credits.aleo/transfer_public_as_signer.future;
    input r4 as credits.aleo/bond_public.future;
    is.eq r0 program_owner into r5;
    assert.eq r5 true;
    await r3;
    await r4;
    contains totals[0u8] into r6;
    not r6 into r7;
    assert.eq r7 true;
    set r2 into totals[0u8];
    set r2 into bonded[r0];
    cast r1 true into r8 as PoolInfo;
    set true into scope_check[0u8];
    set r8 into pool_info[0u8];
    set 10000000u64 into bonding_limit[0u8];
    set 10000000u64 into un_bonding_limit[0u8];

function bond_recharger:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    call credits.aleo/transfer_public_as_signer whalepool_easystaking_v2.aleo r2 into r3;
    call credits.aleo/bond_public r1 whalepool_easystaking_v2.aleo r2 into r4;
    async bond_recharger self.caller r0 r1 r2 r3 r4 into r5;
    output r5 as whalepool_easystaking_v2.aleo/bond_recharger.future;

finalize bond_recharger:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as address.public;
    input r3 as u64.public;
    input r4 as credits.aleo/transfer_public_as_signer.future;
    input r5 as credits.aleo/bond_public.future;
    get.or_use recharger[r0] false into r6;
    assert.eq r6 true;
    await r4;
    await r5;
    get.or_use bonded[r1] 0u64 into r7;
    add r7 r3 into r8;
    set r8 into bonded[r1];
    get.or_use totals[0u8] 0u64 into r9;
    add r9 r3 into r10;
    set r10 into totals[0u8];

function set_recharger:
    input r0 as address.public;
    input r1 as boolean.public;
    async set_recharger self.caller r0 r1 into r2;
    output r2 as whalepool_easystaking_v2.aleo/set_recharger.future;

finalize set_recharger:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as boolean.public;
    is.eq r0 program_owner into r3;
    assert.eq r3 true;
    contains recharger[r1] into r4;
    branch.eq r4 false to end_then_0_0;
    not r2 into r5;
    branch.eq r5 false to end_then_1_2;
    remove recharger[r1];
    branch.eq true true to end_otherwise_1_3;
    position end_then_1_2;
    position end_otherwise_1_3;
    branch.eq true true to end_otherwise_0_1;
    position end_then_0_0;
    branch.eq r2 false to end_then_1_4;
    set true into recharger[r1];
    branch.eq true true to end_otherwise_1_5;
    position end_then_1_4;
    position end_otherwise_1_5;
    position end_otherwise_0_1;

function set_scope_check:
    input r0 as boolean.public;
    async set_scope_check self.caller r0 into r1;
    output r1 as whalepool_easystaking_v2.aleo/set_scope_check.future;

finalize set_scope_check:
    input r0 as address.public;
    input r1 as boolean.public;
    is.eq r0 program_owner into r2;
    assert.eq r2 true;
    set r1 into scope_check[0u8];

function set_pool_state:
    input r0 as boolean.public;
    async set_pool_state self.caller r0 into r1;
    output r1 as whalepool_easystaking_v2.aleo/set_pool_state.future;

finalize set_pool_state:
    input r0 as address.public;
    input r1 as boolean.public;
    is.eq r0 program_owner into r2;
    assert.eq r2 true;
    get pool_info[0u8] into r3;
    branch.eq r1 false to end_then_0_6;
    get.or_use bonded[program_owner] 0u64 into r4;
    gte r4 10000000000u64 into r5;
    assert.eq r5 true;
    branch.eq true true to end_otherwise_0_7;
    position end_then_0_6;
    position end_otherwise_0_7;
    cast r3.validator r1 into r6 as PoolInfo;
    set r6 into pool_info[0u8];

function bond_public:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public_as_signer whalepool_easystaking_v2.aleo r1 into r2;
    call credits.aleo/bond_public r0 whalepool_easystaking_v2.aleo r1 into r3;
    async bond_public self.caller r0 r1 r2 r3 into r4;
    output r4 as whalepool_easystaking_v2.aleo/bond_public.future;

finalize bond_public:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as credits.aleo/transfer_public_as_signer.future;
    input r4 as credits.aleo/bond_public.future;
    get pool_info[0u8] into r5;
    get.or_use bonding_limit[0u8] 10000000u64 into r6;
    gte r2 r6 into r7;
    assert.eq r7 true;
    await r3;
    await r4;
    assert.eq r5.validator r1;
    assert.eq r5.is_open true;
    get.or_use bonded[r0] 0u64 into r8;
    add r8 r2 into r9;
    set r9 into bonded[r0];
    get totals[0u8] into r10;
    add r10 r2 into r11;
    set r11 into totals[0u8];

function unbond_public:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/unbond_public whalepool_easystaking_v2.aleo r1 into r2;
    async unbond_public self.caller r0 r1 r2 into r3;
    output r3 as whalepool_easystaking_v2.aleo/unbond_public.future;

finalize unbond_public:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as credits.aleo/unbond_public.future;
    get pool_info[0u8] into r4;
    is.eq r0 program_owner into r5;
    div 28800u32 2u32 into r6;
    mod block.height 28800u32 into r7;
    lt r7 r6 into r8;
    get.or_use scope_check[0u8] true into r9;
    not r5 into r10;
    branch.eq r10 false to end_then_0_8;
    get.or_use un_bonding_limit[0u8] 10000000u64 into r11;
    gte r2 r11 into r12;
    assert.eq r12 true;
    branch.eq r9 false to end_then_1_10;
    assert.eq r8 true;
    branch.eq true true to end_otherwise_1_11;
    position end_then_1_10;
    position end_otherwise_1_11;
    branch.eq true true to end_otherwise_0_9;
    position end_then_0_8;
    position end_otherwise_0_9;
    cast whalepool_easystaking_v2.aleo 0u64 into r13 as bond_state;
    get.or_use credits.aleo/bonded[whalepool_easystaking_v2.aleo] r13 into r14;
    await r3;
    is.eq r0 r1 into r15;
    get bonded[r1] into r16;
    get totals[0u8] into r17;
    contains credits.aleo/bonded[whalepool_easystaking_v2.aleo] into r18;
    not r18 into r19;
    branch.eq r5 false to end_then_0_12;
    branch.eq r19 false to end_then_1_14;
    assert.eq r16 r17;
    branch.eq true true to end_otherwise_1_15;
    position end_then_1_14;
    position end_otherwise_1_15;
    branch.eq true true to end_otherwise_0_13;
    position end_then_0_12;
    assert.eq r15 true;
    not r19 into r20;
    assert.eq r20 true;
    position end_otherwise_0_13;
    gte r16 r2 into r21;
    assert.eq r21 true;
    sub r16 r2 into r22;
    sub r17 r2 into r23;
    is.eq r22 0u64 into r24;
    or r24 r19 into r25;
    branch.eq r25 false to end_then_0_16;
    remove bonded[r1];
    branch.eq true true to end_otherwise_0_17;
    position end_then_0_16;
    set r22 into bonded[r1];
    position end_otherwise_0_17;
    is.eq r23 0u64 into r26;
    or r26 r19 into r27;
    branch.eq r27 false to end_then_0_18;
    remove totals[0u8];
    cast r4.validator false into r28 as PoolInfo;
    set r28 into pool_info[0u8];
    branch.eq true true to end_otherwise_0_19;
    position end_then_0_18;
    set r23 into totals[0u8];
    position end_otherwise_0_19;
    add block.height 360u32 into r29;
    cast 0u64 r29 into r30 as unbond_state;
    get.or_use unbonding[r1] r30 into r31;
    ternary r19 r14.microcredits r2 into r32;
    add r31.microcredits r32 into r33;
    cast r33 r29 into r34 as unbond_state;
    set r34 into unbonding[r1];
    get.or_use totals[1u8] 0u64 into r35;
    add r35 r32 into r36;
    set r36 into totals[1u8];

function unbond_pos_rewards:
    input r0 as u64.public;
    call credits.aleo/unbond_public whalepool_easystaking_v2.aleo r0 into r1;
    async unbond_pos_rewards self.caller r0 r1 into r2;
    output r2 as whalepool_easystaking_v2.aleo/unbond_pos_rewards.future;

finalize unbond_pos_rewards:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as credits.aleo/unbond_public.future;
    cast whalepool_easystaking_v2.aleo 0u64 into r3 as bond_state;
    get.or_use credits.aleo/bonded[whalepool_easystaking_v2.aleo] r3 into r4;
    get.or_use totals[0u8] 0u64 into r5;
    is.eq program_owner r0 into r6;
    assert.eq r6 true;
    await r2;
    sub r4.microcredits r1 into r7;
    gte r7 r5 into r8;
    assert.eq r8 true;

function claim_unbond_public:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public r0 r1 into r2;
    async claim_unbond_public self.caller r0 r1 r2 into r3;
    output r3 as whalepool_easystaking_v2.aleo/claim_unbond_public.future;

finalize claim_unbond_public:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as credits.aleo/transfer_public.future;
    is.eq r0 program_owner into r4;
    div 28800u32 2u32 into r5;
    add r5 400u32 into r6;
    mod block.height 28800u32 into r7;
    gt r7 r6 into r8;
    get.or_use scope_check[0u8] true into r9;
    not r4 into r10;
    and r10 r9 into r11;
    branch.eq r11 false to end_then_0_20;
    assert.eq r8 true;
    branch.eq true true to end_otherwise_0_21;
    position end_then_0_20;
    position end_otherwise_0_21;
    await r3;
    get unbonding[r1] into r12;
    assert.eq r12.microcredits r2;
    gte block.height r12.height into r13;
    assert.eq r13 true;
    remove unbonding[r1];
    get totals[1u8] into r14;
    sub r14 r2 into r15;
    set r15 into totals[1u8];

function transfer_public:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public r0 r1 into r2;
    async transfer_public self.caller r0 r1 r2 into r3;
    output r3 as whalepool_easystaking_v2.aleo/transfer_public.future;

finalize transfer_public:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as credits.aleo/transfer_public.future;
    await r3;
    is.eq program_owner r0 into r4;
    assert.eq r4 true;
    get credits.aleo/account[whalepool_easystaking_v2.aleo] into r5;
    cast whalepool_easystaking_v2.aleo 0u64 into r6 as bond_state;
    get.or_use credits.aleo/bonded[whalepool_easystaking_v2.aleo] r6 into r7;
    cast 0u64 0u32 into r8 as unbond_state;
    get.or_use credits.aleo/unbonding[whalepool_easystaking_v2.aleo] r8 into r9;
    add r5 r7.microcredits into r10;
    add r10 r9.microcredits into r11;
    get.or_use totals[0u8] 0u64 into r12;
    get.or_use totals[1u8] 0u64 into r13;
    add r12 r13 into r14;
    gte r11 r14 into r15;
    assert.eq r15 true;

function fallback_unbond_if_removed:
    input r0 as address.public;
    async fallback_unbond_if_removed r0 into r1;
    output r1 as whalepool_easystaking_v2.aleo/fallback_unbond_if_removed.future;

finalize fallback_unbond_if_removed:
    input r0 as address.public;
    contains credits.aleo/bonded[whalepool_easystaking_v2.aleo] into r1;
    not r1 into r2;
    assert.eq r2 true;
    get bonded[r0] into r3;
    get totals[0u8] into r4;
    remove bonded[r0];
    sub r4 r3 into r5;
    is.eq r5 0u64 into r6;
    branch.eq r6 false to end_then_0_22;
    remove totals[0u8];
    get pool_info[0u8] into r7;
    cast r7.validator false into r8 as PoolInfo;
    set r8 into pool_info[0u8];
    branch.eq true true to end_otherwise_0_23;
    position end_then_0_22;
    set r5 into totals[0u8];
    position end_otherwise_0_23;
    add block.height 360u32 into r9;
    cast 0u64 r9 into r10 as unbond_state;
    get.or_use unbonding[r0] r10 into r11;
    add r11.microcredits r3 into r12;
    cast r12 r9 into r13 as unbond_state;
    set r13 into unbonding[r0];
    get.or_use totals[1u8] 0u64 into r14;
    add r14 r3 into r15;
    set r15 into totals[1u8];

constructor:
    assert.eq program_owner aleo1kwf3x892cwpm7w2vczsh7ywsk783h2scx4d5upy7k8494d23sgqqnjwzfr;
