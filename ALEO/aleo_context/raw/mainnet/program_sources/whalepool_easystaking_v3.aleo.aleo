import credits.aleo;

program whalepool_easystaking_v3.aleo;

struct PoolInfo:
    validator as address;
    is_open as boolean;

struct Optional__HdJPTit9rcT:
    is_some as boolean;
    val as address;

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
    value as credits.aleo/unbond_state.public;

mapping totals:
    key as u8.public;
    value as u64.public;

mapping pool_info:
    key as u8.public;
    value as PoolInfo.public;

mapping employee__:
    key as boolean.public;
    value as address.public;

function transfer_public:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public r0 r1 into r2;
    async transfer_public self.caller r0 r1 r2 into r3;
    output r3 as whalepool_easystaking_v3.aleo/transfer_public.future;

finalize transfer_public:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as credits.aleo/transfer_public.future;
    contains employee__[false] into r4;
    get.or_use employee__[false] aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r5;
    cast true r5 into r6 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r7 as Optional__HdJPTit9rcT;
    ternary r4 r6.is_some r7.is_some into r8;
    ternary r4 r6.val r7.val into r9;
    cast r8 r9 into r10 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r11 as Optional__HdJPTit9rcT;
    is.eq r10 r11 into r12;
    branch.eq r12 false to end_then_0_0;
    is.eq r0 program_owner into r13;
    assert.eq r13 true;
    branch.eq true true to end_otherwise_0_1;
    position end_then_0_0;
    contains employee__[false] into r14;
    get.or_use employee__[false] aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r15;
    cast true r15 into r16 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r17 as Optional__HdJPTit9rcT;
    ternary r14 r16.is_some r17.is_some into r18;
    ternary r14 r16.val r17.val into r19;
    cast r18 r19 into r20 as Optional__HdJPTit9rcT;
    assert.eq r20.is_some true;
    contains employee__[false] into r21;
    get.or_use employee__[false] aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r22;
    cast true r22 into r23 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r24 as Optional__HdJPTit9rcT;
    ternary r21 r23.is_some r24.is_some into r25;
    ternary r21 r23.val r24.val into r26;
    cast r25 r26 into r27 as Optional__HdJPTit9rcT;
    is.eq r0 program_owner into r28;
    is.eq r0 r27.val into r29;
    or r28 r29 into r30;
    assert.eq r30 true;
    position end_otherwise_0_1;
    await r3;
    get credits.aleo/account[whalepool_easystaking_v3.aleo] into r31;
    cast whalepool_easystaking_v3.aleo 0u64 into r32 as credits.aleo/bond_state;
    get.or_use credits.aleo/bonded[whalepool_easystaking_v3.aleo] r32 into r33;
    cast 0u64 0u32 into r34 as credits.aleo/unbond_state;
    get.or_use credits.aleo/unbonding[whalepool_easystaking_v3.aleo] r34 into r35;
    add r31 r33.microcredits into r36;
    add r36 r35.microcredits into r37;
    get.or_use totals[0u8] 0u64 into r38;
    get.or_use totals[1u8] 0u64 into r39;
    add r38 r39 into r40;
    gte r37 r40 into r41;
    assert.eq r41 true;

function claim_unbond_public:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public r0 r1 into r2;
    async claim_unbond_public self.caller r0 r1 r2 into r3;
    output r3 as whalepool_easystaking_v3.aleo/claim_unbond_public.future;

finalize claim_unbond_public:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as credits.aleo/transfer_public.future;
    is.eq r0 program_owner into r4;
    mod block.height 28800u32 into r5;
    gt r5 14800u32 into r6;
    get.or_use scope_check[0u8] true into r7;
    not r4 into r8;
    and r8 r7 into r9;
    branch.eq r9 false to end_then_0_2;
    assert.eq r6 true;
    branch.eq true true to end_otherwise_0_3;
    position end_then_0_2;
    position end_otherwise_0_3;
    await r3;
    get unbonding[r1] into r10;
    assert.eq r10.microcredits r2;
    gte block.height r10.height into r11;
    assert.eq r11 true;
    remove unbonding[r1];
    get totals[1u8] into r12;
    sub r12 r2 into r13;
    set r13 into totals[1u8];

function unbond_public:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/unbond_public whalepool_easystaking_v3.aleo r1 into r2;
    async unbond_public self.caller r0 r1 r2 into r3;
    output r3 as whalepool_easystaking_v3.aleo/unbond_public.future;

