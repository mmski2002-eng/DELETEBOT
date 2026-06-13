import credits.aleo;

program victim_vault.aleo;

function withdraw:
    input r0 as dynamic.record;
    input r1 as u64.public;
    call credits.aleo/transfer_public self.signer r1 into r2;
    async withdraw r2 into r3;
    output r3 as victim_vault.aleo/withdraw.future;

finalize withdraw:
    input r0 as credits.aleo/transfer_public.future;
    await r0;

constructor:
    assert.eq true true;
