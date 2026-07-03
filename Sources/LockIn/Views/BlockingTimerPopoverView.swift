import SwiftUI

struct BlockingTimerMenuView: View {
    @ObservedObject private var service = BlockerService.shared

    private let ringSize: CGFloat = 164
    private let ringLineWidth: CGFloat = 10

    var body: some View {
        VStack(spacing: 10) {
            header
            timerRing
            statusLine
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: 240)
        .background(AppTheme.background.opacity(0.001))
    }

    private var header: some View {
        VStack(spacing: 3) {
            Text("Timer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            if let endDate = service.sessionEndDate {
                Label {
                    Text(endDate, style: .time)
                } icon: {
                    Image(systemName: "bell.fill")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: ringLineWidth))

            Circle()
                .trim(from: 0.015, to: max(0.015, 1 - service.sessionProgress))
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

            VStack(spacing: 8) {
                Text(service.countdownClockString)
                    .font(.system(size: 42, weight: .thin, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 16)
        }
        .frame(width: ringSize, height: ringSize)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppTheme.accentBlue)
                .frame(width: 6, height: 6)

            Text("Blocking is active")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.accentBlue.opacity(0.95))
        }
    }
}
