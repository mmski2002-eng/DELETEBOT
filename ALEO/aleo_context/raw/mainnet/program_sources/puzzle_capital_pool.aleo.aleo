import puzzle_capital_multisig.aleo;
import credits.aleo;

program puzzle_capital_pool.aleo;

record PayoutReceipt:
    owner as address.private;
    epoch as u64.private;
    reward as u64.private;
    deposit_snapshot as u64.private;
    commitment as field.private;

struct ChecksumEdition:
    checksum as [u8; 32u32];
    edition as u16;

struct WalletSigningOpId:
    wallet_id as field;
    signing_op_id as field;

struct PoolConfig:
    fee_bps as u64;
    paused as boolean;
    wallet_id as field;

struct PendingWithdrawal:
    amount as u64;
    unbond_block as u32;

struct ChangeFeeAction:
    new_fee_bps as u64;

struct ChangeValidatorAction:
    new_validator as address;

struct PauseAction:
    pause as boolean;

struct UpdateRoleAction:
    target as address;
    role as u16;

struct ChangeMaxRewardAction:
    new_max_reward_bps as u64;

struct EpochDepositorKey:
    epoch as u64;
    depositor as address;

mapping deposits:
    key as address.public;
    value as u64.public;

mapping total_deposited:
    key as boolean.public;
    value as u64.public;

mapping depositor_count:
    key as boolean.public;
    value as u64.public;

mapping deposit_block:
    key as address.public;
    value as u32.public;

mapping current_epoch:
    key as boolean.public;
    value as u64.public;

mapping epoch_commitments:
    key as u64.public;
    value as field.public;

mapping epoch_total_rewards:
    key as u64.public;
    value as u64.public;

mapping epoch_fee_taken:
    key as u64.public;
    value as u64.public;

mapping epoch_restaked:
    key as u64.public;
    value as u64.public;

mapping epoch_start_block:
    key as u64.public;
    value as u32.public;

mapping epoch_payout_count:
    key as u64.public;
    value as u64.public;

mapping committed_depositor_count:
    key as u64.public;
    value as u64.public;

mapping bonded_snapshot:
    key as boolean.public;
    value as u64.public;

mapping epoch_net_deposits:
    key as boolean.public;
    value as u64.public;

mapping epoch_net_withdrawals:
    key as boolean.public;
    value as u64.public;

mapping epoch_settling:
    key as boolean.public;
    value as boolean.public;

mapping last_epoch_block:
    key as boolean.public;
    value as u32.public;

mapping auto_restake:
    key as address.public;
    value as boolean.public;

mapping claimable:
    key as address.public;
    value as u64.public;

mapping is_depositor:
    key as address.public;
    value as boolean.public;

mapping pending_withdrawals:
    key as address.public;
    value as PendingWithdrawal.public;

mapping withdrawal_credits:
    key as address.public;
    value as u64.public;

mapping epoch_depositor_paid:
    key as field.public;
    value as boolean.public;

mapping pool_config:
    key as boolean.public;
    value as PoolConfig.public;

mapping validator_address:
    key as boolean.public;
    value as address.public;

mapping treasury:
    key as boolean.public;
    value as address.public;

mapping backup_address:
    key as boolean.public;
    value as address.public;

mapping address_to_role:
    key as address.public;
    value as u16.public;

mapping initialized:
    key as boolean.public;
    value as boolean.public;

mapping max_reward_bps:
    key as boolean.public;
    value as u64.public;

mapping skipped_depositors:
    key as u64.public;
    value as u64.public;

function initialize:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as address.public;
    input r3 as u64.public;
    input r4 as field.public;
    input r5 as address.public;
    input r6 as address.public;
    input r7 as address.public;
    async initialize self.caller r3 r4 r0 r1 r2 r5 r6 r7 into r8;
    output r8 as puzzle_capital_pool.aleo/initialize.future;

