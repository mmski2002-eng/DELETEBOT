import puzzle_capital_multisig.aleo;
import credits.aleo;

program whalepool_puzzlecapital.aleo;

record ProverPayoutReceipt:
    owner as address.private;
    epoch as u64.private;
    amount as u64.private;
    shares as u64.private;
    pool_name_hash as field.private;

struct ChecksumEdition:
    checksum as [u8; 32u32];
    edition as u16;

struct WalletSigningOpId:
    wallet_id as field;
    signing_op_id as field;

struct GlobalConfig:
    paused as boolean;
    total_provers as u64;
    whalepool_fee_bps as u64;
    puzzle_capacity_microcredits as u64;
    max_solutions_per_epoch as u64;
    wallet_id as field;

struct ProverConfig:
    payout_address as address;
    active as boolean;
    registered_block as u32;

struct ProverEpochShares:
    shares as u64;
    paid as boolean;

struct EpochSettlement:
    total_received as u64;
    total_distributed as u64;
    total_shares as u64;
    whalepool_fee_taken as u64;
    settled as boolean;
    solutions_submitted as u64;

struct ProverEpochKey:
    prover as address;
    epoch as u64;

mapping global_config:
    key as boolean.public;
    value as GlobalConfig.public;

mapping current_epoch:
    key as boolean.public;
    value as u64.public;

mapping initialized:
    key as boolean.public;
    value as boolean.public;

mapping address_to_role:
    key as address.public;
    value as u16.public;

mapping provers:
    key as address.public;
    value as ProverConfig.public;

mapping prover_epoch_shares:
    key as field.public;
    value as ProverEpochShares.public;

mapping epoch_settlements:
    key as u64.public;
    value as EpochSettlement.public;

mapping fee_pool:
    key as boolean.public;
    value as u64.public;

mapping treasury:
    key as boolean.public;
    value as address.public;

mapping epoch_solutions_submitted:
    key as u64.public;
    value as u64.public;

function initialize:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as u64.public;
    input r3 as address.public;
    input r4 as address.public;
    input r5 as field.public;
    async initialize self.caller r1 r2 r5 r0 r3 r4 into r6;
    output r6 as whalepool_puzzlecapital.aleo/initialize.future;

finalize initialize:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as u64.public;
    input r3 as field.public;
    input r4 as address.public;
    input r5 as address.public;
    input r6 as address.public;
    get.or_use initialized[true] false into r7;
    not r7 into r8;
    assert.eq r8 true;
    assert.eq r0 aleo1mg4r3ewxj029qd5nuxcz4qvlehld48jy403dfz2x34nmx84vecgs6eyehv;
    lte r1 1000u64 into r9;
    assert.eq r9 true;
    gte r2 500000000000u64 into r10;
    assert.eq r10 true;
    div r2 500000000000u64 into r11;
    cast false 0u64 r1 r2 r11 r3 into r12 as GlobalConfig;
    set r12 into global_config[true];
    set r4 into treasury[true];
    set 0u64 into fee_pool[true];
    set 0u64 into current_epoch[true];
    set 1u16 into address_to_role[r5];
    set 4u16 into address_to_role[r6];
    set true into initialized[true];

function register_prover:
    input r0 as address.public;
    input r1 as address.public;
    async register_prover self.caller r0 r1 into r2;
    output r2 as whalepool_puzzlecapital.aleo/register_prover.future;

finalize register_prover:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as address.public;
    get global_config[true] into r3;
    not r3.paused into r4;
    assert.eq r4 true;
    get address_to_role[r0] into r5;
    and r5 4u16 into r6;
    is.eq r6 4u16 into r7;
    assert.eq r7 true;
    contains provers[r1] into r8;
    not r8 into r9;
    assert.eq r9 true;
    cast r2 true block.height into r10 as ProverConfig;
    set r10 into provers[r1];
    add r3.total_provers 1u64 into r11;
    cast r3.paused r11 r3.whalepool_fee_bps r3.puzzle_capacity_microcredits r3.max_solutions_per_epoch r3.wallet_id into r12 as GlobalConfig;
    set r12 into global_config[true];

function deregister_prover:
    input r0 as address.public;
    async deregister_prover self.caller r0 into r1;
    output r1 as whalepool_puzzlecapital.aleo/deregister_prover.future;

finalize deregister_prover:
    input r0 as address.public;
    input r1 as address.public;
    get global_config[true] into r2;
    get address_to_role[r0] into r3;
    and r3 4u16 into r4;
    is.eq r4 4u16 into r5;
    assert.eq r5 true;
    get provers[r1] into r6;
    assert.eq r6.active true;
    cast r6.payout_address false r6.registered_block into r7 as ProverConfig;
    set r7 into provers[r1];
    sub r2.total_provers 1u64 into r8;
    cast r2.paused r8 r2.whalepool_fee_bps r2.puzzle_capacity_microcredits r2.max_solutions_per_epoch r2.wallet_id into r9 as GlobalConfig;
    set r9 into global_config[true];

