import credits.aleo;
import lsp_host_bank_v1.aleo;

program lsp_host_ui_v1.aleo;

record PendingOwner:
    owner as address.private;
    pre as address.private;

struct PoolState:
    request_bond as u64;
    request_unbond as u64;
    total_unbond as u64;
    suspend as boolean;

struct ReleaseRequest:
    recipient as address;
    amount as u64;
    issued as boolean;

mapping owned:
    key as boolean.public;
    value as address.public;

mapping pool:
    key as address.public;
    value as PoolState.public;

mapping authority:
    key as address.public;
    value as boolean.public;

mapping release_list:
    key as [u128; 2u32].public;
    value as ReleaseRequest.public;

function initialize:
    cast self.signer aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r0 as PendingOwner.record;
    async initialize self.signer into r1;
    output r0 as PendingOwner.record;
    output r1 as lsp_host_ui_v1.aleo/initialize.future;

finalize initialize:
    input r0 as address.public;
    contains owned[true] into r1;
    assert.eq r1 false;
    assert.eq r0 aleo1pp82mhkmtpf3aw3ztup2pecav4knv3qp9hspjz0nsxhuf5pe5v8sup3rz7;
    set r0 into owned[true];

function transfer_ownership:
    input r0 as PendingOwner.record;
    input r1 as address.public;
    assert.eq r0.pre aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;
    cast r1 self.caller into r2 as PendingOwner.record;
    async transfer_ownership self.caller into r3;
    output r2 as PendingOwner.record;
    output r3 as lsp_host_ui_v1.aleo/transfer_ownership.future;

finalize transfer_ownership:
    input r0 as address.public;
    get owned[true] into r1;
    assert.eq r0 r1;

function accept_ownership:
    input r0 as PendingOwner.record;
    assert.neq r0.pre aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;
    cast r0.owner aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r1 as PendingOwner.record;
    async accept_ownership r0.pre r0.owner into r2;
    output r1 as PendingOwner.record;
    output r2 as lsp_host_ui_v1.aleo/accept_ownership.future;

finalize accept_ownership:
    input r0 as address.public;
    input r1 as address.public;
    get owned[true] into r2;
    assert.eq r0 r2;
    set r1 into owned[true];

function init_pool:
    async init_pool self.caller into r0;
    output r0 as lsp_host_ui_v1.aleo/init_pool.future;

finalize init_pool:
    input r0 as address.public;
    contains pool[r0] into r1;
    not r1 into r2;
    assert.eq r2 true;
    cast 0u64 0u64 0u64 false into r3 as PoolState;
    set r3 into pool[r0];

function deposit:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public_as_signer r0 r1 into r2;
    async deposit r0 r1 r2 into r3;
    output r3 as lsp_host_ui_v1.aleo/deposit.future;

finalize deposit:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as credits.aleo/transfer_public_as_signer.future;
    get pool[r0] into r3;
    assert.eq r3.suspend false;
    add r3.request_bond r1 into r4;
    cast r4 r3.request_unbond r3.total_unbond r3.suspend into r5 as PoolState;
    set r5 into pool[r0];
    await r2;

function release:
    input r0 as [u128; 2u32].public;
    input r1 as address.public;
    input r2 as address.public;
    input r3 as u64.public;
    async release self.signer r0 r1 r2 r3 into r4;
    output r4 as lsp_host_ui_v1.aleo/release.future;

finalize release:
    input r0 as address.public;
    input r1 as [u128; 2u32].public;
    input r2 as address.public;
    input r3 as address.public;
    input r4 as u64.public;
    get authority[r0] into r5;
    assert.eq r5 true;
    contains release_list[r1] into r6;
    not r6 into r7;
    assert.eq r7 true;
    cast r3 r4 false into r8 as ReleaseRequest;
    set r8 into release_list[r1];
    get pool[r2] into r9;
    assert.eq r9.suspend false;
    add r9.request_unbond r4 into r10;
    cast r9.request_bond r10 r9.total_unbond r9.suspend into r11 as PoolState;
    set r11 into pool[r2];

function complete_release:
    input r0 as [u128; 2u32].private;
    input r1 as address.private;
    input r2 as address.private;
    input r3 as u64.private;
    call lsp_host_bank_v1.aleo/withdraw r2 r3 into r4;
    async complete_release r0 r1 r2 r3 r4 into r5;
    output r5 as lsp_host_ui_v1.aleo/complete_release.future;

finalize complete_release:
    input r0 as [u128; 2u32].public;
    input r1 as address.public;
    input r2 as address.public;
    input r3 as u64.public;
    input r4 as lsp_host_bank_v1.aleo/withdraw.future;
    get release_list[r0] into r5;
    assert.eq r5.issued false;
    assert.eq r5.recipient r2;
    assert.eq r5.amount r3;
    cast r5.recipient r5.amount true into r6 as ReleaseRequest;
    set r6 into release_list[r0];
    get pool[r1] into r7;
    assert.eq r7.suspend false;
    gte r7.total_unbond r3 into r8;
    assert.eq r8 true;
    sub r7.total_unbond r3 into r9;
    cast r7.request_bond r7.request_unbond r9 r7.suspend into r10 as PoolState;
    set r10 into pool[r1];
    await r4;

function set_authority:
    input r0 as address.private;
    input r1 as boolean.private;
    async set_authority self.caller r0 r1 into r2;
    output r2 as lsp_host_ui_v1.aleo/set_authority.future;

finalize set_authority:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as boolean.public;
    get owned[true] into r3;
    assert.eq r0 r3;
    set r2 into authority[r1];

function pool_control:
    input r0 as address.private;
    input r1 as boolean.private;
    async pool_control self.caller r0 r1 into r2;
    output r2 as lsp_host_ui_v1.aleo/pool_control.future;

finalize pool_control:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as boolean.public;
    get owned[true] into r3;
    assert.eq r0 r3;
    get pool[r1] into r4;
    cast r4.request_bond r4.request_unbond r4.total_unbond r2 into r5 as PoolState;
    set r5 into pool[r1];

function report_bond:
    input r0 as u64.public;
    async report_bond self.caller r0 into r1;
    output r1 as lsp_host_ui_v1.aleo/report_bond.future;

finalize report_bond:
    input r0 as address.public;
    input r1 as u64.public;
    get pool[r0] into r2;
    gte r2.request_bond r1 into r3;
    assert.eq r3 true;
    sub r2.request_bond r1 into r4;
    cast r4 r2.request_unbond r2.total_unbond r2.suspend into r5 as PoolState;
    set r5 into pool[r0];

function report_unbond:
    input r0 as u64.public;
    async report_unbond self.caller r0 into r1;
    output r1 as lsp_host_ui_v1.aleo/report_unbond.future;

finalize report_unbond:
    input r0 as address.public;
    input r1 as u64.public;
    get pool[r0] into r2;
    gte r2.request_unbond r1 into r3;
    assert.eq r3 true;
    sub r2.request_unbond r1 into r4;
    cast r2.request_bond r4 r2.total_unbond r2.suspend into r5 as PoolState;
    set r5 into pool[r0];

function report_total_unbond:
    input r0 as u64.public;
    async report_total_unbond self.caller r0 into r1;
    output r1 as lsp_host_ui_v1.aleo/report_total_unbond.future;

finalize report_total_unbond:
    input r0 as address.public;
    input r1 as u64.public;
    get pool[r0] into r2;
    add r2.total_unbond r1 into r3;
    cast r2.request_bond r2.request_unbond r3 r2.suspend into r4 as PoolState;
    set r4 into pool[r0];
