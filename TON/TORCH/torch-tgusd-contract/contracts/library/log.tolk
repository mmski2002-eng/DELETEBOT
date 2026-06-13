const OP_LOG = 0x31;

@pure
@inline
fun storeLog(mutate self: builder, log: builder): self {
    return log.getBuilderBitsCount() <= 654
        ? self.storeUint(0, 1).storeBuilder(log)
        : self.storeMaybeRef(log.endCell());
}

@inline_ref
fun emitLog(topic: int, log: builder) {
    val msg: cell = beginCell()
        .storeUint(OP_LOG, 2 + 2 + 2) // 110001
        .storeUint(256, 9)
        .storeUint(topic, 256)
        .storeUint(0, 64 + 32 + 1)
        .storeLog(log)
        .endCell();
    sendMessage(msg, SEND_MODE_REGULAR);
}