function record_shares:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as u64.public;
    async record_shares self.caller r0 r1 r2 into r3;
    output r3 as whalepool_puzzlecapital.aleo/record_shares.future;

finalize record_shares:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as u64.public;
    get global_config[true] into r4;
    not r4.paused into r5;
    assert.eq r5 true;
    get address_to_role[r0] into r6;
    and r6 1u16 into r7;
    is.eq r7 1u16 into r8;
    assert.eq r8 true;
    get provers[r1] into r9;
    assert.eq r9.active true;
    get current_epoch[true] into r10;
    assert.eq r2 r10;
    cast r1 r2 into r11 as ProverEpochKey;
    hash.bhp256 r11 into r12 as field;
    cast 0u64 false into r13 as ProverEpochShares;
    get.or_use prover_epoch_shares[r12] r13 into r14;
    not r14.paid into r15;
    assert.eq r15 true;
    cast r3 false into r16 as ProverEpochShares;
    set r16 into prover_epoch_shares[r12];
    cast 0u64 0u64 0u64 0u64 false 0u64 into r17 as EpochSettlement;
    get.or_use epoch_settlements[r2] r17 into r18;
    is.eq r14.shares 0u64 into r19;
    sub r3 r14.shares into r20;
    ternary r19 r3 r20 into r21;
    add r18.total_shares r21 into r22;
    cast r18.total_received r18.total_distributed r22 r18.whalepool_fee_taken r18.settled r18.solutions_submitted into r23 as EpochSettlement;
    set r23 into epoch_settlements[r2];

function begin_epoch_settlement:
    input r0 as u64.public;
    input r1 as u64.public;
    input r2 as u64.public;
    input r3 as u64.public;
    async begin_epoch_settlement self.caller r1 r0 r2 r3 into r4;
    output r4 as whalepool_puzzlecapital.aleo/begin_epoch_settlement.future;

finalize begin_epoch_settlement:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as u64.public;
    input r3 as u64.public;
    input r4 as u64.public;
    get global_config[true] into r5;
    not r5.paused into r6;
    assert.eq r6 true;
    get address_to_role[r0] into r7;
    and r7 1u16 into r8;
    is.eq r8 1u16 into r9;
    assert.eq r9 true;
    gte r1 100000u64 into r10;
    assert.eq r10 true;
    cast 0u64 0u64 0u64 0u64 false 0u64 into r11 as EpochSettlement;
    get.or_use epoch_settlements[r2] r11 into r12;
    not r12.settled into r13;
    assert.eq r13 true;
    assert.eq r3 r12.total_shares;
    set r4 into epoch_solutions_submitted[r2];
    mul r1 r5.whalepool_fee_bps into r14;
    div r14 10000u64 into r15;
    cast r1 0u64 r3 r15 true r4 into r16 as EpochSettlement;
    set r16 into epoch_settlements[r2];
    get fee_pool[true] into r17;
    add r17 r15 into r18;
    set r18 into fee_pool[true];

function distribute_to_prover:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as address.public;
    input r3 as u64.public;
    call credits.aleo/transfer_public r2 r3 into r4;
    async distribute_to_prover r4 self.caller r0 r2 r3 r1 into r5;
    output r5 as whalepool_puzzlecapital.aleo/distribute_to_prover.future;

finalize distribute_to_prover:
    input r0 as credits.aleo/transfer_public.future;
    input r1 as address.public;
    input r2 as address.public;
    input r3 as address.public;
    input r4 as u64.public;
    input r5 as u64.public;
    await r0;
    get global_config[true] into r6;
    not r6.paused into r7;
    assert.eq r7 true;
    get address_to_role[r1] into r8;
    and r8 1u16 into r9;
    is.eq r9 1u16 into r10;
    assert.eq r10 true;
    get provers[r2] into r11;
    assert.eq r11.active true;
    assert.eq r3 r11.payout_address;
    gt r4 0u64 into r12;
    assert.eq r12 true;
    get epoch_settlements[r5] into r13;
    assert.eq r13.settled true;
    gt r13.total_shares 0u64 into r14;
    assert.eq r14 true;
    cast r2 r5 into r15 as ProverEpochKey;
    hash.bhp256 r15 into r16 as field;
    get prover_epoch_shares[r16] into r17;
    not r17.paid into r18;
    assert.eq r18 true;
    sub r13.total_received r13.whalepool_fee_taken into r19;
    mul r19 r17.shares into r20;
    div r20 r13.total_shares into r21;
    assert.eq r4 r21;
    cast r17.shares true into r22 as ProverEpochShares;
    set r22 into prover_epoch_shares[r16];
    add r13.total_distributed r4 into r23;
    cast r13.total_received r23 r13.total_shares r13.whalepool_fee_taken r13.settled r13.solutions_submitted into r24 as EpochSettlement;
    set r24 into epoch_settlements[r5];

