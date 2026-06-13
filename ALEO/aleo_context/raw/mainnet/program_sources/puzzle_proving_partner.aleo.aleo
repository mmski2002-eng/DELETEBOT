import puzzle_capital_multisig.aleo;
import credits.aleo;

program puzzle_proving_partner.aleo;

record PartnerConfigRecord:
    owner as address.private;
    partner_id as address.private;
    payout_address as address.private;
    name_hash as field.private;
    apr_bps as u64.private;
    fee_per_epoch as u64.private;
    capacity_microcredits as u64.private;
    max_solutions_per_epoch as u64.private;

record EpochRewardRecord:
    owner as address.private;
    partner_id as address.private;
    epoch as u64.private;
    gross_rewards as u64.private;
    solutions_submitted as u64.private;
    capped_rewards as u64.private;
    overflow_rewards as u64.private;
    overflow_solutions as u64.private;

record AuditRecord:
    owner as address.private;
    partner_id as address.private;
    epoch as u64.private;
    gross_rewards as u64.private;
    capped_rewards as u64.private;
    overflow_rewards as u64.private;
    fee_deducted as u64.private;
    net_payout as u64.private;
    solutions_submitted as u64.private;
    overflow_solutions as u64.private;
    settlement_block as u32.private;

record SettlementReceipt:
    owner as address.private;
    epoch as u64.private;
    net_payout as u64.private;

struct ChecksumEdition:
    checksum as [u8; 32u32];
    edition as u16;

struct WalletSigningOpId:
    wallet_id as field;
    signing_op_id as field;

struct GlobalConfig:
    wallet_id as field;
    paused as boolean;
    total_partners as u64;

struct PartnerEpochKey:
    partner as address;
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

mapping partner_active:
    key as address.public;
    value as boolean.public;

mapping epoch_settled:
    key as field.public;
    value as boolean.public;

mapping pending_settlements:
    key as field.public;
    value as u64.public;

mapping fee_pool:
    key as boolean.public;
    value as u64.public;

mapping treasury:
    key as boolean.public;
    value as address.public;

function initialize:
    input r0 as field.public;
    input r1 as address.public;
    input r2 as address.public;
    input r3 as address.public;
    async initialize self.caller r0 r1 r2 r3 into r4;
    output r4 as puzzle_proving_partner.aleo/initialize.future;

finalize initialize:
    input r0 as address.public;
    input r1 as field.public;
    input r2 as address.public;
    input r3 as address.public;
    input r4 as address.public;
    get.or_use initialized[true] false into r5;
    not r5 into r6;
    assert.eq r6 true;
    assert.eq r0 aleo1mg4r3ewxj029qd5nuxcz4qvlehld48jy403dfz2x34nmx84vecgs6eyehv;
    cast r1 false 0u64 into r7 as GlobalConfig;
    set r7 into global_config[true];
    set r2 into treasury[true];
    set 0u64 into current_epoch[true];
    set 0u64 into fee_pool[true];
    set 1u16 into address_to_role[r3];
    set 4u16 into address_to_role[r4];
    set true into initialized[true];

function register_partner:
    input r0 as address.public;
    input r1 as address.private;
    input r2 as field.private;
    input r3 as u64.private;
    input r4 as u64.private;
    input r5 as address.private;
    lte r3 1000u64 into r6;
    assert.eq r6 true;
    gte r4 500000000000u64 into r7;
    assert.eq r7 true;
    div r4 500000000000u64 into r8;
    mul r4 r3 into r9;
    div r9 10000u64 into r10;
    div r10 730u64 into r11;
    cast r5 r0 r1 r2 r3 r11 r4 r8 into r12 as PartnerConfigRecord.record;
    async register_partner self.caller r0 into r13;
    output r12 as PartnerConfigRecord.record;
    output r13 as puzzle_proving_partner.aleo/register_partner.future;

finalize register_partner:
    input r0 as address.public;
    input r1 as address.public;
    get global_config[true] into r2;
    not r2.paused into r3;
    assert.eq r3 true;
    get address_to_role[r0] into r4;
    and r4 4u16 into r5;
    is.eq r5 4u16 into r6;
    assert.eq r6 true;
    contains partner_active[r1] into r7;
    not r7 into r8;
    assert.eq r8 true;
    set true into partner_active[r1];
    add r2.total_partners 1u64 into r9;
    cast r2.wallet_id r2.paused r9 into r10 as GlobalConfig;
    set r10 into global_config[true];

