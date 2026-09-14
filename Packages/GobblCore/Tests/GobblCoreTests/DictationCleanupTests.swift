import Testing
@testable import GobblCore

@Suite struct DictationCleanupTests {
    @Test func verbatimOnlyDropsWhisperArtefacts() {
        #expect(DictationCleanup.verbatim(" [BLANK_AUDIO] hello  world (music) ") == "hello world")
        #expect(DictationCleanup.verbatim("um, so") == "um, so")
    }

    @Test func lightRemovesFillersAndCommas() {
        #expect(DictationCleanup.light("Um, so I think we should, uh, ship it.") == "So I think we should ship it.")
        #expect(DictationCleanup.light("It's fine, um.") == "It's fine.")
        #expect(DictationCleanup.light("So umm I think") == "So I think")
    }

    @Test func lightFixesStuttersButKeepsRealDoubles() {
        #expect(DictationCleanup.light("the the plan is is fine") == "The plan is fine")
        #expect(DictationCleanup.light("I know that that works") == "I know that that works")
    }

    @Test func lightKeepsWordsThatStartLikeFillers() {
        #expect(DictationCleanup.light("umbrella errands ahead") == "Umbrella errands ahead")
    }

    @Test func spokenLayout() {
        #expect(DictationCleanup.light("Hi team, new paragraph, the build is green. new line thanks") ==
            "Hi team\n\nThe build is green.\nThanks")
    }

    @Test func capitalisesSentences() {
        #expect(DictationCleanup.light("ok. is it done? yes! great") == "Ok. Is it done? Yes! Great")
    }

    @Test func hallucinationsOnSilence() {
        #expect(DictationCleanup.isLikelyHallucination("Thank you."))
        #expect(DictationCleanup.isLikelyHallucination("  "))
        #expect(!DictationCleanup.isLikelyHallucination("Thank you for the update"))
    }

    @Test func vocabularyPrompt() {
        #expect(DictationCleanup.vocabularyPrompt([" Gobbl", "", "Xeve "]) == "Gobbl, Xeve.")
        #expect(DictationCleanup.vocabularyPrompt([]) == nil)
    }
}
