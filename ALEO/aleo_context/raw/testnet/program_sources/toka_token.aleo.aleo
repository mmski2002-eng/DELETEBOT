program toka_token.aleo;

record Token:
    owner as address.private;
    amount as u128.private;

struct Allowance:
    account as address;
    spender as address;

mapping balances:
    key as address.public;
    value as u128.public;

mapping approvals:
    key as field.public;
    value as u128.public;

function approve_public:
    input r0 as address.private;
    input r1 as u128.private;
    cast self.signer r0 into r2 as Allowance;
    hash.bhp256 r2 into r3 as field;
    async approve_public r1 r3 into r4;
    output r4 as toka_token.aleo/approve_public.future;

finalize approve_public:
    input r0 as u128.public;
    input r1 as field.public;
    get.or_use approvals[r1] 0u128 into r2;
    add r2 r0 into r3;
    set r3 into approvals[r1];

function unapprove_public:
    input r0 as address.private;
    input r1 as u128.private;
    cast self.signer r0 into r2 as Allowance;
    hash.bhp256 r2 into r3 as field;
    async unapprove_public r1 r3 into r4;
    output r4 as toka_token.aleo/unapprove_public.future;

finalize unapprove_public:
    input r0 as u128.public;
    input r1 as field.public;
    get approvals[r1] into r2;
    sub r2 r0 into r3;
    set r3 into approvals[r1];

function transfer_from_public:
    input r0 as address.private;
    input r1 as address.private;
    input r2 as u128.private;
    cast r0 self.caller into r3 as Allowance;
    hash.bhp256 r3 into r4 as field;
    async transfer_from_public r0 r1 r2 r4 into r5;
    output r5 as toka_token.aleo/transfer_from_public.future;

finalize transfer_from_public:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u128.public;
    input r3 as field.public;
    get approvals[r3] into r4;
    sub r4 r2 into r5;
    set r5 into approvals[r3];
    get.or_use balances[r0] 0u128 into r6;
    gte r6 r2 into r7;
    assert.eq r7 true;
    sub r6 r2 into r8;
    set r8 into balances[r0];
    get.or_use balances[r1] 0u128 into r9;
    add r9 r2 into r10;
    set r10 into balances[r1];

function transfer_public_as_signer:
    input r0 as address.private;
    input r1 as u128.private;
    async transfer_public_as_signer self.signer r0 r1 into r2;
    output r2 as toka_token.aleo/transfer_public_as_signer.future;

finalize transfer_public_as_signer:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u128.public;
    get.or_use balances[r0] 0u128 into r3;
    gte r3 r2 into r4;
    assert.eq r4 true;
    sub r3 r2 into r5;
    set r5 into balances[r0];
    get.or_use balances[r1] 0u128 into r6;
    add r6 r2 into r7;
    set r7 into balances[r1];

function transfer_public:
    input r0 as address.private;
    input r1 as u128.private;
    async transfer_public self.caller r0 r1 into r2;
    output r2 as toka_token.aleo/transfer_public.future;

finalize transfer_public:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u128.public;
    get.or_use balances[r0] 0u128 into r3;
    gte r3 r2 into r4;
    assert.eq r4 true;
    sub r3 r2 into r5;
    set r5 into balances[r0];
    get.or_use balances[r1] 0u128 into r6;
    add r6 r2 into r7;
    set r7 into balances[r1];

function transfer_private_to_public:
    input r0 as address.private;
    input r1 as u128.private;
    input r2 as Token.record;
    sub r2.amount r1 into r3;
    cast r2.owner r3 into r4 as Token.record;
    async transfer_private_to_public r0 r1 into r5;
    output r4 as Token.record;
    output r5 as toka_token.aleo/transfer_private_to_public.future;

finalize transfer_private_to_public:
    input r0 as address.public;
    input r1 as u128.public;
    get.or_use balances[r0] 0u128 into r2;
    add r2 r1 into r3;
    set r3 into balances[r0];

function transfer_public_to_private:
    input r0 as address.private;
    input r1 as u128.private;
    cast r0 r1 into r2 as Token.record;
    async transfer_public_to_private self.caller r1 into r3;
    output r2 as Token.record;
    output r3 as toka_token.aleo/transfer_public_to_private.future;

finalize transfer_public_to_private:
    input r0 as address.public;
    input r1 as u128.public;
    get.or_use balances[r0] 0u128 into r2;
    gte r2 r1 into r3;
    assert.eq r3 true;
    sub r2 r1 into r4;
    set r4 into balances[r0];

function mint_public:
    input r0 as address.public;
    input r1 as u128.public;
    async mint_public r0 r1 into r2;
    output r2 as toka_token.aleo/mint_public.future;

finalize mint_public:
    input r0 as address.public;
    input r1 as u128.public;
    get.or_use balances[r0] 0u128 into r2;
    add r2 r1 into r3;
    set r3 into balances[r0];

constructor:
    assert.eq edition 0u16;
