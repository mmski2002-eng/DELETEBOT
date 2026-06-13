import credits.aleo;
import token_registry.aleo;

program autojoin_token_registry_2_9.aleo;

struct TokenMetadata:
    token_id as field;
    name as u128;
    symbol as u128;
    decimals as u8;
    supply as u128;
    max_supply as u128;
    admin as address;
    external_authorization_required as boolean;
    external_authorization_party as address;

struct TokenOwner:
    account as address;
    token_id as field;

function join_2:
    input r0 as token_registry.aleo/Token.record;
    input r1 as token_registry.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.token_id r1.token_id;
    assert.eq r0.external_authorization_required r1.external_authorization_required;
    call token_registry.aleo/join r0 r1 into r2;
    output r2 as token_registry.aleo/Token.record;

function join_3:
    input r0 as token_registry.aleo/Token.record;
    input r1 as token_registry.aleo/Token.record;
    input r2 as token_registry.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.token_id r1.token_id;
    assert.eq r0.token_id r2.token_id;
    assert.eq r0.external_authorization_required r1.external_authorization_required;
    assert.eq r0.external_authorization_required r2.external_authorization_required;
    call token_registry.aleo/join r0 r1 into r3;
    call token_registry.aleo/join r3 r2 into r4;
    output r4 as token_registry.aleo/Token.record;

function join_4:
    input r0 as token_registry.aleo/Token.record;
    input r1 as token_registry.aleo/Token.record;
    input r2 as token_registry.aleo/Token.record;
    input r3 as token_registry.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.token_id r1.token_id;
    assert.eq r0.token_id r2.token_id;
    assert.eq r0.token_id r3.token_id;
    assert.eq r0.external_authorization_required r1.external_authorization_required;
    assert.eq r0.external_authorization_required r2.external_authorization_required;
    assert.eq r0.external_authorization_required r3.external_authorization_required;
    call token_registry.aleo/join r0 r1 into r4;
    call token_registry.aleo/join r2 r3 into r5;
    call token_registry.aleo/join r4 r5 into r6;
    output r6 as token_registry.aleo/Token.record;

function join_5:
    input r0 as token_registry.aleo/Token.record;
    input r1 as token_registry.aleo/Token.record;
    input r2 as token_registry.aleo/Token.record;
    input r3 as token_registry.aleo/Token.record;
    input r4 as token_registry.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.token_id r1.token_id;
    assert.eq r0.token_id r2.token_id;
    assert.eq r0.token_id r3.token_id;
    assert.eq r0.token_id r4.token_id;
    assert.eq r0.external_authorization_required r1.external_authorization_required;
    assert.eq r0.external_authorization_required r2.external_authorization_required;
    assert.eq r0.external_authorization_required r3.external_authorization_required;
    assert.eq r0.external_authorization_required r4.external_authorization_required;
    call token_registry.aleo/join r0 r1 into r5;
    call token_registry.aleo/join r2 r3 into r6;
    call token_registry.aleo/join r5 r6 into r7;
    call token_registry.aleo/join r7 r4 into r8;
    output r8 as token_registry.aleo/Token.record;

function join_6:
    input r0 as token_registry.aleo/Token.record;
    input r1 as token_registry.aleo/Token.record;
    input r2 as token_registry.aleo/Token.record;
    input r3 as token_registry.aleo/Token.record;
    input r4 as token_registry.aleo/Token.record;
    input r5 as token_registry.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    assert.eq r0.token_id r1.token_id;
    assert.eq r0.token_id r2.token_id;
    assert.eq r0.token_id r3.token_id;
    assert.eq r0.token_id r4.token_id;
    assert.eq r0.token_id r5.token_id;
    assert.eq r0.external_authorization_required r1.external_authorization_required;
    assert.eq r0.external_authorization_required r2.external_authorization_required;
    assert.eq r0.external_authorization_required r3.external_authorization_required;
    assert.eq r0.external_authorization_required r4.external_authorization_required;
    assert.eq r0.external_authorization_required r5.external_authorization_required;
    call token_registry.aleo/join r0 r1 into r6;
    call token_registry.aleo/join r2 r3 into r7;
    call token_registry.aleo/join r4 r5 into r8;
    call token_registry.aleo/join r6 r7 into r9;
    call token_registry.aleo/join r9 r8 into r10;
    output r10 as token_registry.aleo/Token.record;

