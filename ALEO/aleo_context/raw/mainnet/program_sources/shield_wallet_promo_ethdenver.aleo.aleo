import credits.aleo;

program shield_wallet_promo_ethdenver.aleo;

mapping spent:
    key as signature.public;
    value as boolean.public;

function redeem:
    input r0 as signature.public;
    sign.verify r0 aleo1er4a9urj2ndl9flusphut3t3j23k8z6drhxgy8f0gpv0r0phucgqzq3dwj 0field into r1;
    assert.eq r1 true;
    call credits.aleo/transfer_public_to_private self.signer 50000000u64 into r2 r3;
    async redeem r0 r3 into r4;
    output r2 as credits.aleo/credits.record;
    output r4 as shield_wallet_promo_ethdenver.aleo/redeem.future;

finalize redeem:
    input r0 as signature.public;
    input r1 as credits.aleo/transfer_public_to_private.future;
    contains spent[r0] into r2;
    not r2 into r3;
    assert.eq r3 true;
    await r1;
    set true into spent[r0];

function fund:
    input r0 as u64.private;
    assert.eq self.signer aleo1er4a9urj2ndl9flusphut3t3j23k8z6drhxgy8f0gpv0r0phucgqzq3dwj;
    call credits.aleo/transfer_public_as_signer shield_wallet_promo_ethdenver.aleo r0 into r1;
    async fund r1 into r2;
    output r2 as shield_wallet_promo_ethdenver.aleo/fund.future;

finalize fund:
    input r0 as credits.aleo/transfer_public_as_signer.future;
    await r0;

function refund:
    input r0 as u64.private;
    assert.eq self.signer aleo1er4a9urj2ndl9flusphut3t3j23k8z6drhxgy8f0gpv0r0phucgqzq3dwj;
    call credits.aleo/transfer_public aleo1er4a9urj2ndl9flusphut3t3j23k8z6drhxgy8f0gpv0r0phucgqzq3dwj r0 into r1;
    async refund r1 into r2;
    output r2 as shield_wallet_promo_ethdenver.aleo/refund.future;

finalize refund:
    input r0 as credits.aleo/transfer_public.future;
    await r0;

constructor:
    assert.eq program_owner aleo1er4a9urj2ndl9flusphut3t3j23k8z6drhxgy8f0gpv0r0phucgqzq3dwj;
