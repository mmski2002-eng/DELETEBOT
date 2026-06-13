program f89b0d41ebe03707fd1f37ef95255ac.aleo;

struct TokenOwner:
    token as field;
    holder as address;

struct LpOwner:
    pool_id as u64;
    holder as address;

mapping pool_token0:
    key as u64.public;
    value as field.public;

mapping pool_token1:
    key as u64.public;
    value as field.public;

mapping pool_reserve0:
    key as u64.public;
    value as u128.public;

mapping pool_reserve1:
    key as u64.public;
    value as u128.public;

mapping pool_total_supply:
    key as u64.public;
    value as u128.public;

mapping pool_fee_bps:
    key as u64.public;
    value as u16.public;

mapping pool_enabled:
    key as u64.public;
    value as boolean.public;

mapping lp_balances:
    key as field.public;
    value as u128.public;

mapping token_balances:
    key as field.public;
    value as u128.public;

mapping next_pool_id:
    key as boolean.public;
    value as u64.public;

function create_pool:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u16.public;
    is.neq r0 r1 into r3;
    assert.eq r3 true;
    lte r2 100u16 into r4;
    assert.eq r4 true;
    async create_pool r0 r1 r2 into r5;
    output r5 as f89b0d41ebe03707fd1f37ef95255ac.aleo/create_pool.future;

finalize create_pool:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u16.public;
    get.or_use next_pool_id[true] 0u64 into r3;
    add r3 1u64 into r4;
    set r4 into next_pool_id[true];
    set r0 into pool_token0[r3];
    set r1 into pool_token1[r3];
    set r2 into pool_fee_bps[r3];
    set true into pool_enabled[r3];
    set 0u128 into pool_reserve0[r3];
    set 0u128 into pool_reserve1[r3];
    set 0u128 into pool_total_supply[r3];

function deposit:
    input r0 as field.public;
    input r1 as u128.public;
    gt r1 0u128 into r2;
    assert.eq r2 true;
    cast r0 self.caller into r3 as TokenOwner;
    hash.bhp256 r3 into r4 as field;
    async deposit r4 r1 into r5;
    output r5 as f89b0d41ebe03707fd1f37ef95255ac.aleo/deposit.future;

finalize deposit:
    input r0 as field.public;
    input r1 as u128.public;
    get.or_use token_balances[r0] 0u128 into r2;
    add r2 r1 into r3;
    set r3 into token_balances[r0];

function withdraw:
    input r0 as field.public;
    input r1 as u128.public;
    gt r1 0u128 into r2;
    assert.eq r2 true;
    cast r0 self.caller into r3 as TokenOwner;
    hash.bhp256 r3 into r4 as field;
    async withdraw r4 r1 into r5;
    output r5 as f89b0d41ebe03707fd1f37ef95255ac.aleo/withdraw.future;

finalize withdraw:
    input r0 as field.public;
    input r1 as u128.public;
    get token_balances[r0] into r2;
    gte r2 r1 into r3;
    assert.eq r3 true;
    sub r2 r1 into r4;
    set r4 into token_balances[r0];

function add_liquidity:
    input r0 as u64.public;
    input r1 as field.public;
    input r2 as field.public;
    input r3 as u128.public;
    input r4 as u128.public;
    input r5 as u128.public;
    gt r3 0u128 into r6;
    assert.eq r6 true;
    gt r4 0u128 into r7;
    assert.eq r7 true;
    cast r1 self.caller into r8 as TokenOwner;
    hash.bhp256 r8 into r9 as field;
    cast r2 self.caller into r10 as TokenOwner;
    hash.bhp256 r10 into r11 as field;
    cast r0 self.caller into r12 as LpOwner;
    hash.bhp256 r12 into r13 as field;
    async add_liquidity r0 r1 r2 r3 r4 r5 r9 r11 r13 into r14;
    output r14 as f89b0d41ebe03707fd1f37ef95255ac.aleo/add_liquidity.future;

finalize add_liquidity:
    input r0 as u64.public;
    input r1 as field.public;
    input r2 as field.public;
    input r3 as u128.public;
    input r4 as u128.public;
    input r5 as u128.public;
    input r6 as field.public;
    input r7 as field.public;
    input r8 as field.public;
    get pool_reserve0[r0] into r9;
    get pool_reserve1[r0] into r10;
    get pool_total_supply[r0] into r11;
    get pool_enabled[r0] into r12;
    get pool_token0[r0] into r13;
    get pool_token1[r0] into r14;
    assert.eq r12 true;
    is.eq r13 r1 into r15;
    assert.eq r15 true;
    is.eq r14 r2 into r16;
    assert.eq r16 true;
    is.eq r11 0u128 into r17;
    not r17 into r18;
    branch.eq r18 false to end_then_0_0;
    mul r3 r10 into r19;
    mul r4 r9 into r20;
    is.eq r19 r20 into r21;
    assert.eq r21 true;
    branch.eq true true to end_otherwise_0_1;
    position end_then_0_0;
    position end_otherwise_0_1;
    ternary r17 1u128 0u128 into r22;
    add r9 r22 into r23;
    mul r3 r11 into r24;
    div r24 r23 into r25;
    ternary r17 r3 r25 into r26;
    gte r26 r5 into r27;
    assert.eq r27 true;
    get token_balances[r6] into r28;
    get token_balances[r7] into r29;
    gte r28 r3 into r30;
    assert.eq r30 true;
    gte r29 r4 into r31;
    assert.eq r31 true;
    sub r28 r3 into r32;
    set r32 into token_balances[r6];
    sub r29 r4 into r33;
    set r33 into token_balances[r7];
    get.or_use lp_balances[r8] 0u128 into r34;
    add r34 r26 into r35;
    set r35 into lp_balances[r8];
    add r9 r3 into r36;
    set r36 into pool_reserve0[r0];
    add r10 r4 into r37;
    set r37 into pool_reserve1[r0];
    add r11 r26 into r38;
    set r38 into pool_total_supply[r0];

