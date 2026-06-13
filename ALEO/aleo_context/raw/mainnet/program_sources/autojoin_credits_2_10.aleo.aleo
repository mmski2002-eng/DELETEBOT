import credits.aleo;

program autojoin_credits_2_10.aleo;

function join_2:
    input r0 as credits.aleo/credits.record;
    input r1 as credits.aleo/credits.record;
    assert.eq r0.owner r1.owner;
    call credits.aleo/join r0 r1 into r2;
    output r2 as credits.aleo/credits.record;

function join_3:
    input r0 as credits.aleo/credits.record;
    input r1 as credits.aleo/credits.record;
    input r2 as credits.aleo/credits.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    call credits.aleo/join r0 r1 into r3;
    call credits.aleo/join r3 r2 into r4;
    output r4 as credits.aleo/credits.record;

function join_4:
    input r0 as credits.aleo/credits.record;
    input r1 as credits.aleo/credits.record;
    input r2 as credits.aleo/credits.record;
    input r3 as credits.aleo/credits.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    call credits.aleo/join r0 r1 into r4;
    call credits.aleo/join r2 r3 into r5;
    call credits.aleo/join r4 r5 into r6;
    output r6 as credits.aleo/credits.record;

function join_5:
    input r0 as credits.aleo/credits.record;
    input r1 as credits.aleo/credits.record;
    input r2 as credits.aleo/credits.record;
    input r3 as credits.aleo/credits.record;
    input r4 as credits.aleo/credits.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    call credits.aleo/join r0 r1 into r5;
    call credits.aleo/join r2 r3 into r6;
    call credits.aleo/join r5 r6 into r7;
    call credits.aleo/join r7 r4 into r8;
    output r8 as credits.aleo/credits.record;

function join_6:
    input r0 as credits.aleo/credits.record;
    input r1 as credits.aleo/credits.record;
    input r2 as credits.aleo/credits.record;
    input r3 as credits.aleo/credits.record;
    input r4 as credits.aleo/credits.record;
    input r5 as credits.aleo/credits.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    call credits.aleo/join r0 r1 into r6;
    call credits.aleo/join r2 r3 into r7;
    call credits.aleo/join r4 r5 into r8;
    call credits.aleo/join r6 r7 into r9;
    call credits.aleo/join r9 r8 into r10;
    output r10 as credits.aleo/credits.record;

function join_7:
    input r0 as credits.aleo/credits.record;
    input r1 as credits.aleo/credits.record;
    input r2 as credits.aleo/credits.record;
    input r3 as credits.aleo/credits.record;
    input r4 as credits.aleo/credits.record;
    input r5 as credits.aleo/credits.record;
    input r6 as credits.aleo/credits.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    assert.eq r0.owner r6.owner;
    call credits.aleo/join r0 r1 into r7;
    call credits.aleo/join r2 r3 into r8;
    call credits.aleo/join r4 r5 into r9;
    call credits.aleo/join r7 r8 into r10;
    call credits.aleo/join r9 r6 into r11;
    call credits.aleo/join r10 r11 into r12;
    output r12 as credits.aleo/credits.record;

function join_8:
    input r0 as credits.aleo/credits.record;
    input r1 as credits.aleo/credits.record;
    input r2 as credits.aleo/credits.record;
    input r3 as credits.aleo/credits.record;
    input r4 as credits.aleo/credits.record;
    input r5 as credits.aleo/credits.record;
    input r6 as credits.aleo/credits.record;
    input r7 as credits.aleo/credits.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    assert.eq r0.owner r6.owner;
    assert.eq r0.owner r7.owner;
    call credits.aleo/join r0 r1 into r8;
    call credits.aleo/join r2 r3 into r9;
    call credits.aleo/join r4 r5 into r10;
    call credits.aleo/join r6 r7 into r11;
    call credits.aleo/join r8 r9 into r12;
    call credits.aleo/join r10 r11 into r13;
    call credits.aleo/join r12 r13 into r14;
    output r14 as credits.aleo/credits.record;

function join_9:
    input r0 as credits.aleo/credits.record;
    input r1 as credits.aleo/credits.record;
    input r2 as credits.aleo/credits.record;
    input r3 as credits.aleo/credits.record;
    input r4 as credits.aleo/credits.record;
    input r5 as credits.aleo/credits.record;
    input r6 as credits.aleo/credits.record;
    input r7 as credits.aleo/credits.record;
    input r8 as credits.aleo/credits.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    assert.eq r0.owner r6.owner;
    assert.eq r0.owner r7.owner;
    assert.eq r0.owner r8.owner;
    call credits.aleo/join r0 r1 into r9;
    call credits.aleo/join r2 r3 into r10;
    call credits.aleo/join r4 r5 into r11;
    call credits.aleo/join r6 r7 into r12;
    call credits.aleo/join r9 r10 into r13;
    call credits.aleo/join r11 r12 into r14;
    call credits.aleo/join r13 r14 into r15;
    call credits.aleo/join r15 r8 into r16;
    output r16 as credits.aleo/credits.record;

function join_10:
    input r0 as credits.aleo/credits.record;
    input r1 as credits.aleo/credits.record;
    input r2 as credits.aleo/credits.record;
    input r3 as credits.aleo/credits.record;
    input r4 as credits.aleo/credits.record;
    input r5 as credits.aleo/credits.record;
    input r6 as credits.aleo/credits.record;
    input r7 as credits.aleo/credits.record;
    input r8 as credits.aleo/credits.record;
    input r9 as credits.aleo/credits.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    assert.eq r0.owner r6.owner;
    assert.eq r0.owner r7.owner;
    assert.eq r0.owner r8.owner;
    assert.eq r0.owner r9.owner;
    call credits.aleo/join r0 r1 into r10;
    call credits.aleo/join r2 r3 into r11;
    call credits.aleo/join r4 r5 into r12;
    call credits.aleo/join r6 r7 into r13;
    call credits.aleo/join r8 r9 into r14;
    call credits.aleo/join r10 r11 into r15;
    call credits.aleo/join r12 r13 into r16;
    call credits.aleo/join r15 r16 into r17;
    call credits.aleo/join r17 r14 into r18;
    output r18 as credits.aleo/credits.record;

constructor:
    assert.eq edition 0u16;
