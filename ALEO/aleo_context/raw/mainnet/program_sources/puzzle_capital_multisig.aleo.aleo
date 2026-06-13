program puzzle_capital_multisig.aleo;

struct ProgramSettings:
    initialized as boolean;
    allow_upgrades as boolean;
    upgrader_address as address;

struct WalletSettings:
    threshold as u8;
    num_signers as u8;
    next_signer_index as u8;

struct WalletSigner:
    wallet_id as field;
    signer as address;

struct WalletSignerIndex:
    wallet_id as field;
    signer_index as u8;

struct WalletSigningOpId:
    wallet_id as field;
    signing_op_id as field;

struct SigningOp:
    action_hash as field;
    confirmations as u64;
    confirmation_count as u8;
    block_expiration as u32;
    is_upgrade as boolean;
    completed as boolean;

struct AdminOp:
    op_type as u8;
    wallet_id as field;
    value_u8 as u8;
    value_address as address;

mapping program_settings:
    key as u8.public;
    value as ProgramSettings.public;

mapping wallets:
    key as field.public;
    value as WalletSettings.public;

mapping signer_to_index:
    key as field.public;
    value as u8.public;

mapping index_to_signer:
    key as field.public;
    value as address.public;

mapping signing_ops:
    key as field.public;
    value as SigningOp.public;

mapping completed_signing_ops:
    key as field.public;
    value as boolean.public;

function create_wallet:
    input r0 as field.public;
    input r1 as u8.public;
    async create_wallet r0 r1 self.caller into r2;
    output r2 as puzzle_capital_multisig.aleo/create_wallet.future;

finalize create_wallet:
    input r0 as field.public;
    input r1 as u8.public;
    input r2 as address.public;
    contains wallets[r0] into r3;
    not r3 into r4;
    assert.eq r4 true;
    gte r1 1u8 into r5;
    assert.eq r5 true;
    cast r1 1u8 1u8 into r6 as WalletSettings;
    set r6 into wallets[r0];
    cast r0 r2 into r7 as WalletSigner;
    hash.bhp256 r7 into r8 as field;
    set 0u8 into signer_to_index[r8];
    cast r0 0u8 into r9 as WalletSignerIndex;
    hash.bhp256 r9 into r10 as field;
    set r2 into index_to_signer[r10];
    cast true true aleo1mg4r3ewxj029qd5nuxcz4qvlehld48jy403dfz2x34nmx84vecgs6eyehv into r11 as ProgramSettings;
    set r11 into program_settings[0u8];

function add_signer:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as address.public;
    async add_signer r0 self.caller r2 r1 into r3;
    output r3 as puzzle_capital_multisig.aleo/add_signer.future;

finalize add_signer:
    input r0 as field.public;
    input r1 as address.public;
    input r2 as address.public;
    input r3 as field.public;
    cast r0 r1 into r4 as WalletSigner;
    hash.bhp256 r4 into r5 as field;
    contains signer_to_index[r5] into r6;
    assert.eq r6 true;
    cast r0 r2 into r7 as WalletSigner;
    hash.bhp256 r7 into r8 as field;
    contains signer_to_index[r8] into r9;
    not r9 into r10;
    assert.eq r10 true;
    get wallets[r0] into r11;
    gt r11.num_signers 1u8 into r12;
    branch.eq r12 false to end_then_0_0;
    cast 2u8 r0 0u8 r2 into r13 as AdminOp;
    hash.bhp256 r13 into r14 as field;
    cast r0 r3 into r15 as WalletSigningOpId;
    hash.bhp256 r15 into r16 as field;
    contains completed_signing_ops[r16] into r17;
    assert.eq r17 true;
    get signing_ops[r16] into r18;
    assert.eq r18.action_hash r14;
    branch.eq true true to end_otherwise_0_1;
    position end_then_0_0;
    position end_otherwise_0_1;
    lt r11.num_signers 8u8 into r19;
    assert.eq r19 true;
    set r11.next_signer_index into signer_to_index[r8];
    cast r0 r11.next_signer_index into r20 as WalletSignerIndex;
    hash.bhp256 r20 into r21 as field;
    set r2 into index_to_signer[r21];
    add r11.num_signers 1u8 into r22;
    add r11.next_signer_index 1u8 into r23;
    cast r11.threshold r22 r23 into r24 as WalletSettings;
    set r24 into wallets[r0];

function init_signing_op:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as field.public;
    input r3 as boolean.public;
    async init_signing_op r0 self.caller r1 r3 r2 into r4;
    output r4 as puzzle_capital_multisig.aleo/init_signing_op.future;

