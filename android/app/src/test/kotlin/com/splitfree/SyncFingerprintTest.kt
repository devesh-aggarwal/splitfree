package com.splitfree

import com.splitfree.data.GroupEntity
import com.splitfree.data.ParticipantEntity
import com.splitfree.sync.SyncEngine
import com.splitfree.sync.SyncFingerprint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The fingerprints have to be identical on both platforms.
 *
 * If they are not, each app decides the other's rows have changed and pushes
 * them back, forever, and nothing looks broken while it happens: no error, no
 * wrong number on screen, just a group that quietly never stops syncing.
 *
 * The expected values below were computed from the FNV-1a specification, not
 * from either app. `SyncFingerprintTests.swift` asserts the same values against
 * the same inputs, so if the two implementations ever drift apart, at least one
 * of these files fails.
 */
class SyncFingerprintTest {

    @Test
    fun `matches the shared vectors`() {
        assertEquals("cbf29ce484222325", SyncFingerprint.of(listOf("")))
        assertEquals("acaeb607516495a3", SyncFingerprint.of(listOf("Lisbon", "trip", "42")))
        assertEquals("3c391f6a60531fa9", SyncFingerprint.of(listOf("Café", "Ünïcode", "日本語")))
    }

    /**
     * Without a separator these two hash the same, and two different rosters
     * would be indistinguishable.
     */
    @Test
    fun `field boundaries are part of the hash`() {
        assertEquals("fd64a883ef221576", SyncFingerprint.of(listOf("ab", "c")))
        assertEquals("b6691782144715c4", SyncFingerprint.of(listOf("a", "bc")))
    }

    @Test
    fun `a group hashes to the value both platforms agree on`() {
        val ana = ParticipantEntity(
            id = "11111111-1111-1111-1111-111111111111",
            name = "Ana",
            colorIndex = 0,
            isCurrentUser = true,
        )
        val group = GroupEntity(
            id = "44444444-4444-4444-4444-444444444444",
            name = "Lisbon Trip",
            kind = "trip",
            colorIndex = 2,
            defaultCurrencyCode = "EUR",
            simplifyDebts = true,
        )
        assertEquals(
            "600fa776858d704f",
            SyncFingerprint.forGroup(group, listOf(ana)) { it.id },
        )
    }

    @Test
    fun `renaming a member changes the group fingerprint`() {
        val ana = ParticipantEntity(id = "a", name = "Ana")
        val group = GroupEntity(id = "g", name = "Trip")
        val before = SyncFingerprint.forGroup(group, listOf(ana)) { it.id }
        val after = SyncFingerprint.forGroup(group, listOf(ana.copy(name = "Anna"))) { it.id }
        assertNotEquals(before, after)
    }

    /** Sub-second precision does not survive Postgres, so it must not be hashed. */
    @Test
    fun `stamps drop milliseconds`() {
        assertEquals(SyncFingerprint.stamp(1_700_000_000_000), SyncFingerprint.stamp(1_700_000_000_400))
        assertNotEquals(SyncFingerprint.stamp(1_700_000_000_000), SyncFingerprint.stamp(1_700_000_002_000))
    }
}

class InviteLinkTest {

    @Test
    fun `a web link carries its token in the fragment, where servers never see it`() {
        assertEquals("abc123", SyncEngine.inviteToken("https://devesh-aggarwal.github.io/splitfree/join.html#abc123"))
    }

    @Test
    fun `the custom scheme works too`() {
        assertEquals("abc123", SyncEngine.inviteToken("splitfree://join#abc123"))
    }

    @Test
    fun `an unrelated link is not mistaken for an invite`() {
        assertNull(SyncEngine.inviteToken("https://example.com/join#abc"))
        assertNull(SyncEngine.inviteToken("splitfree://auth-callback#token"))
    }
}

class ServerTimestampTest {

    /**
     * Postgres returns six fractional digits and writes the offset as `+00:00`.
     * If parsing fails the cursor never advances, and every sync re-downloads
     * the entire history.
     */
    @Test
    fun `a postgres timestamp with microseconds parses`() {
        val withMicros = SyncEngine.epochMillis("2026-08-12T04:05:06.123456+00:00")
        val withMillis = SyncEngine.epochMillis("2026-08-12T04:05:06.123Z")
        assertEquals(withMillis, withMicros)
    }

    @Test
    fun `a timestamp with no fractional part parses`() {
        assertEquals(SyncEngine.epochMillis("2026-08-12T04:05:06Z"), 1786507506000L)
    }

    @Test
    fun `a timestamp survives a round trip`() {
        val original = 1_765_432_109_000L
        assertEquals(original, SyncEngine.epochMillis(SyncEngine.timestamp(original)))
    }

    @Test
    fun `nonsense is rejected rather than silently becoming a date`() {
        assertNull(SyncEngine.epochMillis("-infinity"))
        assertNull(SyncEngine.epochMillis(""))
        assertNull(SyncEngine.epochMillis(null))
    }
}
