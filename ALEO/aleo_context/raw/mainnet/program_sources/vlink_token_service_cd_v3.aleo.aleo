import credits.aleo;
import vlink_holding_cd_v3.aleo;
import vlink_token_bridge_v3.aleo;

program vlink_token_service_cd_v3.aleo;

struct Holder:
    account as address;
    token_id as field;

struct AleoProgram:
    chain_id as u128;
    addr as address;

struct ForeignContract:
    chain_id as u128;
    addr as [u8; 32u32];

struct OutTokenMessage:
    sender_address as address;
    dest_token_address as [u8; 32u32];
    amount as u128;
    receiver_address as [u8; 32u32];

struct InTokenMessage:
    sender_address as [u8; 32u32];
    dest_token_id as field;
    amount as u128;
    receiver_address as address;

struct ChainToken:
    chain_id as u128;
    token_id as field;

mapping owner_TS:
    key as boolean.public;
    value as address.public;

mapping total_supply:
    key as ChainToken.public;
    value as u64.public;

mapping min_transfers:
    key as ChainToken.public;
    value as u64.public;

mapping max_transfers:
    key as ChainToken.public;
    value as u64.public;

mapping status:
    key as ChainToken.public;
    value as boolean.public;

mapping token_holding:
    key as field.public;
    value as u64.public;

mapping other_chain_token_service:
    key as ChainToken.public;
    value as [u8; 32u32].public;

mapping other_chain_token_address:
    key as ChainToken.public;
    value as [u8; 32u32].public;

mapping platform_fee:
    key as ChainToken.public;
    value as u32.public;

function initialize_ts:
    input r0 as address.public;
    assert.eq self.caller aleo1svc4tz09l9ll6nh8mh5jrcas5ce57jwa4cw97nef25vjnghe0szqjn54s0;
    async initialize_ts r0 self.caller into r1;
    output r1 as vlink_token_service_cd_v3.aleo/initialize_ts.future;

finalize initialize_ts:
    input r0 as address.public;
    input r1 as address.public;
    contains owner_TS[true] into r2;
    not r2 into r3;
    assert.eq r3 true;
    set r0 into owner_TS[true];

function transfer_ownership_ts:
    input r0 as address.public;
    assert.neq r0 aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;
    async transfer_ownership_ts self.caller r0 into r1;
    output r1 as vlink_token_service_cd_v3.aleo/transfer_ownership_ts.future;

finalize transfer_ownership_ts:
    input r0 as address.public;
    input r1 as address.public;
    get owner_TS[true] into r2;
    assert.eq r0 r2;
    set r1 into owner_TS[true];

function update_other_chain_tokenservice:
    input r0 as u128.public;
    input r1 as [u8; 20u32].public;
    async update_other_chain_tokenservice self.caller r0 r1 into r2;
    output r2 as vlink_token_service_cd_v3.aleo/update_other_chain_tokenservice.future;

finalize update_other_chain_tokenservice:
    input r0 as address.public;
    input r1 as u128.public;
    input r2 as [u8; 20u32].public;
    get owner_TS[true] into r3;
    assert.eq r0 r3;
    cast r1 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r4 as ChainToken;
    contains other_chain_token_service[r4] into r5;
    assert.eq r5 true;
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r2[0u32] r2[1u32] r2[2u32] r2[3u32] r2[4u32] r2[5u32] r2[6u32] r2[7u32] r2[8u32] r2[9u32] r2[10u32] r2[11u32] r2[12u32] r2[13u32] r2[14u32] r2[15u32] r2[16u32] r2[17u32] r2[18u32] r2[19u32] into r6 as [u8; 32u32];
    set r6 into other_chain_token_service[r4];

function update_other_chain_tokenaddress:
    input r0 as u128.public;
    input r1 as [u8; 20u32].public;
    async update_other_chain_tokenaddress self.caller r0 r1 into r2;
    output r2 as vlink_token_service_cd_v3.aleo/update_other_chain_tokenaddress.future;