finalize init_signing_op:
    input r0 as field.public;
    input r1 as address.public;
    input r2 as field.public;
    input r3 as boolean.public;
    input r4 as field.public;
    cast r0 r1 into r5 as WalletSigner;
    hash.bhp256 r5 into r6 as field;
    get signer_to_index[r6] into r7;
    cast r0 r2 into r8 as WalletSigningOpId;
    hash.bhp256 r8 into r9 as field;
    contains signing_ops[r9] into r10;
    not r10 into r11;
    assert.eq r11 true;
    ternary r3 345600u32 172800u32 into r12;
    add block.height r12 into r13;
    cast r7 into r14 as u32;
    shl 1u64 r14 into r15;
    cast r4 r15 1u8 r13 r3 false into r16 as SigningOp;
    set r16 into signing_ops[r9];

function sign:
    input r0 as field.public;
    input r1 as field.public;
    async sign r0 self.caller r1 into r2;
    output r2 as puzzle_capital_multisig.aleo/sign.future;

finalize sign:
    input r0 as field.public;
    input r1 as address.public;
    input r2 as field.public;
    cast r0 r1 into r3 as WalletSigner;
    hash.bhp256 r3 into r4 as field;
    get signer_to_index[r4] into r5;
    cast r0 r2 into r6 as WalletSigningOpId;
    hash.bhp256 r6 into r7 as field;
    get signing_ops[r7] into r8;
    not r8.completed into r9;
    assert.eq r9 true;
    cast r5 into r10 as u32;
    shl 1u64 r10 into r11;
    and r8.confirmations r11 into r12;
    is.eq r12 0u64 into r13;
    assert.eq r13 true;
    or r8.confirmations r11 into r14;
    add r8.confirmation_count 1u8 into r15;
    cast r8.action_hash r14 r15 r8.block_expiration r8.is_upgrade false into r16 as SigningOp;
    set r16 into signing_ops[r7];

function exec_signing_op:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as field.public;
    async exec_signing_op r0 r1 r2 into r3;
    output r3 as puzzle_capital_multisig.aleo/exec_signing_op.future;

finalize exec_signing_op:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as field.public;
    cast r0 r1 into r3 as WalletSigningOpId;
    hash.bhp256 r3 into r4 as field;
    get signing_ops[r4] into r5;
    not r5.completed into r6;
    assert.eq r6 true;
    assert.eq r5.action_hash r2;
    gte block.height r5.block_expiration into r7;
    assert.eq r7 true;
    add r5.block_expiration 604800u32 into r8;
    lte block.height r8 into r9;
    assert.eq r9 true;
    get wallets[r0] into r10;
    gte r5.confirmation_count r10.threshold into r11;
    assert.eq r11 true;
    cast r5.action_hash r5.confirmations r5.confirmation_count r5.block_expiration r5.is_upgrade true into r12 as SigningOp;
    set r12 into signing_ops[r4];
    set true into completed_signing_ops[r4];

function update_threshold:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as u8.public;
    async update_threshold r0 r2 r1 into r3;
    output r3 as puzzle_capital_multisig.aleo/update_threshold.future;

finalize update_threshold:
    input r0 as field.public;
    input r1 as u8.public;
    input r2 as field.public;
    cast 1u8 r0 r1 aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc into r3 as AdminOp;
    hash.bhp256 r3 into r4 as field;
    cast r0 r2 into r5 as WalletSigningOpId;
    hash.bhp256 r5 into r6 as field;
    contains completed_signing_ops[r6] into r7;
    assert.eq r7 true;
    get signing_ops[r6] into r8;
    assert.eq r8.action_hash r4;
    get wallets[r0] into r9;
    gte r1 1u8 into r10;
    assert.eq r10 true;
    lte r1 r9.num_signers into r11;
    assert.eq r11 true;
    cast r1 r9.num_signers r9.next_signer_index into r12 as WalletSettings;
    set r12 into wallets[r0];
    remove completed_signing_ops[r6];

function remove_signer:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as address.public;
    async remove_signer r0 r2 r1 into r3;
    output r3 as puzzle_capital_multisig.aleo/remove_signer.future;

