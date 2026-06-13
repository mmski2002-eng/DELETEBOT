program phantom_mint.aleo;

record phantom_token:
    owner as address.private;
    amount as u64.private;

function mint:
    input r0 as dynamic.record;
    cast self.signer 1u64 into r1 as phantom_token.record;
    output r1 as phantom_token.record;

constructor:
    assert.eq true true;
