import credits.aleo;

program lsp_host_bank_v1.aleo;

record PendingOwner:
    owner as address.private;
    pre as address.private;

mapping owned:
    key as boolean.public;
    value as address.public;

mapping withdrawal:
    key as boolean.public;
    value as address.public;

function unbond_public:
    input r0 as u64.public;
    call credits.aleo/unbond_public self.caller r0 into r1;
    async unbond_public self.caller r1 into r2;
    output r2 as lsp_host_bank_v1.aleo/unbond_public.future;

finalize unbond_public:
    input r0 as address.public;
    input r1 as credits.aleo/unbond_public.future;
    await r1;

function transfer_public:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public r0 r1 into r2;
    async transfer_public self.caller r2 into r3;
    output r3 as lsp_host_bank_v1.aleo/transfer_public.future;

finalize transfer_public:
    input r0 as address.public;
    input r1 as credits.aleo/transfer_public.future;
    get owned[true] into r2;
    assert.eq r2 r0;
    await r1;

function initialize:
    cast self.signer aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r0 as PendingOwner.record;
    async initialize self.signer into r1;
    output r0 as PendingOwner.record;
    output r1 as lsp_host_bank_v1.aleo/initialize.future;

finalize initialize:
    input r0 as address.public;
    contains owned[true] into r1;
    assert.eq r1 false;
    assert.eq r0 aleo1pp82mhkmtpf3aw3ztup2pecav4knv3qp9hspjz0nsxhuf5pe5v8sup3rz7;
    set r0 into owned[true];

function withdraw:
    input r0 as address.private;
    input r1 as u64.private;
    call credits.aleo/transfer_public r0 r1 into r2;
    async withdraw self.caller r2 into r3;
    output r3 as lsp_host_bank_v1.aleo/withdraw.future;

finalize withdraw:
    input r0 as address.public;
    input r1 as credits.aleo/transfer_public.future;
    get withdrawal[true] into r2;
    assert.eq r2 r0;
    await r1;

function set_withdrawal:
    input r0 as address.private;
    async set_withdrawal self.caller r0 into r1;
    output r1 as lsp_host_bank_v1.aleo/set_withdrawal.future;

finalize set_withdrawal:
    input r0 as address.public;
    input r1 as address.public;
    get owned[true] into r2;
    assert.eq r0 r2;
    set r1 into withdrawal[true];

function transfer_ownership:
    input r0 as PendingOwner.record;
    input r1 as address.public;
    assert.eq r0.pre aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;
    cast r1 self.caller into r2 as PendingOwner.record;
    async transfer_ownership self.caller into r3;
    output r2 as PendingOwner.record;
    output r3 as lsp_host_bank_v1.aleo/transfer_ownership.future;

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
    output r2 as lsp_host_bank_v1.aleo/accept_ownership.future;

finalize accept_ownership:
    input r0 as address.public;
    input r1 as address.public;
    get owned[true] into r2;
    assert.eq r0 r2;
    set r1 into owned[true];
