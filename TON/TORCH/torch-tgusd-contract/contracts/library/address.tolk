import "../common/constants.tolk";

@pure
@inline_ref
fun getStateInit(initCode: cell, initData: cell): cell {
    return beginCell()
    .storeUint(0, 2) // 0b00 - No split_depth; No special
    .storeMaybeRef(initCode)
    .storeMaybeRef(initData)
    .storeUint(0, 1) // Empty libraries
    .endCell();
}

@pure
@inline_ref
fun getContractAddress(stateInit: cell): slice {
    return beginCell()
    .storeUint(2, 2) // addr_std$10
    .storeUint(0, 1) // anycast nothing
    .storeInt(WORKCHAIN, 8)
    .storeUint(stateInit.cellHash(), 256)
    .endCell()
    .beginParse();
}