finalize unbond_public:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as credits.aleo/unbond_public.future;
    get pool_info[0u8] into r4;
    is.eq r0 program_owner into r5;
    mod block.height 28800u32 into r6;
    lt r6 14400u32 into r7;
    get.or_use scope_check[0u8] true into r8;
    assert.eq r4.is_open true;
    not r5 into r9;
    branch.eq r9 false to end_then_0_4;
    get.or_use un_bonding_limit[0u8] 10000000u64 into r10;
    gte r2 r10 into r11;
    assert.eq r11 true;
    branch.eq r8 false to end_then_1_6;
    assert.eq r7 true;
    branch.eq true true to end_otherwise_1_7;
    position end_then_1_6;
    position end_otherwise_1_7;
    branch.eq true true to end_otherwise_0_5;
    position end_then_0_4;
    position end_otherwise_0_5;
    cast whalepool_easystaking_v3.aleo 0u64 into r12 as credits.aleo/bond_state;
    get.or_use credits.aleo/bonded[whalepool_easystaking_v3.aleo] r12 into r13;
    await r3;
    is.eq r0 r1 into r14;
    get bonded[r1] into r15;
    get totals[0u8] into r16;
    contains credits.aleo/bonded[whalepool_easystaking_v3.aleo] into r17;
    not r17 into r18;
    branch.eq r5 false to end_then_0_8;
    branch.eq r18 false to end_then_1_10;
    assert.eq r15 r16;
    branch.eq true true to end_otherwise_1_11;
    position end_then_1_10;
    position end_otherwise_1_11;
    branch.eq true true to end_otherwise_0_9;
    position end_then_0_8;
    assert.eq r14 true;
    not r18 into r19;
    assert.eq r19 true;
    position end_otherwise_0_9;
    gte r15 r2 into r20;
    assert.eq r20 true;
    sub r15 r2 into r21;
    sub r16 r2 into r22;
    is.eq r21 0u64 into r23;
    or r23 r18 into r24;
    branch.eq r24 false to end_then_0_12;
    remove bonded[r1];
    branch.eq true true to end_otherwise_0_13;
    position end_then_0_12;
    set r21 into bonded[r1];
    position end_otherwise_0_13;
    is.eq r22 0u64 into r25;
    or r25 r18 into r26;
    branch.eq r26 false to end_then_0_14;
    remove totals[0u8];
    cast r4.validator false into r27 as PoolInfo;
    set r27 into pool_info[0u8];
    branch.eq true true to end_otherwise_0_15;
    position end_then_0_14;
    set r22 into totals[0u8];
    position end_otherwise_0_15;
    add block.height 360u32 into r28;
    cast 0u64 r28 into r29 as credits.aleo/unbond_state;
    get.or_use unbonding[r1] r29 into r30;
    ternary r18 r13.microcredits r2 into r31;
    add r30.microcredits r31 into r32;
    cast r32 r28 into r33 as credits.aleo/unbond_state;
    set r33 into unbonding[r1];
    get.or_use totals[1u8] 0u64 into r34;
    add r34 r31 into r35;
    set r35 into totals[1u8];

function unbond_pos_rewards:
    input r0 as u64.public;
    call credits.aleo/unbond_public whalepool_easystaking_v3.aleo r0 into r1;
    async unbond_pos_rewards self.caller r0 r1 into r2;
    output r2 as whalepool_easystaking_v3.aleo/unbond_pos_rewards.future;

finalize unbond_pos_rewards:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as credits.aleo/unbond_public.future;
    cast whalepool_easystaking_v3.aleo 0u64 into r3 as credits.aleo/bond_state;
    get.or_use credits.aleo/bonded[whalepool_easystaking_v3.aleo] r3 into r4;
    get.or_use totals[0u8] 0u64 into r5;
    contains employee__[false] into r6;
    get.or_use employee__[false] aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r7;
    cast true r7 into r8 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r9 as Optional__HdJPTit9rcT;
    ternary r6 r8.is_some r9.is_some into r10;
    ternary r6 r8.val r9.val into r11;
    cast r10 r11 into r12 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r13 as Optional__HdJPTit9rcT;
    is.eq r12 r13 into r14;
    branch.eq r14 false to end_then_0_16;
    is.eq r0 program_owner into r15;
    assert.eq r15 true;
    branch.eq true true to end_otherwise_0_17;
    position end_then_0_16;
    contains employee__[false] into r16;
    get.or_use employee__[false] aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r17;
    cast true r17 into r18 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r19 as Optional__HdJPTit9rcT;
    ternary r16 r18.is_some r19.is_some into r20;
    ternary r16 r18.val r19.val into r21;
    cast r20 r21 into r22 as Optional__HdJPTit9rcT;
    assert.eq r22.is_some true;
    contains employee__[false] into r23;
    get.or_use employee__[false] aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r24;
    cast true r24 into r25 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r26 as Optional__HdJPTit9rcT;
    ternary r23 r25.is_some r26.is_some into r27;
    ternary r23 r25.val r26.val into r28;
    cast r27 r28 into r29 as Optional__HdJPTit9rcT;
    is.eq r0 program_owner into r30;
    is.eq r0 r29.val into r31;
    or r30 r31 into r32;
    assert.eq r32 true;
    position end_otherwise_0_17;
    await r2;
    sub r4.microcredits r1 into r33;
    gte r33 r5 into r34;
    assert.eq r34 true;