finalize update_other_chain_tokenaddress:
    input r0 as address.public;
    input r1 as u128.public;
    input r2 as [u8; 20u32].public;
    get owner_TS[true] into r3;
    assert.eq r0 r3;
    cast r1 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r4 as ChainToken;
    contains other_chain_token_address[r4] into r5;
    assert.eq r5 true;
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r2[0u32] r2[1u32] r2[2u32] r2[3u32] r2[4u32] r2[5u32] r2[6u32] r2[7u32] r2[8u32] r2[9u32] r2[10u32] r2[11u32] r2[12u32] r2[13u32] r2[14u32] r2[15u32] r2[16u32] r2[17u32] r2[18u32] r2[19u32] into r6 as [u8; 32u32];
    set r6 into other_chain_token_address[r4];

function remove_other_chain_addresses:
    input r0 as u128.public;
    async remove_other_chain_addresses self.caller r0 into r1;
    output r1 as vlink_token_service_cd_v3.aleo/remove_other_chain_addresses.future;

finalize remove_other_chain_addresses:
    input r0 as address.public;
    input r1 as u128.public;
    get owner_TS[true] into r2;
    assert.eq r0 r2;
    cast r1 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r3 as ChainToken;
    contains other_chain_token_service[r3] into r4;
    assert.eq r4 true;
    remove other_chain_token_service[r3];
    contains other_chain_token_address[r3] into r5;
    assert.eq r5 true;
    remove other_chain_token_address[r3];
    remove platform_fee[r3];

function add_token_info:
    input r0 as u64.public;
    input r1 as u64.public;
    input r2 as [u8; 20u32].public;
    input r3 as [u8; 20u32].public;
    input r4 as u128.public;
    input r5 as u32.public;
    gte r1 r0 into r6;
    assert.eq r6 true;
    lte r5 100000u32 into r7;
    assert.eq r7 true;
    async add_token_info self.caller r0 r1 r2 r3 r4 r5 into r8;
    output r8 as vlink_token_service_cd_v3.aleo/add_token_info.future;

finalize add_token_info:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as u64.public;
    input r3 as [u8; 20u32].public;
    input r4 as [u8; 20u32].public;
    input r5 as u128.public;
    input r6 as u32.public;
    get owner_TS[true] into r7;
    assert.eq r0 r7;
    cast r5 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r8 as ChainToken;
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r3[0u32] r3[1u32] r3[2u32] r3[3u32] r3[4u32] r3[5u32] r3[6u32] r3[7u32] r3[8u32] r3[9u32] r3[10u32] r3[11u32] r3[12u32] r3[13u32] r3[14u32] r3[15u32] r3[16u32] r3[17u32] r3[18u32] r3[19u32] into r9 as [u8; 32u32];
    set r9 into other_chain_token_address[r8];
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r4[0u32] r4[1u32] r4[2u32] r4[3u32] r4[4u32] r4[5u32] r4[6u32] r4[7u32] r4[8u32] r4[9u32] r4[10u32] r4[11u32] r4[12u32] r4[13u32] r4[14u32] r4[15u32] r4[16u32] r4[17u32] r4[18u32] r4[19u32] into r10 as [u8; 32u32];
    set r10 into other_chain_token_service[r8];
    set r1 into min_transfers[r8];
    set r2 into max_transfers[r8];
    set true into status[r8];
    set r6 into platform_fee[r8];

function pause_token_ts:
    input r0 as u128.public;
    async pause_token_ts self.caller r0 into r1;
    output r1 as vlink_token_service_cd_v3.aleo/pause_token_ts.future;

finalize pause_token_ts:
    input r0 as address.public;
    input r1 as u128.public;
    get owner_TS[true] into r2;
    assert.eq r0 r2;
    cast r1 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r3 as ChainToken;
    set true into status[r3];

function unpause_token_ts:
    input r0 as u128.public;
    async unpause_token_ts self.caller r0 into r1;
    output r1 as vlink_token_service_cd_v3.aleo/unpause_token_ts.future;

finalize unpause_token_ts:
    input r0 as address.public;
    input r1 as u128.public;
    get owner_TS[true] into r2;
    assert.eq r0 r2;
    cast r1 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r3 as ChainToken;
    set false into status[r3];

function update_min_transfer_ts:
    input r0 as u128.public;
    input r1 as u64.public;
    async update_min_transfer_ts self.caller r0 r1 into r2;
    output r2 as vlink_token_service_cd_v3.aleo/update_min_transfer_ts.future;

