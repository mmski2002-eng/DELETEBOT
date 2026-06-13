@pure
@inline
fun getOriginalFwdFee(workchain: int, fwdFee: int): int
    asm(fwdFee workchain) "GETORIGINALFWDFEE";

@pure
@inline
fun getCtx(mutate self: slice, workchain: int) {
    val ctxSender: slice = self.loadAddress();
    self.loadAddress(); // skip dst
    self.loadCoins();   // skip value
    self.skipDict();    // skip extracurrency collection
    self.loadCoins();   // skip ihr fee
    val ctxFwdFee: int = getOriginalFwdFee(workchain, self.loadCoins());
    return (ctxSender, ctxFwdFee);
}
