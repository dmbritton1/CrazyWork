import XCTest
@testable import CrazyWork

final class WorkoutAudioCoachTests: XCTestCase {
    func testRepSpeaksNumberWithTick() {
        var coach = WorkoutAudioCoach()
        XCTAssertEqual(coach.handle(.repCompleted(count: 1)), [.tick, .speak("1")])
        XCTAssertEqual(coach.handle(.repCompleted(count: 2)), [.tick, .speak("2")])
    }

    func testCueSpokenOnceUntilItClears() {
        var coach = WorkoutAudioCoach()
        XCTAssertEqual(coach.handle(.formCue("Lower your hips")), [.speak("Lower your hips")])
        XCTAssertEqual(coach.handle(.formCue("Lower your hips")), [])      // repeated -> silent
        XCTAssertEqual(coach.handle(.formCue(nil)), [])                    // cleared -> re-arms
        XCTAssertEqual(coach.handle(.formCue("Lower your hips")), [.speak("Lower your hips")])
    }

    func testPlankAnnouncesTenSecondMilestonesOnce() {
        var coach = WorkoutAudioCoach()
        XCTAssertEqual(coach.handle(.held(seconds: 9.9, target: 35)), [])
        XCTAssertEqual(coach.handle(.held(seconds: 10.0, target: 35)), [.tick, .speak("10 seconds")])
        XCTAssertEqual(coach.handle(.held(seconds: 10.5, target: 35)), [])
        XCTAssertEqual(coach.handle(.held(seconds: 20.0, target: 35)), [.tick, .speak("20 seconds")])
    }

    func testPlankFinalCountdownEachNumberOnce() {
        var coach = WorkoutAudioCoach()
        _ = coach.handle(.held(seconds: 30.0, target: 35)) // prime the 30s milestone so it doesn't overlap the countdown
        XCTAssertEqual(coach.handle(.held(seconds: 32.0, target: 35)), [.speak("three")])
        XCTAssertEqual(coach.handle(.held(seconds: 33.0, target: 35)), [.speak("two")])
        XCTAssertEqual(coach.handle(.held(seconds: 34.0, target: 35)), [.speak("one")])
        XCTAssertEqual(coach.handle(.held(seconds: 34.6, target: 35)), [])
    }

    func testTransitionActions() {
        var coach = WorkoutAudioCoach()
        XCTAssertEqual(coach.handle(.setCompleted(index: 0, total: 2)), [.chime, .speak("Set complete")])
        XCTAssertEqual(coach.handle(.rest(nextExerciseName: "Lunge")),
                       [.restBeep, .speak("Rest. Next up: Lunge")])
        XCTAssertEqual(coach.handle(.finished), [.fanfare, .speak("Workout complete")])
    }

    func testMilestoneFrameSuppressesCountdown() {
        var coach = WorkoutAudioCoach()
        // At 30s with a 33s target, the 30s milestone coincides with "three" —
        // the milestone wins and the countdown number is skipped this frame.
        XCTAssertEqual(coach.handle(.held(seconds: 30.0, target: 33)), [.tick, .speak("30 seconds")])
    }

    func testSetCompletedResetsPerSetState() {
        var coach = WorkoutAudioCoach()
        _ = coach.handle(.held(seconds: 20.0, target: 35))   // milestone 20 recorded
        _ = coach.handle(.setCompleted(index: 0, total: 2))  // resets per-set state
        // Next set's plank should announce 10 again from scratch.
        XCTAssertEqual(coach.handle(.held(seconds: 10.0, target: 35)), [.tick, .speak("10 seconds")])
    }
}