finalize update_min_transfer_ts:
    input r0 as address.public;
    input r1 as u128.public;
    input r2 as u64.public;
    get owner_TS[true] into r3;
    assert.eq r0 r3;
    cast r1 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r4 as ChainToken;
    get max_transfers[r4] into r5;
    lte r2 r5 into r6;
    assert.eq r6 true;
    contains min_transfers[r4] into r7;
    assert.eq r7 true;
    set r2 into min_transfers[r4];

function update_max_transfer_ts:
    input r0 as u128.public;
    input r1 as u64.public;
    async update_max_transfer_ts self.caller r0 r1 into r2;
    output r2 as vlink_token_service_cd_v3.aleo/update_max_transfer_ts.future;

finalize update_max_transfer_ts:
    input r0 as address.public;
    input r1 as u128.public;
    input r2 as u64.public;
    get owner_TS[true] into r3;
    assert.eq r0 r3;
    cast r1 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r4 as ChainToken;
    get min_transfers[r4] into r5;
    gte r2 r5 into r6;
    assert.eq r6 true;
    contains max_transfers[r4] into r7;
    assert.eq r7 true;
    set r2 into max_transfers[r4];

function token_send_public:
    input r0 as [u8; 20u32].public;
    input r1 as u64.public;
    input r2 as u128.public;
    input r3 as [u8; 20u32].public;
    input r4 as [u8; 20u32].public;
    input r5 as u64.public;
    assert.neq self.caller aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;
    sub r1 r5 into r6;
    call credits.aleo/transfer_public_as_signer vlink_token_service_cd_v3.aleo r6 into r7;
    call credits.aleo/transfer_public_as_signer vlink_token_service_cd_cuncl_v3.aleo r5 into r8;
    cast r2 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r9 as ChainToken;
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r3[0u32] r3[1u32] r3[2u32] r3[3u32] r3[4u32] r3[5u32] r3[6u32] r3[7u32] r3[8u32] r3[9u32] r3[10u32] r3[11u32] r3[12u32] r3[13u32] r3[14u32] r3[15u32] r3[16u32] r3[17u32] r3[18u32] r3[19u32] into r10 as [u8; 32u32];
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r4[0u32] r4[1u32] r4[2u32] r4[3u32] r4[4u32] r4[5u32] r4[6u32] r4[7u32] r4[8u32] r4[9u32] r4[10u32] r4[11u32] r4[12u32] r4[13u32] r4[14u32] r4[15u32] r4[16u32] r4[17u32] r4[18u32] r4[19u32] into r11 as [u8; 32u32];
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r0[0u32] r0[1u32] r0[2u32] r0[3u32] r0[4u32] r0[5u32] r0[6u32] r0[7u32] r0[8u32] r0[9u32] r0[10u32] r0[11u32] r0[12u32] r0[13u32] r0[14u32] r0[15u32] r0[16u32] r0[17u32] r0[18u32] r0[19u32] into r12 as [u8; 32u32];
    sub r1 r5 into r13;
    cast r13 into r14 as u128;
    call vlink_token_bridge_v3.aleo/publish 1u8 r2 r10 r11 self.signer r12 r14 into r15;
    async token_send_public r1 r9 r4 r3 r5 r7 r8 r15 into r16;
    output r16 as vlink_token_service_cd_v3.aleo/token_send_public.future;

finalize token_send_public:
    input r0 as u64.public;
    input r1 as ChainToken.public;
    input r2 as [u8; 20u32].public;
    input r3 as [u8; 20u32].public;
    input r4 as u64.public;
    input r5 as credits.aleo/transfer_public_as_signer.future;
    input r6 as credits.aleo/transfer_public_as_signer.future;
    input r7 as vlink_token_bridge_v3.aleo/publish.future;
    await r5;
    await r6;
    await r7;
    get platform_fee[r1] into r8;
    lte r8 100000u32 into r9;
    assert.eq r9 true;
    cast r8 into r10 as u64;
    mul r0 r10 into r11;
    div r11 100000u64 into r12;
    assert.eq r12 r4;
    get status[r1] into r13;
    assert.eq r13 false;
    get min_transfers[r1] into r14;
    sub r0 r4 into r15;
    gte r15 r14 into r16;
    assert.eq r16 true;
    get max_transfers[r1] into r17;
    sub r0 r4 into r18;
    lte r18 r17 into r19;
    assert.eq r19 true;
    get other_chain_token_service[r1] into r20;
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r3[0u32] r3[1u32] r3[2u32] r3[3u32] r3[4u32] r3[5u32] r3[6u32] r3[7u32] r3[8u32] r3[9u32] r3[10u32] r3[11u32] r3[12u32] r3[13u32] r3[14u32] r3[15u32] r3[16u32] r3[17u32] r3[18u32] r3[19u32] into r21 as [u8; 32u32];
    assert.eq r20 r21;
    get other_chain_token_address[r1] into r22;
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r2[0u32] r2[1u32] r2[2u32] r2[3u32] r2[4u32] r2[5u32] r2[6u32] r2[7u32] r2[8u32] r2[9u32] r2[10u32] r2[11u32] r2[12u32] r2[13u32] r2[14u32] r2[15u32] r2[16u32] r2[17u32] r2[18u32] r2[19u32] into r23 as [u8; 32u32];
    assert.eq r22 r23;
    get.or_use total_supply[r1] 0u64 into r24;
    add r24 r0 into r25;
    sub r25 r4 into r26;
    set r26 into total_supply[r1];