finalize initialize:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as field.public;
    input r3 as address.public;
    input r4 as address.public;
    input r5 as address.public;
    input r6 as address.public;
    input r7 as address.public;
    input r8 as address.public;
    get.or_use initialized[true] false into r9;
    not r9 into r10;
    assert.eq r10 true;
    assert.eq r0 aleo1mg4r3ewxj029qd5nuxcz4qvlehld48jy403dfz2x34nmx84vecgs6eyehv;
    lte r1 2000u64 into r11;
    assert.eq r11 true;
    cast r1 false r2 into r12 as PoolConfig;
    set r12 into pool_config[true];
    set r3 into validator_address[true];
    set r4 into treasury[true];
    set r5 into backup_address[true];
    set 0u64 into total_deposited[true];
    set 0u64 into depositor_count[true];
    set 0u64 into current_epoch[true];
    set false into epoch_settling[true];
    set 0u32 into last_epoch_block[true];
    set 0u64 into epoch_net_deposits[true];
    set 0u64 into epoch_net_withdrawals[true];
    set 0u64 into bonded_snapshot[true];
    set 1u16 into address_to_role[r6];
    set 2u16 into address_to_role[r7];
    set 4u16 into address_to_role[r8];
    set 1000u64 into max_reward_bps[true];
    set true into initialized[true];

function deposit:
    input r0 as u64.public;
    call credits.aleo/transfer_public puzzle_capital_pool.aleo r0 into r1;
    async deposit r1 r0 self.caller into r2;
    output r2 as puzzle_capital_pool.aleo/deposit.future;

finalize deposit:
    input r0 as credits.aleo/transfer_public.future;
    input r1 as u64.public;
    input r2 as address.public;
    await r0;
    get pool_config[true] into r3;
    not r3.paused into r4;
    assert.eq r4 true;
    get epoch_settling[true] into r5;
    not r5 into r6;
    assert.eq r6 true;
    gte r1 10000000u64 into r7;
    assert.eq r7 true;
    get.or_use deposits[r2] 0u64 into r8;
    add r8 r1 into r9;
    set r9 into deposits[r2];
    get.or_use is_depositor[r2] false into r10;
    not r10 into r11;
    branch.eq r11 false to end_then_0_0;
    set block.height into deposit_block[r2];
    set true into is_depositor[r2];
    set true into auto_restake[r2];
    get depositor_count[true] into r12;
    add r12 1u64 into r13;
    set r13 into depositor_count[true];
    branch.eq true true to end_otherwise_0_1;
    position end_then_0_0;
    position end_otherwise_0_1;
    get total_deposited[true] into r14;
    add r14 r1 into r15;
    set r15 into total_deposited[true];
    get epoch_net_deposits[true] into r16;
    add r16 r1 into r17;
    set r17 into epoch_net_deposits[true];

function deposit_v2:
    input r0 as u64.public;
    call credits.aleo/transfer_public_as_signer puzzle_capital_pool.aleo r0 into r1;
    async deposit_v2 r1 r0 self.caller into r2;
    output r2 as puzzle_capital_pool.aleo/deposit_v2.future;

finalize deposit_v2:
    input r0 as credits.aleo/transfer_public_as_signer.future;
    input r1 as u64.public;
    input r2 as address.public;
    await r0;
    get pool_config[true] into r3;
    not r3.paused into r4;
    assert.eq r4 true;
    get epoch_settling[true] into r5;
    not r5 into r6;
    assert.eq r6 true;
    gte r1 10000000u64 into r7;
    assert.eq r7 true;
    get.or_use deposits[r2] 0u64 into r8;
    add r8 r1 into r9;
    set r9 into deposits[r2];
    get.or_use is_depositor[r2] false into r10;
    get.or_use deposit_block[r2] block.height into r11;
    set r11 into deposit_block[r2];
    set true into is_depositor[r2];
    get.or_use auto_restake[r2] true into r12;
    set r12 into auto_restake[r2];
    get depositor_count[true] into r13;
    ternary r10 0u64 1u64 into r14;
    add r13 r14 into r15;
    set r15 into depositor_count[true];
    get total_deposited[true] into r16;
    add r16 r1 into r17;
    set r17 into total_deposited[true];
    get epoch_net_deposits[true] into r18;
    add r18 r1 into r19;
    set r19 into epoch_net_deposits[true];

