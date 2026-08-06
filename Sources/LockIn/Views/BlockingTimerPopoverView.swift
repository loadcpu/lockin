import SwiftUI

struct BlockingTimerMenuView: View {
    @ObservedObject private var service = BlockerService.shared
    @State private var showingBreakPicker = false
    @State private var breakMinutes: Double = 10

    private let ringSize: CGFloat = 164
    private let ringLineWidth: CGFloat = 10

    var body: some View {
        VStack(spacing: 10) {
            if service.isPaused {
                breakRing
            } else {
                timerRing
            }
            bottomControls
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 220)
        .background(AppTheme.background.opacity(0.001))
        .onAppear { breakMinutes = min(10, max(0, Double(service.breaksAvailable > 0 ? 10 : 0))) }
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: ringLineWidth))

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
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
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
        .frame(width: ringSize, height: ringSize)
    }

    private var breakRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: ringLineWidth))

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
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
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
        .frame(width: ringSize, height: ringSize)
    }

    @ViewBuilder
    private var bottomControls: some View {
        if service.isPaused {
            resumeButton
        } else if showingBreakPicker {
            breakPicker
        } else if service.breaksAvailable > 0 {
            startBreakPrompt
        } else {
            Text("Earn a 10-min break every hour")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
    }

    private var resumeButton: some View {
        pillButton("Resume Session", systemImage: "play.fill", fill: AppTheme.accentBlue, foreground: .white) {
            service.resumeSession()
        }
    }

    private var startBreakPrompt: some View {
        outlinePillButton(
            "Take a Break (\(service.breaksAvailable) earned)",
            systemImage: "pause.fill"
        ) {
            showingBreakPicker = true
        }
    }

    private var breakPicker: some View {
        VStack(spacing: 8) {
            Text("\(Int(breakMinutes)) min break")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Slider(value: $breakMinutes, in: 0...10, step: 1)
            HStack(spacing: 8) {
                outlinePillButton("Cancel") { showingBreakPicker = false }
                pillButton("Start Break", fill: .orange, foreground: .black) {
                    service.pauseSession(minutes: Int(breakMinutes))
                    showingBreakPicker = false
                }
            }
        }
    }

    // MARK: - Custom pill buttons
    //
    // Native `.borderedProminent`/`.bordered` styles render through the status-bar menu's
    // vibrancy material and lose their tint (everything comes out a flat gray). Drawing the
    // fill/stroke ourselves and using `.plain` keeps the actual color.

    private func pillButton(
        _ title: String,
        systemImage: String? = nil,
        fill: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }

    private func outlinePillButton(
        _ title: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.92))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
