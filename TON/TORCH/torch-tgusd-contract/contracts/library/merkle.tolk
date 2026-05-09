/*
 * Parse exotic cell and return the slice and success flag
 * @param c: cell - the exotic cell to parse
 * @return: (slice, int) - the slice and success flag
*/
@pure
@inline
fun beginParseExotic(c: cell): (slice, bool)
    asm "XCTOS";
