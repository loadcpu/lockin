import Foundation

public enum TimerInputRules {
    public static let maxFieldLength = 2

    public static func sanitize(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(maxFieldLength))
    }

    public static func allowsReplacement(currentText: String, range: NSRange, replacementString: String?) -> Bool {
        guard let replacementString else { return true }
        if replacementString.isEmpty { return true }

        let allowedCharacters = CharacterSet.decimalDigits
        if replacementString.rangeOfCharacter(from: allowedCharacters.inverted) != nil {
            return false
        }

        let currentNSString = currentText as NSString
        let proposedText = currentNSString.replacingCharacters(in: range, with: replacementString)
        return proposedText.count <= maxFieldLength
    }

    public static func normalized(hours: String, minutes: String, seconds: String) -> NormalizedTimerInput {
        let sanitizedHours = sanitize(hours)
        let sanitizedMinutes = sanitize(minutes)
        let sanitizedSeconds = sanitize(seconds)

        let hoursValue = min(Int(sanitizedHours) ?? 0, 23)
        let minutesValue = min(Int(sanitizedMinutes) ?? 0, 59)
        let secondsValue = min(Int(sanitizedSeconds) ?? 0, 59)
        let totalMinutes = min(hoursValue * 60 + minutesValue + (secondsValue > 0 ? 1 : 0), 1440)

        return NormalizedTimerInput(
            hoursText: sanitizedHours,
            minutesText: sanitizedMinutes,
            secondsText: sanitizedSeconds,
            totalMinutes: totalMinutes
        )
    }

    public static func fields(fromTotalMinutes totalMinutes: Int) -> NormalizedTimerFields {
        let safeTotal = max(0, min(totalMinutes, 1440))
        let hours = safeTotal / 60
        let minutes = safeTotal % 60

        return NormalizedTimerFields(
            hoursText: String(format: "%02d", hours),
            minutesText: String(format: "%02d", minutes),
            secondsText: "00"
        )
    }
}

public struct NormalizedTimerInput: Equatable {
    public let hoursText: String
    public let minutesText: String
    public let secondsText: String
    public let totalMinutes: Int

    public init(hoursText: String, minutesText: String, secondsText: String, totalMinutes: Int) {
        self.hoursText = hoursText
        self.minutesText = minutesText
        self.secondsText = secondsText
        self.totalMinutes = totalMinutes
    }
}

public struct NormalizedTimerFields: Equatable {
    public let hoursText: String
    public let minutesText: String
    public let secondsText: String

    public init(hoursText: String, minutesText: String, secondsText: String) {
        self.hoursText = hoursText
        self.minutesText = minutesText
        self.secondsText = secondsText
    }
}
