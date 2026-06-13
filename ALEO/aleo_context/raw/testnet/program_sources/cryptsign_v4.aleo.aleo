program cryptsign_v4.aleo;

function record_contract:
    input r0 as field.private;
    input r1 as field.private;
    input r2 as u8.private;
    input r3 as u64.private;
    add r0 r1 into r4;
    hash.bhp256 r4 into r5 as field;
    output r5 as field.public;

constructor:
    assert.eq edition 0u16;