function token_receive_public:
    input r0 as [u8; 20u32].public;
    input r1 as address.public;
    input r2 as u64.public;
    input r3 as u64.public;
    input r4 as u64.public;
    input r5 as [address; 5u32].public;
    input r6 as [signature; 5u32].public;
    input r7 as u128.public;
    input r8 as [u8; 20u32].public;
    assert.neq self.caller aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;
    assert.neq r1 aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r8[0u32] r8[1u32] r8[2u32] r8[3u32] r8[4u32] r8[5u32] r8[6u32] r8[7u32] r8[8u32] r8[9u32] r8[10u32] r8[11u32] r8[12u32] r8[13u32] r8[14u32] r8[15u32] r8[16u32] r8[17u32] r8[18u32] r8[19u32] into r9 as [u8; 32u32];
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r0[0u32] r0[1u32] r0[2u32] r0[3u32] r0[4u32] r0[5u32] r0[6u32] r0[7u32] r0[8u32] r0[9u32] r0[10u32] r0[11u32] r0[12u32] r0[13u32] r0[14u32] r0[15u32] r0[16u32] r0[17u32] r0[18u32] r0[19u32] into r10 as [u8; 32u32];
    cast r2 into r11 as u128;
    call vlink_token_bridge_v3.aleo/consume 1u8 r7 r9 3443843282313283355522573239085696902919850365217539366784739393210722344986field r10 r1 r11 r3 r4 r5 r6 into r12 r13;
    cast r7 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r14 as ChainToken;
    not r12 into r15;
    ternary r15 vlink_holding_cd_v3.aleo r1 into r16;
    ternary r15 r2 0u64 into r17;
    call credits.aleo/transfer_public r16 r2 into r18;
    call vlink_holding_cd_v3.aleo/hold_fund r1 r17 into r19;
    async token_receive_public r2 r17 r14 r8 r13 r18 r19 into r20;
    output r12 as boolean.public;
    output r20 as vlink_token_service_cd_v3.aleo/token_receive_public.future;

finalize token_receive_public:
    input r0 as u64.public;
    input r1 as u64.public;
    input r2 as ChainToken.public;
    input r3 as [u8; 20u32].public;
    input r4 as vlink_token_bridge_v3.aleo/consume.future;
    input r5 as credits.aleo/transfer_public.future;
    input r6 as vlink_holding_cd_v3.aleo/hold_fund.future;
    await r4;
    await r5;
    await r6;
    get status[r2] into r7;
    assert.eq r7 false;
    contains other_chain_token_service[r2] into r8;
    assert.eq r8 true;
    get other_chain_token_service[r2] into r9;
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r3[0u32] r3[1u32] r3[2u32] r3[3u32] r3[4u32] r3[5u32] r3[6u32] r3[7u32] r3[8u32] r3[9u32] r3[10u32] r3[11u32] r3[12u32] r3[13u32] r3[14u32] r3[15u32] r3[16u32] r3[17u32] r3[18u32] r3[19u32] into r10 as [u8; 32u32];
    assert.eq r9 r10;
    get.or_use total_supply[r2] 0u64 into r11;
    sub r11 r0 into r12;
    set r12 into total_supply[r2];
    get.or_use token_holding[3443843282313283355522573239085696902919850365217539366784739393210722344986field] 0u64 into r13;
    add r13 r1 into r14;
    set r14 into token_holding[3443843282313283355522573239085696902919850365217539366784739393210722344986field];

