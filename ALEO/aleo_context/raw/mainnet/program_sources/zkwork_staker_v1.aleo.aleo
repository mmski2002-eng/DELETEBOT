import credits.aleo;
import zkwork_staking.aleo;
import withdrawaler.aleo;

program zkwork_staker_v1.aleo;

struct bond_state:
    validator as address;
    microcredits as u64;

struct unbond_state:
    microcredits as u64;
    height as u32;

struct Settings:
    unstake_wait as u32;
    stake_paused as boolean;
    global_paused as boolean;
    max_reward_per_notify as u64;
    protocol_fee as u16;
    fee_account as address;
    fixed_stakers as boolean;

struct WithdrawalerState:
    total_pushed as u64;

struct StakerState:
    total_pulled as u64;
    total_reward as u64;

mapping state:
    key as boolean.public;
    value as StakerState.public;

function bond:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as u64.public;
    assert.eq r2 r1;
    call zkwork_staking.aleo/pull_aleo r2 into r3;
    call credits.aleo/bond_public r0 withdrawaler.aleo r1 into r4;
    async bond self.caller r2 r3 r4 into r5;
    output r5 as zkwork_staker_v1.aleo/bond.future;

finalize bond:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as zkwork_staking.aleo/pull_aleo.future;
    input r3 as credits.aleo/bond_public.future;
    await r2;
    await r3;
    get.or_use withdrawaler.aleo/operators[r0] false into r4;
    assert.eq r4 true;
    get state[true] into r5;
    add r5.total_pulled r1 into r6;
    cast r6 r5.total_reward into r7 as StakerState;
    set r7 into state[true];

function notify_reward:
    input r0 as u64.public;
    call zkwork_staking.aleo/notify_reward r0 into r1;
    async notify_reward self.caller r0 r1 into r2;
    output r2 as zkwork_staker_v1.aleo/notify_reward.future;

finalize notify_reward:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as zkwork_staking.aleo/notify_reward.future;
    await r2;
    get.or_use withdrawaler.aleo/operators[r0] false into r3;
    assert.eq r3 true;
    get.or_use credits.aleo/account[withdrawaler.aleo] 0u64 into r4;
    get withdrawaler.aleo/state[true] into r5;
    cast aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc 0u64 into r6 as bond_state;
    get.or_use credits.aleo/bonded[zkwork_staker_v1.aleo] r6 into r7;
    cast 0u64 0u32 into r8 as unbond_state;
    get.or_use credits.aleo/unbonding[zkwork_staker_v1.aleo] r8 into r9;
    get state[true] into r10;
    add r4 r7.microcredits into r11;
    add r11 r9.microcredits into r12;
    add r12 r5.total_pushed into r13;
    sub r13 r10.total_pulled into r14;
    sub r14 r10.total_reward into r15;
    lte r1 r15 into r16;
    assert.eq r16 true;
    add r10.total_reward r1 into r17;
    cast r10.total_pulled r17 into r18 as StakerState;
    set r18 into state[true];

function withdraw_puzzle:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as u64.public;
    call credits.aleo/transfer_public r0 r2 into r4;
    call credits.aleo/bond_public r1 withdrawaler.aleo r3 into r5;
    async withdraw_puzzle self.caller r0 r4 r5 into r6;
    output r6 as zkwork_staker_v1.aleo/withdraw_puzzle.future;

finalize withdraw_puzzle:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as credits.aleo/transfer_public.future;
    input r3 as credits.aleo/bond_public.future;
    await r2;
    await r3;
    get.or_use withdrawaler.aleo/operators[r0] false into r4;
    assert.eq r4 true;
    get.or_use withdrawaler.aleo/miners[r1] false into r5;
    assert.eq r5 true;

function init:
    assert.eq self.caller aleo1rjv05jexvu7r2gh945g70dxj35vdjuv6xvrdsamy3jd7ykx89cqqeag7up;
    async init into r0;
    output r0 as zkwork_staker_v1.aleo/init.future;

finalize init:
    get.or_use withdrawaler.aleo/admins[aleo1rjv05jexvu7r2gh945g70dxj35vdjuv6xvrdsamy3jd7ykx89cqqeag7up] false into r0;
    assert.eq r0 false;
    cast 0u64 0u64 into r1 as StakerState;
    set r1 into state[true];

constructor:
    assert.eq edition 0u16;
