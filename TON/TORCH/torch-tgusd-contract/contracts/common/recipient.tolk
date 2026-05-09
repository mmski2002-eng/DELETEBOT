@pure
@inline
fun getRecipient(recipient: slice, sender: slice): slice {
    return addressIsNone(recipient) ? sender : recipient;
}
