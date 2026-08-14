package com.splitfree.sync

/**
 * A join code, and the link that carries it.
 *
 * The code goes in the link's fragment. Browsers never send a fragment to a
 * server, so a code opened on the web leaves no copy of itself in anybody's
 * access log.
 */
data class Invite(val code: String) {

    /** Grouped in fives, which is how people read a code aloud. */
    val formattedCode: String
        get() {
            val clean = code.uppercase().filter { it.isLetterOrDigit() }
            return if (clean.length == 10) "${clean.take(5)}-${clean.drop(5)}" else clean
        }

    val url: String get() = "https://devesh-aggarwal.github.io/splitfree/join.html#$code"
}
