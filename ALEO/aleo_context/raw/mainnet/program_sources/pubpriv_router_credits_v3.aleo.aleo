import credits.aleo;

program pubpriv_router_credits_v3.aleo;

function transfer_pub_priv_to_pub:
    input r0 as credits.aleo/credits.record;
    input r1 as address.private;
    input r2 as u64.private;
    input r3 as u64.private;
    call credits.aleo/transfer_private_to_public r0 r1 r2 into r4 r5;
    call credits.aleo/transfer_public_as_signer r1 r3 into r6;
    async transfer_pub_priv_to_pub r5 r6 into r7;
    output r4 as credits.aleo/credits.record;
    output r7 as pubpriv_router_credits_v3.aleo/transfer_pub_priv_to_pub.future;

finalize transfer_pub_priv_to_pub:
    input r0 as credits.aleo/transfer_private_to_public.future;
    input r1 as credits.aleo/transfer_public_as_signer.future;
    await r0;
    await r1;

function transfer_pub_priv_to_priv:
    input r0 as credits.aleo/credits.record;
    input r1 as address.private;
    input r2 as u64.private;
    input r3 as u64.private;
    input r4 as address.private;
    call credits.aleo/transfer_private r0 self.caller r2 into r5 r6;
    call credits.aleo/transfer_public_as_signer r4 r3 into r7;
    call credits.aleo/transfer_public_to_private self.caller r3 into r8 r9;
    assert.eq r5.owner r8.owner;
    call credits.aleo/join r5 r8 into r10;
    add r2 r3 into r11;
    call credits.aleo/transfer_private r10 r1 r11 into r12 r13;
    async transfer_pub_priv_to_priv r7 r9 into r14;
    output r12 as credits.aleo/credits.record;
    output r6 as credits.aleo/credits.record;
    output r13 as credits.aleo/credits.record;
    output r14 as pubpriv_router_credits_v3.aleo/transfer_pub_priv_to_priv.future;

finalize transfer_pub_priv_to_priv:
    input r0 as credits.aleo/transfer_public_as_signer.future;
    input r1 as credits.aleo/transfer_public_to_private.future;
    await r0;
    await r1;

constructor:
    assert.eq edition 0u16;
