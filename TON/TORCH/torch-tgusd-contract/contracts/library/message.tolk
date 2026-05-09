// after `grams:Grams` we have (1 + 4 + 4 + 64 + 32) zeroes - zeroed extracurrency, ihr_fee, fwd_fee, created_lt and created_at
const MSG_INFO_REST_BITS = 1 + 4 + 4 + 64 + 32;

// MSG

// https://github.com/ton-blockchain/ton/blob/8a9ff339927b22b72819c5125428b70c406da631/crypto/block/block.tlb#L155
// message$_ {X:Type} info:CommonMsgInfo
//  init:Maybe (Either StateInit ^StateInit)
//  body:(Either X ^X) = Message X;
//
// message$_ {X:Type} info:CommonMsgInfoRelaxed
//  init:(Maybe (Either StateInit ^StateInit))
//  body:(Either X ^X) = MessageRelaxed X;
//
// _ (Message Any) = MessageAny;

// if have StateInit (always place StateInit in ref):
// 0b11 for `Maybe (Either StateInit ^StateInit)` and 0b1 or 0b0 for `body:(Either X ^X)`
const MSG_WITH_STATE_INIT_AND_BODY_SIZE = MSG_INFO_REST_BITS + 1 + 1 + 1;
const MSG_HAVE_STATE_INIT = 4;
const MSG_STATE_INIT_IN_REF = 2;
const MSG_BODY_IN_REF = 1;

// if no StateInit:
// 0b0 for `Maybe (Either StateInit ^StateInit)` and 0b1 or 0b0 for `body:(Either X ^X)`
const MSG_ONLY_BODY_SIZE = MSG_INFO_REST_BITS + 1 + 1;

@pure
@inline 
fun storeStateInitAndBody(mutate self: builder, stateInit: cell, body: cell): self {
    return self
        .storeUint(MSG_HAVE_STATE_INIT + MSG_STATE_INIT_IN_REF + MSG_BODY_IN_REF, MSG_WITH_STATE_INIT_AND_BODY_SIZE)
        .storeRef(stateInit)
        .storeRef(body);
}

@pure
@inline
fun storeOnlyBodyRef(mutate self: builder, body: cell): self {
    return self
        .storeUint(MSG_BODY_IN_REF, MSG_ONLY_BODY_SIZE)
        .storeRef(body);
}