function record_proving_rewards:
    input r0 as PartnerConfigRecord.record;
    input r1 as EpochRewardRecord.record;
    input r2 as u64.private;
    input r3 as u64.private;
    cast r0.owner r0.partner_id r0.payout_address r0.name_hash r0.apr_bps r0.fee_per_epoch r0.capacity_microcredits r0.max_solutions_per_epoch into r4 as PartnerConfigRecord.record;
    assert.eq r1.partner_id r0.partner_id;
    add r1.solutions_submitted r3 into r5;
    add r1.gross_rewards r2 into r6;
    lt r1.solutions_submitted r0.max_solutions_per_epoch into r7;
    ternary r7 r1.solutions_submitted r0.max_solutions_per_epoch into r8;
    lt r5 r0.max_solutions_per_epoch into r9;
    ternary r9 r5 r0.max_solutions_per_epoch into r10;
    sub r10 r8 into r11;
    gt r3 0u64 into r12;
    mul r2 r11 into r13;
    div r13 r3 into r14;
    ternary r12 r14 0u64 into r15;
    sub r2 r15 into r16;
    sub r3 r11 into r17;
    add r1.capped_rewards r15 into r18;
    add r1.overflow_rewards r16 into r19;
    add r1.overflow_solutions r17 into r20;
    cast r0.owner r0.partner_id r1.epoch r6 r5 r18 r19 r20 into r21 as EpochRewardRecord.record;
    async record_proving_rewards self.caller r0.partner_id into r22;
    output r4 as PartnerConfigRecord.record;
    output r21 as EpochRewardRecord.record;
    output r22 as puzzle_proving_partner.aleo/record_proving_rewards.future;

finalize record_proving_rewards:
    input r0 as address.public;
    input r1 as address.public;
    get global_config[true] into r2;
    not r2.paused into r3;
    assert.eq r3 true;
    get address_to_role[r0] into r4;
    and r4 1u16 into r5;
    is.eq r5 1u16 into r6;
    assert.eq r6 true;
    get partner_active[r1] into r7;
    assert.eq r7 true;

function create_epoch_record:
    input r0 as PartnerConfigRecord.record;
    input r1 as u64.private;
    cast r0.owner r0.partner_id r0.payout_address r0.name_hash r0.apr_bps r0.fee_per_epoch r0.capacity_microcredits r0.max_solutions_per_epoch into r2 as PartnerConfigRecord.record;
    cast r0.owner r0.partner_id r1 0u64 0u64 0u64 0u64 0u64 into r3 as EpochRewardRecord.record;
    async create_epoch_record self.caller r0.partner_id r1 into r4;
    output r2 as PartnerConfigRecord.record;
    output r3 as EpochRewardRecord.record;
    output r4 as puzzle_proving_partner.aleo/create_epoch_record.future;

finalize create_epoch_record:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u64.public;
    get global_config[true] into r3;
    not r3.paused into r4;
    assert.eq r4 true;
    get address_to_role[r0] into r5;
    and r5 1u16 into r6;
    is.eq r6 1u16 into r7;
    assert.eq r7 true;
    get partner_active[r1] into r8;
    assert.eq r8 true;
    cast r1 r2 into r9 as PartnerEpochKey;
    hash.bhp256 r9 into r10 as field;
    get.or_use epoch_settled[r10] false into r11;
    not r11 into r12;
    assert.eq r12 true;