function request_withdraw:
    input r0 as u64.public;
    call credits.aleo/unbond_public puzzle_capital_pool.aleo r0 into r1;
    async request_withdraw r1 self.caller r0 into r2;
    output r2 as puzzle_capital_pool.aleo/request_withdraw.future;

finalize request_withdraw:
    input r0 as credits.aleo/unbond_public.future;
    input r1 as address.public;
    input r2 as u64.public;
    await r0;
    get pool_config[true] into r3;
    not r3.paused into r4;
    assert.eq r4 true;
    get epoch_settling[true] into r5;
    not r5 into r6;
    assert.eq r6 true;
    get is_depositor[r1] into r7;
    assert.eq r7 true;
    get deposits[r1] into r8;
    gt r2 0u64 into r9;
    assert.eq r9 true;
    lte r2 r8 into r10;
    assert.eq r10 true;
    sub r8 r2 into r11;
    lt r11 10000000u64 into r12;
    ternary r12 r8 r2 into r13;
    is.eq r13 r8 into r14;
    branch.eq r14 false to end_then_0_2;
    set 0u64 into deposits[r1];
    set false into is_depositor[r1];
    get depositor_count[true] into r15;
    sub r15 1u64 into r16;
    set r16 into depositor_count[true];
    branch.eq true true to end_otherwise_0_3;
    position end_then_0_2;
    sub r8 r13 into r17;
    set r17 into deposits[r1];
    position end_otherwise_0_3;
    get total_deposited[true] into r18;
    sub r18 r13 into r19;
    set r19 into total_deposited[true];
    get epoch_net_withdrawals[true] into r20;
    add r20 r13 into r21;
    set r21 into epoch_net_withdrawals[true];
    cast r13 block.height into r22 as PendingWithdrawal;
    set r22 into pending_withdrawals[r1];

function complete_withdraw:
    call credits.aleo/claim_unbond_public puzzle_capital_pool.aleo into r0;
    async complete_withdraw r0 self.caller into r1;
    output r1 as puzzle_capital_pool.aleo/complete_withdraw.future;

finalize complete_withdraw:
    input r0 as credits.aleo/claim_unbond_public.future;
    input r1 as address.public;
    await r0;
    get pending_withdrawals[r1] into r2;
    gt r2.amount 0u64 into r3;
    assert.eq r3 true;
    remove pending_withdrawals[r1];
    get.or_use withdrawal_credits[r1] 0u64 into r4;
    add r4 r2.amount into r5;
    set r5 into withdrawal_credits[r1];

function set_auto_restake:
    input r0 as boolean.public;
    async set_auto_restake self.caller r0 into r1;
    output r1 as puzzle_capital_pool.aleo/set_auto_restake.future;

finalize set_auto_restake:
    input r0 as address.public;
    input r1 as boolean.public;
    get is_depositor[r0] into r2;
    assert.eq r2 true;
    set r1 into auto_restake[r0];

function commit_epoch:
    input r0 as u64.public;
    input r1 as u64.public;
    input r2 as u64.public;
    input r3 as u64.public;
    input r4 as field.public;
    async commit_epoch self.caller r0 r3 r1 r2 r4 into r5;
    output r5 as puzzle_capital_pool.aleo/commit_epoch.future;

