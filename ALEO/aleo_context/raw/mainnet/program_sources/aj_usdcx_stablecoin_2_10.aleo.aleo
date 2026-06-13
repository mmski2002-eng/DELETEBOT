import merkle_tree.aleo;
import usdcx_multisig_core.aleo;
import usdcx_freezelist.aleo;
import usdcx_stablecoin.aleo;

program aj_usdcx_stablecoin_2_10.aleo;

struct MerkleProof:
    siblings as [field; 16u32];
    leaf_index as u32;

struct WalletEcdsaSigner:
    wallet_id as address;
    ecdsa_signer as [u8; 20u32];

struct AdminOp:
    op as u8;
    threshold as u8;
    aleo_signer as address;
    ecdsa_signer as [u8; 20u32];

function join_2:
    input r0 as usdcx_stablecoin.aleo/Token.record;
    input r1 as usdcx_stablecoin.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    call usdcx_stablecoin.aleo/join r0 r1 into r2;
    output r2 as usdcx_stablecoin.aleo/Token.record;

function join_3:
    input r0 as usdcx_stablecoin.aleo/Token.record;
    input r1 as usdcx_stablecoin.aleo/Token.record;
    input r2 as usdcx_stablecoin.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    call usdcx_stablecoin.aleo/join r0 r1 into r3;
    call usdcx_stablecoin.aleo/join r3 r2 into r4;
    output r4 as usdcx_stablecoin.aleo/Token.record;

function join_4:
    input r0 as usdcx_stablecoin.aleo/Token.record;
    input r1 as usdcx_stablecoin.aleo/Token.record;
    input r2 as usdcx_stablecoin.aleo/Token.record;
    input r3 as usdcx_stablecoin.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    call usdcx_stablecoin.aleo/join r0 r1 into r4;
    call usdcx_stablecoin.aleo/join r2 r3 into r5;
    call usdcx_stablecoin.aleo/join r4 r5 into r6;
    output r6 as usdcx_stablecoin.aleo/Token.record;

function join_5:
    input r0 as usdcx_stablecoin.aleo/Token.record;
    input r1 as usdcx_stablecoin.aleo/Token.record;
    input r2 as usdcx_stablecoin.aleo/Token.record;
    input r3 as usdcx_stablecoin.aleo/Token.record;
    input r4 as usdcx_stablecoin.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    call usdcx_stablecoin.aleo/join r0 r1 into r5;
    call usdcx_stablecoin.aleo/join r2 r3 into r6;
    call usdcx_stablecoin.aleo/join r5 r6 into r7;
    call usdcx_stablecoin.aleo/join r7 r4 into r8;
    output r8 as usdcx_stablecoin.aleo/Token.record;

function join_6:
    input r0 as usdcx_stablecoin.aleo/Token.record;
    input r1 as usdcx_stablecoin.aleo/Token.record;
    input r2 as usdcx_stablecoin.aleo/Token.record;
    input r3 as usdcx_stablecoin.aleo/Token.record;
    input r4 as usdcx_stablecoin.aleo/Token.record;
    input r5 as usdcx_stablecoin.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    call usdcx_stablecoin.aleo/join r0 r1 into r6;
    call usdcx_stablecoin.aleo/join r2 r3 into r7;
    call usdcx_stablecoin.aleo/join r4 r5 into r8;
    call usdcx_stablecoin.aleo/join r6 r7 into r9;
    call usdcx_stablecoin.aleo/join r9 r8 into r10;
    output r10 as usdcx_stablecoin.aleo/Token.record;

function join_7:
    input r0 as usdcx_stablecoin.aleo/Token.record;
    input r1 as usdcx_stablecoin.aleo/Token.record;
    input r2 as usdcx_stablecoin.aleo/Token.record;
    input r3 as usdcx_stablecoin.aleo/Token.record;
    input r4 as usdcx_stablecoin.aleo/Token.record;
    input r5 as usdcx_stablecoin.aleo/Token.record;
    input r6 as usdcx_stablecoin.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    assert.eq r0.owner r6.owner;
    call usdcx_stablecoin.aleo/join r0 r1 into r7;
    call usdcx_stablecoin.aleo/join r2 r3 into r8;
    call usdcx_stablecoin.aleo/join r4 r5 into r9;
    call usdcx_stablecoin.aleo/join r7 r8 into r10;
    call usdcx_stablecoin.aleo/join r9 r6 into r11;
    call usdcx_stablecoin.aleo/join r10 r11 into r12;
    output r12 as usdcx_stablecoin.aleo/Token.record;