finalize remove_signer:
    input r0 as field.public;
    input r1 as address.public;
    input r2 as field.public;
    cast 3u8 r0 0u8 r1 into r3 as AdminOp;
    hash.bhp256 r3 into r4 as field;
    cast r0 r2 into r5 as WalletSigningOpId;
    hash.bhp256 r5 into r6 as field;
    contains completed_signing_ops[r6] into r7;
    assert.eq r7 true;
    get signing_ops[r6] into r8;
    assert.eq r8.action_hash r4;
    cast r0 r1 into r9 as WalletSigner;
    hash.bhp256 r9 into r10 as field;
    contains signer_to_index[r10] into r11;
    assert.eq r11 true;
    get wallets[r0] into r12;
    sub r12.num_signers 1u8 into r13;
    gte r13 r12.threshold into r14;
    assert.eq r14 true;
    remove signer_to_index[r10];
    sub r12.num_signers 1u8 into r15;
    cast r12.threshold r15 r12.next_signer_index into r16 as WalletSettings;
    set r16 into wallets[r0];
    remove completed_signing_ops[r6];

function verify_completed_op:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as field.public;
    async verify_completed_op r0 r1 r2 into r3;
    output r3 as puzzle_capital_multisig.aleo/verify_completed_op.future;

finalize verify_completed_op:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as field.public;
    cast r0 r1 into r3 as WalletSigningOpId;
    hash.bhp256 r3 into r4 as field;
    contains completed_signing_ops[r4] into r5;
    assert.eq r5 true;
    get signing_ops[r4] into r6;
    assert.eq r6.action_hash r2;

function consume_signing_op:
    input r0 as field.public;
    input r1 as field.public;
    async consume_signing_op r0 r1 into r2;
    output r2 as puzzle_capital_multisig.aleo/consume_signing_op.future;

finalize consume_signing_op:
    input r0 as field.public;
    input r1 as field.public;
    cast r0 r1 into r2 as WalletSigningOpId;
    hash.bhp256 r2 into r3 as field;
    contains completed_signing_ops[r3] into r4;
    assert.eq r4 true;
    remove completed_signing_ops[r3];

function get_signing_op_hash:
    input r0 as field.public;
    input r1 as field.public;
    cast r0 r1 into r2 as WalletSigningOpId;
    hash.bhp256 r2 into r3 as field;
    output r3 as field.private;

function emergency_exec_signing_op:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as field.public;
    async emergency_exec_signing_op self.caller r0 r1 r2 into r3;
    output r3 as puzzle_capital_multisig.aleo/emergency_exec_signing_op.future;

finalize emergency_exec_signing_op:
    input r0 as address.public;
    input r1 as field.public;
    input r2 as field.public;
    input r3 as field.public;
    assert.eq r0 aleo1mg4r3ewxj029qd5nuxcz4qvlehld48jy403dfz2x34nmx84vecgs6eyehv;
    cast r1 r2 into r4 as WalletSigningOpId;
    hash.bhp256 r4 into r5 as field;
    get signing_ops[r5] into r6;
    not r6.completed into r7;
    assert.eq r7 true;
    assert.eq r6.action_hash r3;
    get wallets[r1] into r8;
    gte r6.confirmation_count r8.threshold into r9;
    assert.eq r9 true;
    cast r6.action_hash r6.confirmations r6.confirmation_count r6.block_expiration r6.is_upgrade true into r10 as SigningOp;
    set r10 into signing_ops[r5];
    set true into completed_signing_ops[r5];

function disallow_upgrades:
    async disallow_upgrades self.caller into r0;
    output r0 as puzzle_capital_multisig.aleo/disallow_upgrades.future;

finalize disallow_upgrades:
    input r0 as address.public;
    get program_settings[0u8] into r1;
    assert.eq r0 r1.upgrader_address;
    cast r1.initialized false r1.upgrader_address into r2 as ProgramSettings;
    set r2 into program_settings[0u8];

function set_upgrader_address:
    input r0 as address.public;
    async set_upgrader_address self.caller r0 into r1;
    output r1 as puzzle_capital_multisig.aleo/set_upgrader_address.future;

finalize set_upgrader_address:
    input r0 as address.public;
    input r1 as address.public;
    get program_settings[0u8] into r2;
    assert.eq r0 r2.upgrader_address;
    cast r2.initialized r2.allow_upgrades r1 into r3 as ProgramSettings;
    set r3 into program_settings[0u8];

constructor:
    is.eq edition 0u16 into r0;
    branch.eq r0 false to end_then_0_2;
    assert.eq program_owner aleo1mg4r3ewxj029qd5nuxcz4qvlehld48jy403dfz2x34nmx84vecgs6eyehv;
    branch.eq true true to end_otherwise_0_3;
    position end_then_0_2;
    contains program_settings[0u8] into r1;
    assert.eq r1 true;
    get program_settings[0u8] into r2;
    assert.eq r2.allow_upgrades true;
    assert.eq program_owner r2.upgrader_address;
    position end_otherwise_0_3;