finalize commit_epoch:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as u64.public;
    input r3 as u64.public;
    input r4 as u64.public;
    input r5 as field.public;
    get address_to_role[r0] into r6;
    and r6 1u16 into r7;
    is.eq r7 1u16 into r8;
    assert.eq r8 true;
    get pool_config[true] into r9;
    not r9.paused into r10;
    assert.eq r10 true;
    get epoch_settling[true] into r11;
    not r11 into r12;
    assert.eq r12 true;
    get current_epoch[true] into r13;
    add r13 1u64 into r14;
    assert.eq r1 r14;
    gt r13 0u64 into r15;
    branch.eq r15 false to end_then_0_4;
    get last_epoch_block[true] into r16;
    sub block.height r16 into r17;
    gte r17 86400u32 into r18;
    assert.eq r18 true;
    get epoch_payout_count[r13] into r19;
    get committed_depositor_count[r13] into r20;
    assert.eq r19 r20;
    branch.eq true true to end_otherwise_0_5;
    position end_then_0_4;
    position end_otherwise_0_5;
    get depositor_count[true] into r21;
    assert.eq r2 r21;
    gt r21 0u64 into r22;
    assert.eq r22 true;
    get max_reward_bps[true] into r23;
    get total_deposited[true] into r24;
    mul r24 r23 into r25;
    div r25 10000u64 into r26;
    lte r3 r26 into r27;
    assert.eq r27 true;
    mul r3 r9.fee_bps into r28;
    div r28 10000u64 into r29;
    add r29 1u64 into r30;
    lte r4 r30 into r31;
    assert.eq r31 true;
    set r1 into current_epoch[true];
    set r5 into epoch_commitments[r1];
    set r3 into epoch_total_rewards[r1];
    set r4 into epoch_fee_taken[r1];
    set block.height into epoch_start_block[r1];
    set 0u64 into epoch_payout_count[r1];
    set r2 into committed_depositor_count[r1];
    set true into epoch_settling[true];
    set r24 into bonded_snapshot[true];
    set 0u64 into epoch_net_deposits[true];
    set 0u64 into epoch_net_withdrawals[true];

function apply_epoch_rewards:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as u64.public;
    input r3 as u32.public;
    input r4 as address.public;
    input r5 as u64.public;
    input r6 as field.public;
    cast r0 r1 r2 r5 r6 into r7 as PayoutReceipt.record;
    cast r4 r1 r2 r5 r6 into r8 as PayoutReceipt.record;
    async apply_epoch_rewards self.caller r1 r0 r5 r6 r2 r3 into r9;
    output r7 as PayoutReceipt.record;
    output r8 as PayoutReceipt.record;
    output r9 as puzzle_capital_pool.aleo/apply_epoch_rewards.future;

finalize apply_epoch_rewards:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as address.public;
    input r3 as u64.public;
    input r4 as field.public;
    input r5 as u64.public;
    input r6 as u32.public;
    get address_to_role[r0] into r7;
    and r7 1u16 into r8;
    is.eq r8 1u16 into r9;
    assert.eq r9 true;
    get epoch_settling[true] into r10;
    assert.eq r10 true;
    get current_epoch[true] into r11;
    assert.eq r1 r11;
    cast r1 r2 into r12 as EpochDepositorKey;
    hash.bhp256 r12 into r13 as field;
    contains epoch_depositor_paid[r13] into r14;
    not r14 into r15;
    assert.eq r15 true;
    get is_depositor[r2] into r16;
    assert.eq r16 true;
    get deposits[r2] into r17;
    assert.eq r3 r17;
    get epoch_commitments[r1] into r18;
    assert.eq r4 r18;
    get epoch_total_rewards[r1] into r19;
    get epoch_fee_taken[r1] into r20;
    sub r19 r20 into r21;
    get bonded_snapshot[true] into r22;
    cast r17 into r23 as u128;
    cast r21 into r24 as u128;
    mul r23 r24 into r25;
    cast r22 into r26 as u128;
    div r25 r26 into r27;
    cast r27 into r28 as u64;
    add r28 1u64 into r29;
    lte r5 r29 into r30;
    assert.eq r30 true;
    get epoch_start_block[r1] into r31;
    get deposit_block[r2] into r32;
    gt r32 r31 into r33;
    branch.eq r33 false to end_then_0_6;
    sub block.height r32 into r34;
    lte r6 r34 into r35;
    assert.eq r35 true;
    branch.eq true true to end_otherwise_0_7;
    position end_then_0_6;
    position end_otherwise_0_7;
    get.or_use auto_restake[r2] true into r36;
    branch.eq r36 false to end_then_0_8;
    add r17 r5 into r37;
    set r37 into deposits[r2];
    get total_deposited[true] into r38;
    add r38 r5 into r39;
    set r39 into total_deposited[true];
    branch.eq true true to end_otherwise_0_9;
    position end_then_0_8;
    get.or_use claimable[r2] 0u64 into r40;
    add r40 r5 into r41;
    set r41 into claimable[r2];
    position end_otherwise_0_9;
    get epoch_payout_count[r1] into r42;
    add r42 1u64 into r43;
    set r43 into epoch_payout_count[r1];
    set true into epoch_depositor_paid[r13];