function advance_epoch:
    async advance_epoch self.caller into r0;
    output r0 as whalepool_puzzlecapital.aleo/advance_epoch.future;

finalize advance_epoch:
    input r0 as address.public;
    get global_config[true] into r1;
    not r1.paused into r2;
    assert.eq r2 true;
    get address_to_role[r0] into r3;
    and r3 1u16 into r4;
    is.eq r4 1u16 into r5;
    assert.eq r5 true;
    get current_epoch[true] into r6;
    add r6 1u64 into r7;
    set r7 into current_epoch[true];

function withdraw_fees:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public r0 r1 into r2;
    async withdraw_fees r2 self.caller r0 r1 into r3;
    output r3 as whalepool_puzzlecapital.aleo/withdraw_fees.future;

finalize withdraw_fees:
    input r0 as credits.aleo/transfer_public.future;
    input r1 as address.public;
    input r2 as address.public;
    input r3 as u64.public;
    await r0;
    get global_config[true] into r4;
    not r4.paused into r5;
    assert.eq r5 true;
    get address_to_role[r1] into r6;
    and r6 1u16 into r7;
    is.eq r7 1u16 into r8;
    assert.eq r8 true;
    get treasury[true] into r9;
    assert.eq r2 r9;
    get fee_pool[true] into r10;
    lte r3 r10 into r11;
    assert.eq r11 true;
    sub r10 r3 into r12;
    set r12 into fee_pool[true];

function update_prover_payout_address:
    input r0 as address.public;
    async update_prover_payout_address self.caller r0 into r1;
    output r1 as whalepool_puzzlecapital.aleo/update_prover_payout_address.future;

finalize update_prover_payout_address:
    input r0 as address.public;
    input r1 as address.public;
    get global_config[true] into r2;
    not r2.paused into r3;
    assert.eq r3 true;
    get provers[r0] into r4;
    assert.eq r4.active true;
    cast r1 r4.active r4.registered_block into r5 as ProverConfig;
    set r5 into provers[r0];

function set_paused:
    input r0 as boolean.public;
    async set_paused self.caller r0 into r1;
    output r1 as whalepool_puzzlecapital.aleo/set_paused.future;

finalize set_paused:
    input r0 as address.public;
    input r1 as boolean.public;
    get global_config[true] into r2;
    get address_to_role[r0] into r3;
    and r3 4u16 into r4;
    is.eq r4 4u16 into r5;
    assert.eq r5 true;
    cast r1 r2.total_provers r2.whalepool_fee_bps r2.puzzle_capacity_microcredits r2.max_solutions_per_epoch r2.wallet_id into r6 as GlobalConfig;
    set r6 into global_config[true];

function update_puzzle_capacity:
    input r0 as u64.public;
    async update_puzzle_capacity self.caller r0 into r1;
    output r1 as whalepool_puzzlecapital.aleo/update_puzzle_capacity.future;

finalize update_puzzle_capacity:
    input r0 as address.public;
    input r1 as u64.public;
    get global_config[true] into r2;
    get address_to_role[r0] into r3;
    and r3 4u16 into r4;
    is.eq r4 4u16 into r5;
    assert.eq r5 true;
    gte r1 500000000000u64 into r6;
    assert.eq r6 true;
    div r1 500000000000u64 into r7;
    cast r2.paused r2.total_provers r2.whalepool_fee_bps r1 r7 r2.wallet_id into r8 as GlobalConfig;
    set r8 into global_config[true];

function update_role:
    input r0 as address.public;
    input r1 as u16.public;
    async update_role self.caller r0 r1 into r2;
    output r2 as whalepool_puzzlecapital.aleo/update_role.future;

finalize update_role:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u16.public;
    get global_config[true] into r3;
    get address_to_role[r0] into r4;
    and r4 4u16 into r5;
    is.eq r5 4u16 into r6;
    assert.eq r6 true;
    set r2 into address_to_role[r1];

constructor:
    gt edition 0u16 into r0;
    branch.eq r0 false to end_then_0_0;
    get global_config[true] into r1;
    cast checksum edition into r2 as ChecksumEdition;
    hash.bhp256 r2 into r3 as field;
    cast r1.wallet_id r3 into r4 as WalletSigningOpId;
    hash.bhp256 r4 into r5 as field;
    contains puzzle_capital_multisig.aleo/completed_signing_ops[r5] into r6;
    assert.eq r6 true;
    branch.eq true true to end_otherwise_0_1;
    position end_then_0_0;
    position end_otherwise_0_1;
