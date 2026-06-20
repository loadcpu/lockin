import Foundation
import TimerInputSupport

struct CheckRunner {
    private(set) var failures: [String] = []

    mutating func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }
}

@main
struct TimerInputRuleChecksMain {
    static func main() {
        var runner = CheckRunner()

        runner.expect(
            TimerInputRules.allowsReplacement(
                currentText: "12",
                range: NSRange(location: 1, length: 1),
                replacementString: ""
            ),
            "Deleting text should stay allowed"
        )

        runner.expect(
            !TimerInputRules.allowsReplacement(
                currentText: "04",
                range: NSRange(location: 2, length: 0),
                replacementString: "a"
            ),
            "Letters should be rejected"
        )

        runner.expect(
            !TimerInputRules.allowsReplacement(
                currentText: "12",
                range: NSRange(location: 2, length: 0),
                replacementString: "3"
            ),
            "A third digit should be rejected"
        )

        runner.expect(
            TimerInputRules.allowsReplacement(
                currentText: "04",
                range: NSRange(location: 0, length: 2),
                replacementString: "99"
            ),
            "Replacing the whole field with two digits should be allowed"
        )

        runner.expect(
            !TimerInputRules.allowsReplacement(
                currentText: "",
                range: NSRange(location: 0, length: 0),
                replacementString: "123"
            ),
            "Pasting more than two digits into an empty field should be rejected"
        )

        runner.expect(
            !TimerInputRules.allowsReplacement(
                currentText: "0",
                range: NSRange(location: 1, length: 0),
                replacementString: "2a"
            ),
            "Mixed digit-letter replacements should be rejected"
        )

        runner.expect(
            TimerInputRules.sanitize("1a234") == "12",
            "Sanitize should keep only the first two digits"
        )

        runner.expect(
            TimerInputRules.sanitize("ab") == "",
            "Sanitize should remove letters entirely"
        )

        let clamped = TimerInputRules.normalized(hours: "99", minutes: "88", seconds: "77")
        runner.expect(clamped.hoursText == "99", "Hours text should preserve the typed digits")
        runner.expect(clamped.minutesText == "88", "Minutes text should preserve the typed digits")
        runner.expect(clamped.secondsText == "77", "Seconds text should preserve the typed digits")
        runner.expect(clamped.totalMinutes == 1440, "Total minutes should clamp to 1440")

        let rounded = TimerInputRules.normalized(hours: "01", minutes: "30", seconds: "01")
        runner.expect(rounded.totalMinutes == 91, "Any non-zero seconds should round the total up by one minute")

        let fields = TimerInputRules.fields(fromTotalMinutes: 65)
        runner.expect(fields == NormalizedTimerFields(hoursText: "01", minutesText: "05", secondsText: "00"),
                      "Field formatting should return zero-padded hour/minute text")

        if runner.failures.isEmpty {
            print("TimerInputRuleChecks: all checks passed")
            return
        }

        fputs("TimerInputRuleChecks failed:\n", stderr)
        for failure in runner.failures {
            fputs("- \(failure)\n", stderr)
        }
        exit(1)
    }
}