function close_epoch:
    input r0 as u64.public;
    async close_epoch self.caller r0 into r1;
    output r1 as puzzle_capital_pool.aleo/close_epoch.future;

finalize close_epoch:
    input r0 as address.public;
    input r1 as u64.public;
    get address_to_role[r0] into r2;
    and r2 1u16 into r3;
    is.eq r3 1u16 into r4;
    assert.eq r4 true;
    get current_epoch[true] into r5;
    assert.eq r1 r5;
    get epoch_payout_count[r1] into r6;
    get committed_depositor_count[r1] into r7;
    assert.eq r6 r7;
    set false into epoch_settling[true];
    set block.height into last_epoch_block[true];

function restake_epoch:
    input r0 as u64.public;
    input r1 as u64.public;
    input r2 as address.public;
    call credits.aleo/bond_public r2 puzzle_capital_pool.aleo r1 into r3;
    async restake_epoch r3 self.caller r2 r0 r1 into r4;
    output r4 as puzzle_capital_pool.aleo/restake_epoch.future;

finalize restake_epoch:
    input r0 as credits.aleo/bond_public.future;
    input r1 as address.public;
    input r2 as address.public;
    input r3 as u64.public;
    input r4 as u64.public;
    await r0;
    get address_to_role[r1] into r5;
    and r5 1u16 into r6;
    is.eq r6 1u16 into r7;
    assert.eq r7 true;
    get epoch_settling[true] into r8;
    not r8 into r9;
    assert.eq r9 true;
    get validator_address[true] into r10;
    assert.eq r2 r10;
    get current_epoch[true] into r11;
    assert.eq r3 r11;
    set r4 into epoch_restaked[r3];

function withdraw_credits:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public r0 r1 into r2;
    async withdraw_credits r2 r0 r1 into r3;
    output r3 as puzzle_capital_pool.aleo/withdraw_credits.future;

finalize withdraw_credits:
    input r0 as credits.aleo/transfer_public.future;
    input r1 as address.public;
    input r2 as u64.public;
    await r0;
    get withdrawal_credits[r1] into r3;
    gt r2 0u64 into r4;
    assert.eq r4 true;
    lte r2 r3 into r5;
    assert.eq r5 true;
    sub r3 r2 into r6;
    is.eq r6 0u64 into r7;
    branch.eq r7 false to end_then_0_10;
    remove withdrawal_credits[r1];
    branch.eq true true to end_otherwise_0_11;
    position end_then_0_10;
    set r6 into withdrawal_credits[r1];
    position end_otherwise_0_11;

function transfer_claimable:
    input r0 as address.public;
    input r1 as u64.public;
    call credits.aleo/transfer_public r0 r1 into r2;
    async transfer_claimable r2 r0 r1 into r3;
    output r3 as puzzle_capital_pool.aleo/transfer_claimable.future;