function settle_partner_epoch:
    input r0 as PartnerConfigRecord.record;
    input r1 as EpochRewardRecord.record;
    input r2 as address.private;
    assert.eq r0.partner_id r1.partner_id;
    gte r1.capped_rewards 1000000u64 into r3;
    assert.eq r3 true;
    lt r0.fee_per_epoch r1.capped_rewards into r4;
    ternary r4 r0.fee_per_epoch r1.capped_rewards into r5;
    sub r1.capped_rewards r5 into r6;
    cast r2 r0.partner_id r1.epoch r1.gross_rewards r1.capped_rewards r1.overflow_rewards r5 r6 r1.solutions_submitted r1.overflow_solutions 0u32 into r7 as AuditRecord.record;
    cast r0.payout_address r0.partner_id r1.epoch r1.gross_rewards r1.capped_rewards r1.overflow_rewards r5 r6 r1.solutions_submitted r1.overflow_solutions 0u32 into r8 as AuditRecord.record;
    cast r0.payout_address r1.epoch r6 into r9 as SettlementReceipt.record;
    cast r0.owner r0.partner_id r0.payout_address r0.name_hash r0.apr_bps r0.fee_per_epoch r0.capacity_microcredits r0.max_solutions_per_epoch into r10 as PartnerConfigRecord.record;
    async settle_partner_epoch self.caller r0.partner_id r1.epoch r6 r5 into r11;
    output r10 as PartnerConfigRecord.record;
    output r7 as AuditRecord.record;
    output r8 as AuditRecord.record;
    output r9 as SettlementReceipt.record;
    output r11 as puzzle_proving_partner.aleo/settle_partner_epoch.future;

finalize settle_partner_epoch:
    input r0 as address.public;
    input r1 as address.public;
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
    get partner_active[r1] into r10;
    assert.eq r10 true;
    cast r1 r2 into r11 as PartnerEpochKey;
    hash.bhp256 r11 into r12 as field;
    get.or_use epoch_settled[r12] false into r13;
    not r13 into r14;
    assert.eq r14 true;
    set true into epoch_settled[r12];
    set r3 into pending_settlements[r12];
    get fee_pool[true] into r15;
    add r15 r4 into r16;
    set r16 into fee_pool[true];

function transfer_settlement:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as address.public;
    input r3 as u64.public;
    call credits.aleo/transfer_public r2 r3 into r4;
    async transfer_settlement r4 self.caller r0 r1 r3 into r5;
    output r5 as puzzle_proving_partner.aleo/transfer_settlement.future;

finalize transfer_settlement:
    input r0 as credits.aleo/transfer_public.future;
    input r1 as address.public;
    input r2 as address.public;
    input r3 as u64.public;
    input r4 as u64.public;
    await r0;
    get global_config[true] into r5;
    not r5.paused into r6;
    assert.eq r6 true;
    get address_to_role[r1] into r7;
    and r7 1u16 into r8;
    is.eq r8 1u16 into r9;
    assert.eq r9 true;
    cast r2 r3 into r10 as PartnerEpochKey;
    hash.bhp256 r10 into r11 as field;
    get pending_settlements[r11] into r12;
    assert.eq r4 r12;
    remove pending_settlements[r11];

function advance_epoch:
    async advance_epoch self.caller into r0;
    output r0 as puzzle_proving_partner.aleo/advance_epoch.future;

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
    output r3 as puzzle_proving_partner.aleo/withdraw_fees.future;

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

function update_partner_apr:
    input r0 as PartnerConfigRecord.record;
    input r1 as u64.private;
    input r2 as field.public;
    input r3 as address.private;
    lte r1 1000u64 into r4;
    assert.eq r4 true;
    mul r0.capacity_microcredits r1 into r5;
    div r5 10000u64 into r6;
    div r6 730u64 into r7;
    cast r0.owner r0.partner_id r0.payout_address r0.name_hash r1 r7 r0.capacity_microcredits r0.max_solutions_per_epoch into r8 as PartnerConfigRecord.record;
    cast r3 r0.partner_id 0u64 r0.apr_bps r1 0u64 r7 0u64 0u64 0u64 0u32 into r9 as AuditRecord.record;
    cast r0.payout_address r0.partner_id 0u64 r0.apr_bps r1 0u64 r7 0u64 0u64 0u64 0u32 into r10 as AuditRecord.record;
    async update_partner_apr self.caller r0.partner_id r2 into r11;
    output r8 as PartnerConfigRecord.record;
    output r9 as AuditRecord.record;
    output r10 as AuditRecord.record;
    output r11 as puzzle_proving_partner.aleo/update_partner_apr.future;

finalize update_partner_apr:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as field.public;
    get global_config[true] into r3;
    get address_to_role[r0] into r4;
    and r4 4u16 into r5;
    is.eq r5 4u16 into r6;
    assert.eq r6 true;
    get partner_active[r1] into r7;
    assert.eq r7 true;
    cast r3.wallet_id r2 into r8 as WalletSigningOpId;
    hash.bhp256 r8 into r9 as field;
    contains puzzle_capital_multisig.aleo/completed_signing_ops[r9] into r10;
    assert.eq r10 true;