function join_7:
    input r0 as token_registry.aleo/Token.record;
    input r1 as token_registry.aleo/Token.record;
    input r2 as token_registry.aleo/Token.record;
    input r3 as token_registry.aleo/Token.record;
    input r4 as token_registry.aleo/Token.record;
    input r5 as token_registry.aleo/Token.record;
    input r6 as token_registry.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    assert.eq r0.owner r6.owner;
    assert.eq r0.token_id r1.token_id;
    assert.eq r0.token_id r2.token_id;
    assert.eq r0.token_id r3.token_id;
    assert.eq r0.token_id r4.token_id;
    assert.eq r0.token_id r5.token_id;
    assert.eq r0.token_id r6.token_id;
    assert.eq r0.external_authorization_required r1.external_authorization_required;
    assert.eq r0.external_authorization_required r2.external_authorization_required;
    assert.eq r0.external_authorization_required r3.external_authorization_required;
    assert.eq r0.external_authorization_required r4.external_authorization_required;
    assert.eq r0.external_authorization_required r5.external_authorization_required;
    assert.eq r0.external_authorization_required r6.external_authorization_required;
    call token_registry.aleo/join r0 r1 into r7;
    call token_registry.aleo/join r2 r3 into r8;
    call token_registry.aleo/join r4 r5 into r9;
    call token_registry.aleo/join r7 r8 into r10;
    call token_registry.aleo/join r9 r6 into r11;
    call token_registry.aleo/join r10 r11 into r12;
    output r12 as token_registry.aleo/Token.record;

function join_8:
    input r0 as token_registry.aleo/Token.record;
    input r1 as token_registry.aleo/Token.record;
    input r2 as token_registry.aleo/Token.record;
    input r3 as token_registry.aleo/Token.record;
    input r4 as token_registry.aleo/Token.record;
    input r5 as token_registry.aleo/Token.record;
    input r6 as token_registry.aleo/Token.record;
    input r7 as token_registry.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    assert.eq r0.owner r6.owner;
    assert.eq r0.owner r7.owner;
    assert.eq r0.token_id r1.token_id;
    assert.eq r0.token_id r2.token_id;
    assert.eq r0.token_id r3.token_id;
    assert.eq r0.token_id r4.token_id;
    assert.eq r0.token_id r5.token_id;
    assert.eq r0.token_id r6.token_id;
    assert.eq r0.token_id r7.token_id;
    assert.eq r0.external_authorization_required r1.external_authorization_required;
    assert.eq r0.external_authorization_required r2.external_authorization_required;
    assert.eq r0.external_authorization_required r3.external_authorization_required;
    assert.eq r0.external_authorization_required r4.external_authorization_required;
    assert.eq r0.external_authorization_required r5.external_authorization_required;
    assert.eq r0.external_authorization_required r6.external_authorization_required;
    assert.eq r0.external_authorization_required r7.external_authorization_required;
    call token_registry.aleo/join r0 r1 into r8;
    call token_registry.aleo/join r2 r3 into r9;
    call token_registry.aleo/join r4 r5 into r10;
    call token_registry.aleo/join r6 r7 into r11;
    call token_registry.aleo/join r8 r9 into r12;
    call token_registry.aleo/join r10 r11 into r13;
    call token_registry.aleo/join r12 r13 into r14;
    output r14 as token_registry.aleo/Token.record;

function join_9:
    input r0 as token_registry.aleo/Token.record;
    input r1 as token_registry.aleo/Token.record;
    input r2 as token_registry.aleo/Token.record;
    input r3 as token_registry.aleo/Token.record;
    input r4 as token_registry.aleo/Token.record;
    input r5 as token_registry.aleo/Token.record;
    input r6 as token_registry.aleo/Token.record;
    input r7 as token_registry.aleo/Token.record;
    input r8 as token_registry.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    assert.eq r0.owner r6.owner;
    assert.eq r0.owner r7.owner;
    assert.eq r0.owner r8.owner;
    assert.eq r0.token_id r1.token_id;
    assert.eq r0.token_id r2.token_id;
    assert.eq r0.token_id r3.token_id;
    assert.eq r0.token_id r4.token_id;
    assert.eq r0.token_id r5.token_id;
    assert.eq r0.token_id r6.token_id;
    assert.eq r0.token_id r7.token_id;
    assert.eq r0.token_id r8.token_id;
    assert.eq r0.external_authorization_required r1.external_authorization_required;
    assert.eq r0.external_authorization_required r2.external_authorization_required;
    assert.eq r0.external_authorization_required r3.external_authorization_required;
    assert.eq r0.external_authorization_required r4.external_authorization_required;
    assert.eq r0.external_authorization_required r5.external_authorization_required;
    assert.eq r0.external_authorization_required r6.external_authorization_required;
    assert.eq r0.external_authorization_required r7.external_authorization_required;
    assert.eq r0.external_authorization_required r8.external_authorization_required;
    call token_registry.aleo/join r0 r1 into r9;
    call token_registry.aleo/join r2 r3 into r10;
    call token_registry.aleo/join r4 r5 into r11;
    call token_registry.aleo/join r6 r7 into r12;
    call token_registry.aleo/join r9 r10 into r13;
    call token_registry.aleo/join r11 r12 into r14;
    call token_registry.aleo/join r13 r14 into r15;
    call token_registry.aleo/join r15 r8 into r16;
    output r16 as token_registry.aleo/Token.record;

constructor:
    assert.eq edition 0u16;