finalize transfer_claimable:
    input r0 as credits.aleo/transfer_public.future;
    input r1 as address.public;
    input r2 as u64.public;
    await r0;
    get claimable[r1] into r3;
    assert.eq r2 r3;
    set 0u64 into claimable[r1];

function emergency_unseal:
    async emergency_unseal self.caller into r0;
    output r0 as puzzle_capital_pool.aleo/emergency_unseal.future;

finalize emergency_unseal:
    input r0 as address.public;
    get address_to_role[r0] into r1;
    and r1 1u16 into r2;
    is.eq r2 1u16 into r3;
    and r1 2u16 into r4;
    is.eq r4 2u16 into r5;
    or r3 r5 into r6;
    assert.eq r6 true;
    set false into epoch_settling[true];

function force_close_epoch:
    input r0 as u64.public;
    async force_close_epoch self.caller r0 into r1;
    output r1 as puzzle_capital_pool.aleo/force_close_epoch.future;

finalize force_close_epoch:
    input r0 as address.public;
    input r1 as u64.public;
    get address_to_role[r0] into r2;
    and r2 2u16 into r3;
    is.eq r3 2u16 into r4;
    assert.eq r4 true;
    get current_epoch[true] into r5;
    assert.eq r1 r5;
    get epoch_settling[true] into r6;
    not r6 into r7;
    assert.eq r7 true;
    get epoch_payout_count[r1] into r8;
    get committed_depositor_count[r1] into r9;
    lt r8 r9 into r10;
    assert.eq r10 true;
    sub r9 r8 into r11;
    set r11 into skipped_depositors[r1];
    set r8 into committed_depositor_count[r1];
    set block.height into last_epoch_block[true];

function propose_change_fee:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u64.public;
    cast r2 into r3 as ChangeFeeAction;
    hash.bhp256 r3 into r4 as field;
    call puzzle_capital_multisig.aleo/init_signing_op r0 r1 r4 false into r5;
    async propose_change_fee r5 self.caller r2 into r6;
    output r6 as puzzle_capital_pool.aleo/propose_change_fee.future;

finalize propose_change_fee:
    input r0 as puzzle_capital_multisig.aleo/init_signing_op.future;
    input r1 as address.public;
    input r2 as u64.public;
    await r0;
    get address_to_role[r1] into r3;
    and r3 4u16 into r4;
    is.eq r4 4u16 into r5;
    assert.eq r5 true;
    lte r2 2000u64 into r6;
    assert.eq r6 true;

function propose_change_validator:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as address.public;
    cast r2 into r3 as ChangeValidatorAction;
    hash.bhp256 r3 into r4 as field;
    call puzzle_capital_multisig.aleo/init_signing_op r0 r1 r4 false into r5;
    async propose_change_validator r5 self.caller into r6;
    output r6 as puzzle_capital_pool.aleo/propose_change_validator.future;

finalize propose_change_validator:
    input r0 as puzzle_capital_multisig.aleo/init_signing_op.future;
    input r1 as address.public;
    await r0;
    get address_to_role[r1] into r2;
    and r2 4u16 into r3;
    is.eq r3 4u16 into r4;
    assert.eq r4 true;

function propose_update_role:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as address.public;
    input r3 as u16.public;
    cast r2 r3 into r4 as UpdateRoleAction;
    hash.bhp256 r4 into r5 as field;
    call puzzle_capital_multisig.aleo/init_signing_op r0 r1 r5 false into r6;
    async propose_update_role r6 self.caller into r7;
    output r7 as puzzle_capital_pool.aleo/propose_update_role.future;

finalize propose_update_role:
    input r0 as puzzle_capital_multisig.aleo/init_signing_op.future;
    input r1 as address.public;
    await r0;
    get address_to_role[r1] into r2;
    and r2 4u16 into r3;
    is.eq r3 4u16 into r4;
    assert.eq r4 true;