function update_partner_capacity:
    input r0 as PartnerConfigRecord.record;
    input r1 as u64.private;
    input r2 as field.public;
    input r3 as address.private;
    gte r1 500000000000u64 into r4;
    assert.eq r4 true;
    div r1 500000000000u64 into r5;
    mul r1 r0.apr_bps into r6;
    div r6 10000u64 into r7;
    div r7 730u64 into r8;
    cast r0.owner r0.partner_id r0.payout_address r0.name_hash r0.apr_bps r8 r1 r5 into r9 as PartnerConfigRecord.record;
    cast r3 r0.partner_id 0u64 r0.capacity_microcredits r1 0u64 r8 0u64 r0.max_solutions_per_epoch r5 0u32 into r10 as AuditRecord.record;
    cast r0.payout_address r0.partner_id 0u64 r0.capacity_microcredits r1 0u64 r8 0u64 r0.max_solutions_per_epoch r5 0u32 into r11 as AuditRecord.record;
    async update_partner_capacity self.caller r0.partner_id r2 into r12;
    output r9 as PartnerConfigRecord.record;
    output r10 as AuditRecord.record;
    output r11 as AuditRecord.record;
    output r12 as puzzle_proving_partner.aleo/update_partner_capacity.future;

finalize update_partner_capacity:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as field.public;
    get global_config[true] into r3;
    get address_to_role[r0] into r4;
    and r4 4u16 into r5;
    is.eq r5 4u16 into r6;
    assert.eq r6 true;
    get partner_active[r1] into r7;
    assert.eq r7 true;
    cast r3.wallet_id r2 into r8 as WalletSigningOpId;
    hash.bhp256 r8 into r9 as field;
    contains puzzle_capital_multisig.aleo/completed_signing_ops[r9] into r10;
    assert.eq r10 true;

function update_partner_payout_address:
    input r0 as PartnerConfigRecord.record;
    input r1 as address.private;
    cast r0.owner r0.partner_id r1 r0.name_hash r0.apr_bps r0.fee_per_epoch r0.capacity_microcredits r0.max_solutions_per_epoch into r2 as PartnerConfigRecord.record;
    async update_partner_payout_address self.caller r0.partner_id into r3;
    output r2 as PartnerConfigRecord.record;
    output r3 as puzzle_proving_partner.aleo/update_partner_payout_address.future;

finalize update_partner_payout_address:
    input r0 as address.public;
    input r1 as address.public;
    get global_config[true] into r2;
    not r2.paused into r3;
    assert.eq r3 true;
    get address_to_role[r0] into r4;
    and r4 4u16 into r5;
    is.eq r5 4u16 into r6;
    assert.eq r6 true;
    get partner_active[r1] into r7;
    assert.eq r7 true;

function deactivate_partner:
    input r0 as PartnerConfigRecord.record;
    async deactivate_partner self.caller r0.partner_id into r1;
    output r1 as puzzle_proving_partner.aleo/deactivate_partner.future;

finalize deactivate_partner:
    input r0 as address.public;
    input r1 as address.public;
    get global_config[true] into r2;
    get address_to_role[r0] into r3;
    and r3 4u16 into r4;
    is.eq r4 4u16 into r5;
    assert.eq r5 true;
    get partner_active[r1] into r6;
    assert.eq r6 true;
    set false into partner_active[r1];
    sub r2.total_partners 1u64 into r7;
    cast r2.wallet_id r2.paused r7 into r8 as GlobalConfig;
    set r8 into global_config[true];

function set_paused:
    input r0 as boolean.public;
    async set_paused self.caller r0 into r1;
    output r1 as puzzle_proving_partner.aleo/set_paused.future;

finalize set_paused:
    input r0 as address.public;
    input r1 as boolean.public;
    get global_config[true] into r2;
    get address_to_role[r0] into r3;
    and r3 4u16 into r4;
    is.eq r4 4u16 into r5;
    assert.eq r5 true;
    cast r2.wallet_id r1 r2.total_partners into r6 as GlobalConfig;
    set r6 into global_config[true];

function update_role:
    input r0 as address.public;
    input r1 as u16.public;
    async update_role self.caller r0 r1 into r2;
    output r2 as puzzle_proving_partner.aleo/update_role.future;

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
