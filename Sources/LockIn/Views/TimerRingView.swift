import SwiftUI

/// The circular countdown ring, shared between the menu bar popover and the main dashboard.
struct TimerRingView: View {
    @ObservedObject private var service = BlockerService.shared
    var size: CGFloat = 164
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            if service.isPaused {
                breakRing
            } else {
                timerRing
            }
        }
        .frame(width: size, height: size)
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth))

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                Circle()
                    .trim(from: 0.015, to: max(0.015, 1 - service.sessionProgress(at: context.date)))
                    .stroke(
                        LinearGradient(
                            colors: [
                                AppTheme.accentBlue.opacity(0.88),
                                AppTheme.accentBlue,
                                Color(red: 88.0 / 255.0, green: 171.0 / 255.0, blue: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: AppTheme.accentBlue.opacity(0.30), radius: 8)
            }

            VStack(spacing: 2) {
                if let endDate = service.sessionEndDate {
                    Label {
                        Text(endDate, style: .time)
                    } icon: {
                        Image(systemName: "bell.fill")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Text(service.countdownClockString)
                    .font(.system(size: 42, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
        }
    }

    private var breakRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth))

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { _ in
                let total = max(1.0, Double(service.breakMinutesChosen * 60))
                let fraction = min(1, max(0, Double(service.breakRemainingSeconds) / total))
                Circle()
                    .trim(from: 0.015, to: max(0.015, fraction))
                    .stroke(
                        LinearGradient(
                            colors: [.orange.opacity(0.88), .orange, Color(red: 1.0, green: 0.72, blue: 0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color.orange.opacity(0.30), radius: 8)
            }

            VStack(spacing: 6) {
                if service.breakRemainingSeconds > 0 {
                    Text(service.breakCountdownString)
                        .font(.system(size: 42, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                } else {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.orange)
                    Text("Break's over")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