function propose_pause:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as boolean.public;
    cast r2 into r3 as PauseAction;
    hash.bhp256 r3 into r4 as field;
    call puzzle_capital_multisig.aleo/init_signing_op r0 r1 r4 false into r5;
    async propose_pause r5 self.caller into r6;
    output r6 as puzzle_capital_pool.aleo/propose_pause.future;

finalize propose_pause:
    input r0 as puzzle_capital_multisig.aleo/init_signing_op.future;
    input r1 as address.public;
    await r0;
    get address_to_role[r1] into r2;
    and r2 4u16 into r3;
    is.eq r3 4u16 into r4;
    and r2 2u16 into r5;
    is.eq r5 2u16 into r6;
    or r4 r6 into r7;
    assert.eq r7 true;

function propose_change_max_reward_bps:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u64.public;
    cast r2 into r3 as ChangeMaxRewardAction;
    hash.bhp256 r3 into r4 as field;
    call puzzle_capital_multisig.aleo/init_signing_op r0 r1 r4 false into r5;
    async propose_change_max_reward_bps r5 self.caller r2 into r6;
    output r6 as puzzle_capital_pool.aleo/propose_change_max_reward_bps.future;

finalize propose_change_max_reward_bps:
    input r0 as puzzle_capital_multisig.aleo/init_signing_op.future;
    input r1 as address.public;
    input r2 as u64.public;
    await r0;
    get address_to_role[r1] into r3;
    and r3 4u16 into r4;
    is.eq r4 4u16 into r5;
    assert.eq r5 true;
    gt r2 0u64 into r6;
    assert.eq r6 true;
    lte r2 5000u64 into r7;
    assert.eq r7 true;

function exec_change_fee:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u64.public;
    cast r2 into r3 as ChangeFeeAction;
    hash.bhp256 r3 into r4 as field;
    call puzzle_capital_multisig.aleo/verify_completed_op r0 r1 r4 into r5;
    call puzzle_capital_multisig.aleo/consume_signing_op r0 r1 into r6;
    async exec_change_fee r5 r6 self.caller r2 into r7;
    output r7 as puzzle_capital_pool.aleo/exec_change_fee.future;

finalize exec_change_fee:
    input r0 as puzzle_capital_multisig.aleo/verify_completed_op.future;
    input r1 as puzzle_capital_multisig.aleo/consume_signing_op.future;
    input r2 as address.public;
    input r3 as u64.public;
    await r0;
    await r1;
    get address_to_role[r2] into r4;
    and r4 4u16 into r5;
    is.eq r5 4u16 into r6;
    assert.eq r6 true;
    lte r3 2000u64 into r7;
    assert.eq r7 true;
    get pool_config[true] into r8;
    cast r3 r8.paused r8.wallet_id into r9 as PoolConfig;
    set r9 into pool_config[true];

function exec_update_role:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as address.public;
    input r3 as u16.public;
    cast r2 r3 into r4 as UpdateRoleAction;
    hash.bhp256 r4 into r5 as field;
    call puzzle_capital_multisig.aleo/verify_completed_op r0 r1 r5 into r6;
    call puzzle_capital_multisig.aleo/consume_signing_op r0 r1 into r7;
    async exec_update_role r6 r7 self.caller r2 r3 into r8;
    output r8 as puzzle_capital_pool.aleo/exec_update_role.future;

finalize exec_update_role:
    input r0 as puzzle_capital_multisig.aleo/verify_completed_op.future;
    input r1 as puzzle_capital_multisig.aleo/consume_signing_op.future;
    input r2 as address.public;
    input r3 as address.public;
    input r4 as u16.public;
    await r0;
    await r1;
    get address_to_role[r2] into r5;
    and r5 4u16 into r6;
    is.eq r6 4u16 into r7;
    assert.eq r7 true;
    set r4 into address_to_role[r3];