function join_8:
    input r0 as usdcx_stablecoin.aleo/Token.record;
    input r1 as usdcx_stablecoin.aleo/Token.record;
    input r2 as usdcx_stablecoin.aleo/Token.record;
    input r3 as usdcx_stablecoin.aleo/Token.record;
    input r4 as usdcx_stablecoin.aleo/Token.record;
    input r5 as usdcx_stablecoin.aleo/Token.record;
    input r6 as usdcx_stablecoin.aleo/Token.record;
    input r7 as usdcx_stablecoin.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    assert.eq r0.owner r6.owner;
    assert.eq r0.owner r7.owner;
    call usdcx_stablecoin.aleo/join r0 r1 into r8;
    call usdcx_stablecoin.aleo/join r2 r3 into r9;
    call usdcx_stablecoin.aleo/join r4 r5 into r10;
    call usdcx_stablecoin.aleo/join r6 r7 into r11;
    call usdcx_stablecoin.aleo/join r8 r9 into r12;
    call usdcx_stablecoin.aleo/join r10 r11 into r13;
    call usdcx_stablecoin.aleo/join r12 r13 into r14;
    output r14 as usdcx_stablecoin.aleo/Token.record;

function join_9:
    input r0 as usdcx_stablecoin.aleo/Token.record;
    input r1 as usdcx_stablecoin.aleo/Token.record;
    input r2 as usdcx_stablecoin.aleo/Token.record;
    input r3 as usdcx_stablecoin.aleo/Token.record;
    input r4 as usdcx_stablecoin.aleo/Token.record;
    input r5 as usdcx_stablecoin.aleo/Token.record;
    input r6 as usdcx_stablecoin.aleo/Token.record;
    input r7 as usdcx_stablecoin.aleo/Token.record;
    input r8 as usdcx_stablecoin.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    assert.eq r0.owner r6.owner;
    assert.eq r0.owner r7.owner;
    assert.eq r0.owner r8.owner;
    call usdcx_stablecoin.aleo/join r0 r1 into r9;
    call usdcx_stablecoin.aleo/join r2 r3 into r10;
    call usdcx_stablecoin.aleo/join r4 r5 into r11;
    call usdcx_stablecoin.aleo/join r6 r7 into r12;
    call usdcx_stablecoin.aleo/join r9 r10 into r13;
    call usdcx_stablecoin.aleo/join r11 r12 into r14;
    call usdcx_stablecoin.aleo/join r13 r14 into r15;
    call usdcx_stablecoin.aleo/join r15 r8 into r16;
    output r16 as usdcx_stablecoin.aleo/Token.record;

function join_10:
    input r0 as usdcx_stablecoin.aleo/Token.record;
    input r1 as usdcx_stablecoin.aleo/Token.record;
    input r2 as usdcx_stablecoin.aleo/Token.record;
    input r3 as usdcx_stablecoin.aleo/Token.record;
    input r4 as usdcx_stablecoin.aleo/Token.record;
    input r5 as usdcx_stablecoin.aleo/Token.record;
    input r6 as usdcx_stablecoin.aleo/Token.record;
    input r7 as usdcx_stablecoin.aleo/Token.record;
    input r8 as usdcx_stablecoin.aleo/Token.record;
    input r9 as usdcx_stablecoin.aleo/Token.record;
    assert.eq r0.owner r1.owner;
    assert.eq r0.owner r2.owner;
    assert.eq r0.owner r3.owner;
    assert.eq r0.owner r4.owner;
    assert.eq r0.owner r5.owner;
    assert.eq r0.owner r6.owner;
    assert.eq r0.owner r7.owner;
    assert.eq r0.owner r8.owner;
    assert.eq r0.owner r9.owner;
    call usdcx_stablecoin.aleo/join r0 r1 into r10;
    call usdcx_stablecoin.aleo/join r2 r3 into r11;
    call usdcx_stablecoin.aleo/join r4 r5 into r12;
    call usdcx_stablecoin.aleo/join r6 r7 into r13;
    call usdcx_stablecoin.aleo/join r10 r11 into r14;
    call usdcx_stablecoin.aleo/join r12 r13 into r15;
    call usdcx_stablecoin.aleo/join r14 r15 into r16;
    call usdcx_stablecoin.aleo/join r16 r8 into r17;
    call usdcx_stablecoin.aleo/join r17 r9 into r18;
    output r18 as usdcx_stablecoin.aleo/Token.record;

constructor:
    assert.eq edition 0u16;