function add_chain_to_existing_token:
    input r0 as u128.public;
    input r1 as [u8; 20u32].public;
    input r2 as [u8; 20u32].public;
    input r3 as u32.public;
    cast r0 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r4 as ChainToken;
    lte r3 100000u32 into r5;
    assert.eq r5 true;
    async add_chain_to_existing_token self.caller r4 r1 r2 r3 into r6;
    output r6 as vlink_token_service_cd_v3.aleo/add_chain_to_existing_token.future;

finalize add_chain_to_existing_token:
    input r0 as address.public;
    input r1 as ChainToken.public;
    input r2 as [u8; 20u32].public;
    input r3 as [u8; 20u32].public;
    input r4 as u32.public;
    contains other_chain_token_service[r1] into r5;
    not r5 into r6;
    assert.eq r6 true;
    contains other_chain_token_address[r1] into r7;
    not r7 into r8;
    assert.eq r8 true;
    get owner_TS[true] into r9;
    assert.eq r0 r9;
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r2[0u32] r2[1u32] r2[2u32] r2[3u32] r2[4u32] r2[5u32] r2[6u32] r2[7u32] r2[8u32] r2[9u32] r2[10u32] r2[11u32] r2[12u32] r2[13u32] r2[14u32] r2[15u32] r2[16u32] r2[17u32] r2[18u32] r2[19u32] into r10 as [u8; 32u32];
    set r10 into other_chain_token_service[r1];
    cast 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 0u8 r3[0u32] r3[1u32] r3[2u32] r3[3u32] r3[4u32] r3[5u32] r3[6u32] r3[7u32] r3[8u32] r3[9u32] r3[10u32] r3[11u32] r3[12u32] r3[13u32] r3[14u32] r3[15u32] r3[16u32] r3[17u32] r3[18u32] r3[19u32] into r11 as [u8; 32u32];
    set r11 into other_chain_token_address[r1];
    set r4 into platform_fee[r1];

function holding_release:
    input r0 as address.public;
    input r1 as u64.public;
    call vlink_holding_cd_v3.aleo/release_fund r0 r1 into r2;
    async holding_release self.caller r1 r2 into r3;
    output r3 as vlink_token_service_cd_v3.aleo/holding_release.future;

finalize holding_release:
    input r0 as address.public;
    input r1 as u64.public;
    input r2 as vlink_holding_cd_v3.aleo/release_fund.future;
    await r2;
    get owner_TS[true] into r3;
    assert.eq r3 r0;
    get token_holding[3443843282313283355522573239085696902919850365217539366784739393210722344986field] into r4;
    sub r4 r1 into r5;
    set r5 into token_holding[3443843282313283355522573239085696902919850365217539366784739393210722344986field];

function holding_transfer_ownership:
    input r0 as address.public;
    assert.neq r0 aleo1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq3ljyzc;
    call vlink_holding_cd_v3.aleo/transfer_ownership_holding r0 into r1;
    async holding_transfer_ownership self.caller r1 into r2;
    output r2 as vlink_token_service_cd_v3.aleo/holding_transfer_ownership.future;

finalize holding_transfer_ownership:
    input r0 as address.public;
    input r1 as vlink_holding_cd_v3.aleo/transfer_ownership_holding.future;
    await r1;
    get owner_TS[true] into r2;
    assert.eq r2 r0;

function update_fees:
    input r0 as u128.public;
    input r1 as u32.public;
    lte r1 100000u32 into r2;
    assert.eq r2 true;
    async update_fees self.caller r0 r1 into r3;
    output r3 as vlink_token_service_cd_v3.aleo/update_fees.future;

finalize update_fees:
    input r0 as address.public;
    input r1 as u128.public;
    input r2 as u32.public;
    cast r1 3443843282313283355522573239085696902919850365217539366784739393210722344986field into r3 as ChainToken;
    get owner_TS[true] into r4;
    assert.eq r4 r0;
    contains platform_fee[r3] into r5;
    assert.eq r5 true;
    set r2 into platform_fee[r3];

constructor:
    assert.eq edition 0u16;
