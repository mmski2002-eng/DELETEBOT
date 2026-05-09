import "../common/constants.tolk";
import "../library/log.tolk";

const LOG_GAS_RESET = stringCrc32("GasReset");
const LOG_ADMIN_CHANGED = stringCrc32("AdminChanged");
const LOG_HALTED = stringCrc32("Halted");
const LOG_UNHALTED = stringCrc32("Unhalted");

@inline
fun logAdminChanged(newAdmin: slice, oldAdmin: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_ADMIN_CHANGED)
        .storeSlice(newAdmin)
        .storeSlice(oldAdmin);
    emitLog(LOG_ADMIN_CHANGED, log);
}

@inline
fun logContractHalted(admin: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_HALTED)
        .storeSlice(admin);
    emitLog(LOG_HALTED, log);
}

@inline
fun logContractUnhalted(admin: slice) {
    val log: builder = beginCell()
        .storeMessageOp(LOG_UNHALTED)
        .storeSlice(admin);
    emitLog(LOG_UNHALTED, log);
}