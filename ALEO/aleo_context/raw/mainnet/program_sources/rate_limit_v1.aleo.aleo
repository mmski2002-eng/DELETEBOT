import gmp_checksum_v1.aleo;

program rate_limit_v1.aleo;

struct RateLimitConfig:
    rate_per_second as u128;
    last_updated as i64;
    available as u128;
    max_available as u128;

mapping owner_rate_limit:
    key as boolean.public;
    value as address.public;

mapping asset_manager_core:
    key as boolean.public;
    value as address.public;

mapping pause_status:
    key as boolean.public;
    value as boolean.public;

mapping token_config:
    key as field.public;
    value as RateLimitConfig.public;

function initialize:
    input r0 as address.public;
    input r1 as address.public;
    assert.eq self.caller aleo1yhqmy5wkal76ks837svjzc97hqgjeuy2rhegthtmrxmx5phehu9sr6hxgx;
    async initialize r0 r1 into r2;
    output r2 as rate_limit_v1.aleo/initialize.future;

finalize initialize:
    input r0 as address.public;
    input r1 as address.public;
    contains owner_rate_limit[true] into r2;
    not r2 into r3;
    assert.eq r3 true;
    set r0 into owner_rate_limit[true];
    set r1 into asset_manager_core[true];
    set false into pause_status[true];

function set_asset_manager:
    input r0 as address.public;
    async set_asset_manager self.caller r0 into r1;
    output r1 as rate_limit_v1.aleo/set_asset_manager.future;

finalize set_asset_manager:
    input r0 as address.public;
    input r1 as address.public;
    get owner_rate_limit[true] into r2;
    assert.eq r2 r0;
    set r1 into asset_manager_core[true];

function pause:
    async pause self.caller into r0;
    output r0 as rate_limit_v1.aleo/pause.future;

finalize pause:
    input r0 as address.public;
    get owner_rate_limit[true] into r1;
    assert.eq r1 r0;
    get.or_use pause_status[true] false into r2;
    assert.eq r2 false;
    set true into pause_status[true];

function unpause:
    async unpause self.caller into r0;
    output r0 as rate_limit_v1.aleo/unpause.future;

finalize unpause:
    input r0 as address.public;
    get owner_rate_limit[true] into r1;
    assert.eq r1 r0;
    get pause_status[true] into r2;
    assert.eq r2 true;
    set false into pause_status[true];

function set_rate_limit:
    input r0 as field.private;
    input r1 as u128.private;
    input r2 as u128.private;
    gt r1 0u128 into r3;
    assert.eq r3 true;
    async set_rate_limit r0 r1 r2 self.caller into r4;
    output r4 as rate_limit_v1.aleo/set_rate_limit.future;

finalize set_rate_limit:
    input r0 as field.public;
    input r1 as u128.public;
    input r2 as u128.public;
    input r3 as address.public;
    get owner_rate_limit[true] into r4;
    assert.eq r4 r3;
    cast 0u128 0i64 0u128 0u128 into r5 as RateLimitConfig;
    get.or_use token_config[r0] r5 into r6;
    sub block.timestamp r6.last_updated into r7;
    cast r7 into r8 as u128;
    mul r8 r6.rate_per_second into r9;
    add r6.available r9 into r10;
    lt r6.max_available r10 into r11;
    ternary r11 r6.max_available r10 into r12;
    is.eq r6.rate_per_second 0u128 into r13;
    ternary r13 r2 r12 into r14;
    cast r1 block.timestamp r14 r2 into r15 as RateLimitConfig;
    set r15 into token_config[r0];

function reset_rate_limit:
    input r0 as field.private;
    async reset_rate_limit r0 self.caller into r1;
    output r1 as rate_limit_v1.aleo/reset_rate_limit.future;

finalize reset_rate_limit:
    input r0 as field.public;
    input r1 as address.public;
    get owner_rate_limit[true] into r2;
    assert.eq r2 r1;
    get token_config[r0] into r3;
    cast r3.rate_per_second block.timestamp r3.max_available r3.max_available into r4 as RateLimitConfig;
    set r4 into token_config[r0];

function verify_withdraw:
    input r0 as field.private;
    input r1 as u128.private;
    async verify_withdraw r0 r1 self.caller into r2;
    output r2 as rate_limit_v1.aleo/verify_withdraw.future;

finalize verify_withdraw:
    input r0 as field.public;
    input r1 as u128.public;
    input r2 as address.public;
    get asset_manager_core[true] into r3;
    assert.eq r3 r2;
    get pause_status[true] into r4;
    not r4 into r5;
    assert.eq r5 true;
    cast 0u128 0i64 0u128 0u128 into r6 as RateLimitConfig;
    get.or_use token_config[r0] r6 into r7;
    sub block.timestamp r7.last_updated into r8;
    cast r8 into r9 as u128;
    mul r9 r7.rate_per_second into r10;
    add r7.available r10 into r11;
    lt r7.max_available r11 into r12;
    ternary r12 r7.max_available r11 into r13;
    is.neq r7.rate_per_second 0u128 into r14;
    branch.eq r14 false to end_then_0_0;
    gte r13 r1 into r15;
    assert.eq r15 true;
    sub r13 r1 into r16;
    cast r7.rate_per_second block.timestamp r16 r7.max_available into r17 as RateLimitConfig;
    set r17 into token_config[r0];
    branch.eq true true to end_otherwise_0_1;
    position end_then_0_0;
    position end_otherwise_0_1;

function transfer_ownership:
    input r0 as address.public;
    assert.neq r0 aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;
    async transfer_ownership self.caller r0 into r1;
    output r1 as rate_limit_v1.aleo/transfer_ownership.future;

finalize transfer_ownership:
    input r0 as address.public;
    input r1 as address.public;
    get owner_rate_limit[true] into r2;
    assert.eq r2 r0;
    set r1 into owner_rate_limit[true];

constructor:
    branch.eq edition 0u16 to end;
    get gmp_checksum_v1.aleo/approved_checksums[aleo12kjuwutk9ykkl8hmxkqxdj7l7htpzq827qa95v06wk3c2h086y8sdtadvn] into r0;
    assert.eq checksum r0;
    position end;