function admin_change_validator_stake:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/bond_public r0 whalepool_easystaking_v3.aleo r1 into r2;
    async admin_change_validator_stake self.caller r0 r1 r2 into r3;
    output r3 as whalepool_easystaking_v3.aleo/admin_change_validator_stake.future;

finalize admin_change_validator_stake:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as credits.aleo/bond_public.future;
    is.eq r0 program_owner into r4;
    assert.eq r4 true;
    cast whalepool_easystaking_v3.aleo 0u64 into r5 as credits.aleo/bond_state;
    get.or_use credits.aleo/bonded[whalepool_easystaking_v3.aleo] r5 into r6;
    assert.eq r6.microcredits 0u64;
    await r3;
    get pool_info[0u8] into r7;
    cast r1 r7.is_open into r8 as PoolInfo;
    set r8 into pool_info[0u8];

function admin_unbond_credits:
    input r0 as u64.public;
    call credits.aleo/unbond_public whalepool_easystaking_v3.aleo r0 into r1;
    async admin_unbond_credits self.caller r0 r1 into r2;
    output r2 as whalepool_easystaking_v3.aleo/admin_unbond_credits.future;

finalize admin_unbond_credits:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as credits.aleo/unbond_public.future;
    cast whalepool_easystaking_v3.aleo 0u64 into r3 as credits.aleo/bond_state;
    get.or_use credits.aleo/bonded[whalepool_easystaking_v3.aleo] r3 into r4;
    lte r1 r4.microcredits into r5;
    assert.eq r5 true;
    get pool_info[0u8] into r6;
    is.eq r0 program_owner into r7;
    assert.eq r7 true;
    await r2;
    assert.eq r6.is_open false;

function bond_public:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public_as_signer whalepool_easystaking_v3.aleo r1 into r2;
    call credits.aleo/bond_public r0 whalepool_easystaking_v3.aleo r1 into r3;
    async bond_public self.caller r1 r0 r2 r3 into r4;
    output r4 as whalepool_easystaking_v3.aleo/bond_public.future;

finalize bond_public:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as address.public;
    input r3 as credits.aleo/transfer_public_as_signer.future;
    input r4 as credits.aleo/bond_public.future;
    get pool_info[0u8] into r5;
    get pool_info[0u8] into r6;
    assert.eq r6.validator r2;
    assert.eq r6.is_open true;
    get.or_use bonding_limit[0u8] 10000000u64 into r7;
    gte r1 r7 into r8;
    assert.eq r8 true;
    await r3;
    await r4;
    get.or_use bonded[r0] 0u64 into r9;
    add r9 r1 into r10;
    set r10 into bonded[r0];
    get.or_use totals[0u8] 0u64 into r11;
    add r11 r1 into r12;
    set r12 into totals[0u8];

function set_scope_check:
    input r0 as boolean.public;
    async set_scope_check self.caller r0 into r1;
    output r1 as whalepool_easystaking_v3.aleo/set_scope_check.future;

finalize set_scope_check:
    input r0 as address.public;
    input r1 as boolean.public;
    contains employee__[false] into r2;
    get.or_use employee__[false] aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r3;
    cast true r3 into r4 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r5 as Optional__HdJPTit9rcT;
    ternary r2 r4.is_some r5.is_some into r6;
    ternary r2 r4.val r5.val into r7;
    cast r6 r7 into r8 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r9 as Optional__HdJPTit9rcT;
    is.eq r8 r9 into r10;
    branch.eq r10 false to end_then_0_18;
    is.eq r0 program_owner into r11;
    assert.eq r11 true;
    branch.eq true true to end_otherwise_0_19;
    position end_then_0_18;
    contains employee__[false] into r12;
    get.or_use employee__[false] aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r13;
    cast true r13 into r14 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r15 as Optional__HdJPTit9rcT;
    ternary r12 r14.is_some r15.is_some into r16;
    ternary r12 r14.val r15.val into r17;
    cast r16 r17 into r18 as Optional__HdJPTit9rcT;
    assert.eq r18.is_some true;
    contains employee__[false] into r19;
    get.or_use employee__[false] aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r20;
    cast true r20 into r21 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r22 as Optional__HdJPTit9rcT;
    ternary r19 r21.is_some r22.is_some into r23;
    ternary r19 r21.val r22.val into r24;
    cast r23 r24 into r25 as Optional__HdJPTit9rcT;
    is.eq r0 program_owner into r26;
    is.eq r0 r25.val into r27;
    or r26 r27 into r28;
    assert.eq r28 true;
    position end_otherwise_0_19;
    set r1 into scope_check[0u8];

