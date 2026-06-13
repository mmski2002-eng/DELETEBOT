program certchain_equity_v1.aleo;

record EquityNFT:
    owner as address.private;
    asset_id as field.private;
    cert_id as field.private;
    shares as u64.private;
    epoch_in as u32.private;

struct DividendKey:
    asset_id as field;
    epoch as u32;

struct ClaimKey:
    cert_id as field;
    epoch as u32;

struct VoteKey:
    cert_id as field;
    proposal_id as field;

mapping cert_exists:
    key as field.public;
    value as boolean.public;

mapping asset_total_shares:
    key as field.public;
    value as u64.public;

mapping asset_admin:
    key as field.public;
    value as address.public;

mapping dividend_per_share:
    key as DividendKey.public;
    value as u64.public;

mapping dividend_claimed:
    key as ClaimKey.public;
    value as boolean.public;

mapping has_voted:
    key as VoteKey.public;
    value as boolean.public;

mapping votes_yes:
    key as field.public;
    value as u64.public;

mapping votes_no:
    key as field.public;
    value as u64.public;

function register_admin:
    input r0 as field.public;
    async register_admin r0 self.caller into r1;
    output r1 as certchain_equity_v1.aleo/register_admin.future;

finalize register_admin:
    input r0 as field.public;
    input r1 as address.public;
    get.or_use asset_admin[r0] r1 into r2;
    assert.eq r2 r1;
    set r1 into asset_admin[r0];

function mint:
    input r0 as address.public;
    input r1 as field.public;
    input r2 as field.public;
    input r3 as u64.public;
    input r4 as u32.public;
    gt r3 0u64 into r5;
    assert.eq r5 true;
    cast r0 r1 r2 r3 r4 into r6 as EquityNFT.record;
    async mint r2 r1 r3 self.caller into r7;
    output r6 as EquityNFT.record;
    output r7 as certchain_equity_v1.aleo/mint.future;

finalize mint:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u64.public;
    input r3 as address.public;
    get.or_use asset_admin[r1] r3 into r4;
    assert.eq r4 r3;
    get.or_use cert_exists[r0] false into r5;
    not r5 into r6;
    assert.eq r6 true;
    set true into cert_exists[r0];
    get.or_use asset_total_shares[r1] 0u64 into r7;
    add r7 r2 into r8;
    set r8 into asset_total_shares[r1];

function split:
    input r0 as EquityNFT.record;
    input r1 as u64.public;
    input r2 as field.public;
    input r3 as address.public;
    is.eq r0.owner self.caller into r4;
    assert.eq r4 true;
    gt r1 0u64 into r5;
    assert.eq r5 true;
    lt r1 r0.shares into r6;
    assert.eq r6 true;
    is.neq r2 r0.cert_id into r7;
    assert.eq r7 true;
    sub r0.shares r1 into r8;
    cast r0.owner r0.asset_id r0.cert_id r8 r0.epoch_in into r9 as EquityNFT.record;
    cast r3 r0.asset_id r2 r1 r0.epoch_in into r10 as EquityNFT.record;
    async split r2 into r11;
    output r9 as EquityNFT.record;
    output r10 as EquityNFT.record;
    output r11 as certchain_equity_v1.aleo/split.future;

finalize split:
    input r0 as field.public;
    get.or_use cert_exists[r0] false into r1;
    not r1 into r2;
    assert.eq r2 true;
    set true into cert_exists[r0];

function transfer:
    input r0 as EquityNFT.record;
    input r1 as address.public;
    is.eq r0.owner self.caller into r2;
    assert.eq r2 true;
    cast r1 r0.asset_id r0.cert_id r0.shares r0.epoch_in into r3 as EquityNFT.record;
    output r3 as EquityNFT.record;

function declare_dividend:
    input r0 as field.public;
    input r1 as u32.public;
    input r2 as u64.public;
    gt r2 0u64 into r3;
    assert.eq r3 true;
    async declare_dividend r0 r1 r2 self.caller into r4;
    output r4 as certchain_equity_v1.aleo/declare_dividend.future;

finalize declare_dividend:
    input r0 as field.public;
    input r1 as u32.public;
    input r2 as u64.public;
    input r3 as address.public;
    get.or_use asset_admin[r0] r3 into r4;
    assert.eq r4 r3;
    cast r0 r1 into r5 as DividendKey;
    get.or_use dividend_per_share[r5] 0u64 into r6;
    assert.eq r6 0u64;
    set r2 into dividend_per_share[r5];

function claim_dividend:
    input r0 as EquityNFT.record;
    input r1 as u32.public;
    is.eq r0.owner self.caller into r2;
    assert.eq r2 true;
    lt r0.epoch_in r1 into r3;
    assert.eq r3 true;
    cast r0.owner r0.asset_id r0.cert_id r0.shares r0.epoch_in into r4 as EquityNFT.record;
    async claim_dividend r0.cert_id r1 r0.asset_id into r5;
    output r4 as EquityNFT.record;
    output r5 as certchain_equity_v1.aleo/claim_dividend.future;

finalize claim_dividend:
    input r0 as field.public;
    input r1 as u32.public;
    input r2 as field.public;
    cast r2 r1 into r3 as DividendKey;
    get.or_use dividend_per_share[r3] 0u64 into r4;
    gt r4 0u64 into r5;
    assert.eq r5 true;
    cast r0 r1 into r6 as ClaimKey;
    get.or_use dividend_claimed[r6] false into r7;
    not r7 into r8;
    assert.eq r8 true;
    set true into dividend_claimed[r6];

function vote:
    input r0 as EquityNFT.record;
    input r1 as field.public;
    input r2 as u8.public;
    is.eq r0.owner self.caller into r3;
    assert.eq r3 true;
    lte r2 2u8 into r4;
    assert.eq r4 true;
    cast r0.owner r0.asset_id r0.cert_id r0.shares r0.epoch_in into r5 as EquityNFT.record;
    async vote r0.cert_id r1 r0.shares r2 into r6;
    output r5 as EquityNFT.record;
    output r6 as certchain_equity_v1.aleo/vote.future;

finalize vote:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u64.public;
    input r3 as u8.public;
    cast r0 r1 into r4 as VoteKey;
    get.or_use has_voted[r4] false into r5;
    not r5 into r6;
    assert.eq r6 true;
    set true into has_voted[r4];
    is.eq r3 1u8 into r7;
    branch.eq r7 false to end_then_0_0;
    get.or_use votes_yes[r1] 0u64 into r8;
    add r8 r2 into r9;
    set r9 into votes_yes[r1];
    branch.eq true true to end_otherwise_0_1;
    position end_then_0_0;
    is.eq r3 0u8 into r10;
    branch.eq r10 false to end_then_1_2;
    get.or_use votes_no[r1] 0u64 into r11;
    add r11 r2 into r12;
    set r12 into votes_no[r1];
    branch.eq true true to end_otherwise_1_3;
    position end_then_1_2;
    position end_otherwise_1_3;
    position end_otherwise_0_1;

constructor:
    assert.eq edition 0u16;