function exec_pause:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as boolean.public;
    cast r2 into r3 as PauseAction;
    hash.bhp256 r3 into r4 as field;
    call puzzle_capital_multisig.aleo/verify_completed_op r0 r1 r4 into r5;
    call puzzle_capital_multisig.aleo/consume_signing_op r0 r1 into r6;
    async exec_pause r5 r6 self.caller r2 into r7;
    output r7 as puzzle_capital_pool.aleo/exec_pause.future;

finalize exec_pause:
    input r0 as puzzle_capital_multisig.aleo/verify_completed_op.future;
    input r1 as puzzle_capital_multisig.aleo/consume_signing_op.future;
    input r2 as address.public;
    input r3 as boolean.public;
    await r0;
    await r1;
    get address_to_role[r2] into r4;
    and r4 2u16 into r5;
    is.eq r5 2u16 into r6;
    assert.eq r6 true;
    get pool_config[true] into r7;
    cast r7.fee_bps r3 r7.wallet_id into r8 as PoolConfig;
    set r8 into pool_config[true];

function exec_change_validator:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as address.public;
    cast r2 into r3 as ChangeValidatorAction;
    hash.bhp256 r3 into r4 as field;
    call puzzle_capital_multisig.aleo/verify_completed_op r0 r1 r4 into r5;
    call puzzle_capital_multisig.aleo/consume_signing_op r0 r1 into r6;
    async exec_change_validator r5 r6 self.caller r2 into r7;
    output r7 as puzzle_capital_pool.aleo/exec_change_validator.future;

finalize exec_change_validator:
    input r0 as puzzle_capital_multisig.aleo/verify_completed_op.future;
    input r1 as puzzle_capital_multisig.aleo/consume_signing_op.future;
    input r2 as address.public;
    input r3 as address.public;
    await r0;
    await r1;
    get address_to_role[r2] into r4;
    and r4 4u16 into r5;
    is.eq r5 4u16 into r6;
    assert.eq r6 true;
    set r3 into validator_address[true];

function exec_change_max_reward_bps:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u64.public;
    cast r2 into r3 as ChangeMaxRewardAction;
    hash.bhp256 r3 into r4 as field;
    call puzzle_capital_multisig.aleo/verify_completed_op r0 r1 r4 into r5;
    call puzzle_capital_multisig.aleo/consume_signing_op r0 r1 into r6;
    async exec_change_max_reward_bps r5 r6 self.caller r2 into r7;
    output r7 as puzzle_capital_pool.aleo/exec_change_max_reward_bps.future;

finalize exec_change_max_reward_bps:
    input r0 as puzzle_capital_multisig.aleo/verify_completed_op.future;
    input r1 as puzzle_capital_multisig.aleo/consume_signing_op.future;
    input r2 as address.public;
    input r3 as u64.public;
    await r0;
    await r1;
    get address_to_role[r2] into r4;
    and r4 4u16 into r5;
    is.eq r5 4u16 into r6;
    assert.eq r6 true;
    gt r3 0u64 into r7;
    assert.eq r7 true;
    lte r3 5000u64 into r8;
    assert.eq r8 true;
    set r3 into max_reward_bps[true];

function get_signing_op_id_for_deploy:
    input r0 as [u8; 32u32].private;
    input r1 as u16.private;
    cast r0 r1 into r2 as ChecksumEdition;
    hash.bhp256 r2 into r3 as field;
    output r3 as field.private;

constructor:
    gt edition 0u16 into r0;
    branch.eq r0 false to end_then_0_12;
    get pool_config[true] into r1;
    cast checksum edition into r2 as ChecksumEdition;
    hash.bhp256 r2 into r3 as field;
    cast r1.wallet_id r3 into r4 as WalletSigningOpId;
    hash.bhp256 r4 into r5 as field;
    contains puzzle_capital_multisig.aleo/completed_signing_ops[r5] into r6;
    assert.eq r6 true;
    branch.eq true true to end_otherwise_0_13;
    position end_then_0_12;
    position end_otherwise_0_13;
