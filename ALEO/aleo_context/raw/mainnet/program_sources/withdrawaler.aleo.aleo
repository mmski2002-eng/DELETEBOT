import credits.aleo;
import zkwork_staking.aleo;

program withdrawaler.aleo;

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

mapping admins:
    key as address.public;
    value as boolean.public;

mapping operators:
    key as address.public;
    value as boolean.public;

mapping miners:
    key as address.public;
    value as boolean.public;

mapping state:
    key as boolean.public;
    value as WithdrawalerState.public;

function unbond:
    input r0 as address.public;
    input r1 as u64.public;
    assert.neq r1 0u64;
    call credits.aleo/unbond_public r0 r1 into r2;
    async unbond self.caller r2 into r3;
    output r3 as withdrawaler.aleo/unbond.future;

finalize unbond:
    input r0 as address.public;
    input r1 as credits.aleo/unbond_public.future;
    await r1;
    get operators[r0] into r2;
    assert.eq r2 true;

function claim:
    input r0 as address.public;
    call credits.aleo/claim_unbond_public r0 into r1;
    async claim self.caller r0 r1 into r2;
    output r2 as withdrawaler.aleo/claim.future;

finalize claim:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as credits.aleo/claim_unbond_public.future;
    await r2;
    get operators[r0] into r3;
    assert.eq r3 true;

function push_aleo:
    input r0 as u64.public;
    assert.neq r0 0u64;
    call credits.aleo/transfer_public zkwork_staking.aleo r0 into r1;
    async push_aleo self.caller r0 r1 into r2;
    output r2 as withdrawaler.aleo/push_aleo.future;

finalize push_aleo:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as credits.aleo/transfer_public.future;
    await r2;
    get operators[r0] into r3;
    assert.eq r3 true;
    get state[true] into r4;
    add r4.total_pushed r1 into r5;
    cast r5 into r6 as WithdrawalerState;
    set r6 into state[true];

function claim_and_push:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/claim_unbond_public r0 into r2;
    call credits.aleo/transfer_public zkwork_staking.aleo r1 into r3;
    async claim_and_push self.caller r0 r1 r2 r3 into r4;
    output r4 as withdrawaler.aleo/claim_and_push.future;

finalize claim_and_push:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as credits.aleo/claim_unbond_public.future;
    input r4 as credits.aleo/transfer_public.future;
    await r3;
    await r4;
    get operators[r0] into r5;
    assert.eq r5 true;
    get state[true] into r6;
    add r6.total_pushed r2 into r7;
    cast r7 into r8 as WithdrawalerState;
    set r8 into state[true];

function set_operator:
    input r0 as address.public;
    input r1 as boolean.public;
    async set_operator self.caller r0 r1 into r2;
    output r2 as withdrawaler.aleo/set_operator.future;

finalize set_operator:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as boolean.public;
    get admins[r0] into r3;
    assert.eq r3 true;
    set r2 into operators[r1];

function set_admin:
    input r0 as address.public;
    input r1 as boolean.public;
    assert.neq self.caller r0;
    async set_admin self.caller r0 r1 into r2;
    output r2 as withdrawaler.aleo/set_admin.future;

finalize set_admin:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as boolean.public;
    get admins[r0] into r3;
    assert.eq r3 true;
    set r2 into admins[r1];

function set_miner:
    input r0 as address.public;
    input r1 as boolean.public;
    async set_miner self.caller r0 r1 into r2;
    output r2 as withdrawaler.aleo/set_miner.future;

finalize set_miner:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as boolean.public;
    get admins[r0] into r3;
    assert.eq r3 true;
    set r2 into miners[r1];

function init:
    assert.eq self.caller aleo1rjv05jexvu7r2gh945g70dxj35vdjuv6xvrdsamy3jd7ykx89cqqeag7up;
    async init into r0;
    output r0 as withdrawaler.aleo/init.future;

finalize init:
    contains admins[aleo1rjv05jexvu7r2gh945g70dxj35vdjuv6xvrdsamy3jd7ykx89cqqeag7up] into r0;
    assert.eq r0 false;
    set true into admins[aleo1rjv05jexvu7r2gh945g70dxj35vdjuv6xvrdsamy3jd7ykx89cqqeag7up];
    set true into operators[aleo1rjv05jexvu7r2gh945g70dxj35vdjuv6xvrdsamy3jd7ykx89cqqeag7up];
    set true into miners[aleo1rjv05jexvu7r2gh945g70dxj35vdjuv6xvrdsamy3jd7ykx89cqqeag7up];
    cast 0u64 into r1 as WithdrawalerState;
    set r1 into state[true];

constructor:
    assert.eq edition 0u16;