function remove_liquidity:
    input r0 as u64.public;
    input r1 as field.public;
    input r2 as field.public;
    input r3 as u128.public;
    input r4 as u128.public;
    input r5 as u128.public;
    gt r3 0u128 into r6;
    assert.eq r6 true;
    cast r0 self.caller into r7 as LpOwner;
    hash.bhp256 r7 into r8 as field;
    cast r1 self.caller into r9 as TokenOwner;
    hash.bhp256 r9 into r10 as field;
    cast r2 self.caller into r11 as TokenOwner;
    hash.bhp256 r11 into r12 as field;
    async remove_liquidity r0 r3 r4 r5 r8 r10 r12 into r13;
    output r13 as f89b0d41ebe03707fd1f37ef95255ac.aleo/remove_liquidity.future;

finalize remove_liquidity:
    input r0 as u64.public;
    input r1 as u128.public;
    input r2 as u128.public;
    input r3 as u128.public;
    input r4 as field.public;
    input r5 as field.public;
    input r6 as field.public;
    get pool_reserve0[r0] into r7;
    get pool_reserve1[r0] into r8;
    get pool_total_supply[r0] into r9;
    gt r9 0u128 into r10;
    assert.eq r10 true;
    mul r1 r7 into r11;
    div r11 r9 into r12;
    mul r1 r8 into r13;
    div r13 r9 into r14;
    gte r12 r2 into r15;
    assert.eq r15 true;
    gte r14 r3 into r16;
    assert.eq r16 true;
    get lp_balances[r4] into r17;
    gte r17 r1 into r18;
    assert.eq r18 true;
    sub r17 r1 into r19;
    set r19 into lp_balances[r4];
    get.or_use token_balances[r5] 0u128 into r20;
    get.or_use token_balances[r6] 0u128 into r21;
    add r20 r12 into r22;
    set r22 into token_balances[r5];
    add r21 r14 into r23;
    set r23 into token_balances[r6];
    sub r7 r12 into r24;
    set r24 into pool_reserve0[r0];
    sub r8 r14 into r25;
    set r25 into pool_reserve1[r0];
    sub r9 r1 into r26;
    set r26 into pool_total_supply[r0];

function swap:
    input r0 as u64.public;
    input r1 as field.public;
    input r2 as field.public;
    input r3 as u128.public;
    input r4 as u128.public;
    gt r3 0u128 into r5;
    assert.eq r5 true;
    cast r1 self.caller into r6 as TokenOwner;
    hash.bhp256 r6 into r7 as field;
    cast r2 self.caller into r8 as TokenOwner;
    hash.bhp256 r8 into r9 as field;
    async swap r0 r1 r2 r3 r4 r7 r9 into r10;
    output r10 as f89b0d41ebe03707fd1f37ef95255ac.aleo/swap.future;

finalize swap:
    input r0 as u64.public;
    input r1 as field.public;
    input r2 as field.public;
    input r3 as u128.public;
    input r4 as u128.public;
    input r5 as field.public;
    input r6 as field.public;
    get pool_token0[r0] into r7;
    get pool_token1[r0] into r8;
    get pool_enabled[r0] into r9;
    assert.eq r9 true;
    is.eq r1 r7 into r10;
    is.eq r1 r8 into r11;
    or r10 r11 into r12;
    assert.eq r12 true;
    ternary r10 r8 r7 into r13;
    is.eq r13 r2 into r14;
    assert.eq r14 true;
    get pool_reserve0[r0] into r15;
    get pool_reserve1[r0] into r16;
    get pool_fee_bps[r0] into r17;
    ternary r10 r15 r16 into r18;
    ternary r10 r16 r15 into r19;
    cast r17 into r20 as u128;
    sub 10000u128 r20 into r21;
    mul r3 r21 into r22;
    mul r22 r19 into r23;
    mul r18 10000u128 into r24;
    add r24 r22 into r25;
    div r23 r25 into r26;
    gte r26 r4 into r27;
    assert.eq r27 true;
    lt r26 r19 into r28;
    assert.eq r28 true;
    get token_balances[r5] into r29;
    gte r29 r3 into r30;
    assert.eq r30 true;
    sub r29 r3 into r31;
    set r31 into token_balances[r5];
    get.or_use token_balances[r6] 0u128 into r32;
    add r32 r26 into r33;
    set r33 into token_balances[r6];
    add r15 r3 into r34;
    sub r15 r26 into r35;
    ternary r10 r34 r35 into r36;
    sub r16 r26 into r37;
    add r16 r3 into r38;
    ternary r10 r37 r38 into r39;
    set r36 into pool_reserve0[r0];
    set r39 into pool_reserve1[r0];

constructor:
    assert.eq edition 0u16;
