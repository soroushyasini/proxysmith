package ir.proxysmith.proxysmith_flutter

import kotlin.test.Test
import kotlin.test.assertEquals

class PipelineTest {
    @Test
    fun `ranking considers all candidates and prioritizes reliability`() {
        val candidates = listOf(
            Candidate("first", 90, jitterMs = 30, successes = 3, attempts = 3, inputIndex = 0),
            Candidate("flaky", 20, jitterMs = 5, successes = 2, attempts = 3, inputIndex = 1),
            Candidate("best", 70, jitterMs = 10, successes = 3, attempts = 3, inputIndex = 2),
            Candidate("jittery", 70, jitterMs = 20, successes = 3, attempts = 3, inputIndex = 3)
        )

        assertEquals(listOf("best", "jittery"), Pipeline.rankCandidates(candidates, 2).map { it.uri })
    }

    @Test
    fun `progress reporter throttles intermediate updates but preserves final update`() {
        val reporter = ProgressReporter(intervalMs = 100)

        assertEquals(false, reporter.shouldEmit(completed = 1, total = 10, nowMs = 50))
        assertEquals(true, reporter.shouldEmit(completed = 2, total = 10, nowMs = 100))
        assertEquals(false, reporter.shouldEmit(completed = 3, total = 10, nowMs = 150))
        assertEquals(true, reporter.shouldEmit(completed = 10, total = 10, nowMs = 151))
    }
}