function set_pool_state:
    input r0 as boolean.public;
    async set_pool_state self.caller r0 into r1;
    output r1 as whalepool_easystaking_v3.aleo/set_pool_state.future;

finalize set_pool_state:
    input r0 as address.public;
    input r1 as boolean.public;
    is.eq r0 program_owner into r2;
    assert.eq r2 true;
    get pool_info[0u8] into r3;
    branch.eq r1 false to end_then_0_20;
    get.or_use bonded[program_owner] 0u64 into r4;
    gte r4 10000000000u64 into r5;
    assert.eq r5 true;
    branch.eq true true to end_otherwise_0_21;
    position end_then_0_20;
    position end_otherwise_0_21;
    cast r3.validator r1 into r6 as PoolInfo;
    set r6 into pool_info[0u8];

function set_employee:
    input r0 as address.public;
    async set_employee self.caller r0 into r1;
    output r1 as whalepool_easystaking_v3.aleo/set_employee.future;

finalize set_employee:
    input r0 as address.public;
    input r1 as address.public;
    is.eq r0 program_owner into r2;
    assert.eq r2 true;
    set r1 into employee__[false];

function initialize:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public_as_signer whalepool_easystaking_v3.aleo r1 into r2;
    call credits.aleo/bond_public r0 whalepool_easystaking_v3.aleo r1 into r3;
    async initialize self.caller r0 r1 r2 r3 into r4;
    output r4 as whalepool_easystaking_v3.aleo/initialize.future;

finalize initialize:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as credits.aleo/transfer_public_as_signer.future;
    input r4 as credits.aleo/bond_public.future;
    contains employee__[false] into r5;
    get.or_use employee__[false] aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r6;
    cast true r6 into r7 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r8 as Optional__HdJPTit9rcT;
    ternary r5 r7.is_some r8.is_some into r9;
    ternary r5 r7.val r8.val into r10;
    cast r9 r10 into r11 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r12 as Optional__HdJPTit9rcT;
    is.eq r11 r12 into r13;
    branch.eq r13 false to end_then_0_22;
    is.eq r0 program_owner into r14;
    assert.eq r14 true;
    branch.eq true true to end_otherwise_0_23;
    position end_then_0_22;
    contains employee__[false] into r15;
    get.or_use employee__[false] aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r16;
    cast true r16 into r17 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r18 as Optional__HdJPTit9rcT;
    ternary r15 r17.is_some r18.is_some into r19;
    ternary r15 r17.val r18.val into r20;
    cast r19 r20 into r21 as Optional__HdJPTit9rcT;
    assert.eq r21.is_some true;
    contains employee__[false] into r22;
    get.or_use employee__[false] aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r23;
    cast true r23 into r24 as Optional__HdJPTit9rcT;
    cast false aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r25 as Optional__HdJPTit9rcT;
    ternary r22 r24.is_some r25.is_some into r26;
    ternary r22 r24.val r25.val into r27;
    cast r26 r27 into r28 as Optional__HdJPTit9rcT;
    is.eq r0 program_owner into r29;
    is.eq r0 r28.val into r30;
    or r29 r30 into r31;
    assert.eq r31 true;
    position end_otherwise_0_23;
    await r3;
    await r4;
    contains totals[0u8] into r32;
    not r32 into r33;
    assert.eq r33 true;
    set r2 into totals[0u8];
    set r2 into bonded[r0];
    cast r1 true into r34 as PoolInfo;
    set true into scope_check[0u8];
    set r34 into pool_info[0u8];
    set 10000000u64 into bonding_limit[0u8];
    set 10000000u64 into un_bonding_limit[0u8];

constructor:
    assert.eq program_owner aleo1aekd0ufset8gzaay3eezsq2sre5d69px389qd39et8k2wxzrwg8se976gt;
