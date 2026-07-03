import SwiftUI

struct BlockingTimerMenuView: View {
    @ObservedObject private var service = BlockerService.shared

    private let ringSize: CGFloat = 196
    private let ringLineWidth: CGFloat = 12

    var body: some View {
        VStack(spacing: 12) {
            header
            timerRing
            statusLine
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(width: 286)
        .background(AppTheme.background.opacity(0.001))
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            if let endDate = service.sessionEndDate {
                Label {
                    Text(endDate, style: .time)
                } icon: {
                    Image(systemName: "bell.fill")
                }
                .font(.system(size: 12, weight: .medium))
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

            VStack(spacing: 10) {
                Text(service.countdownClockString)
                    .font(.system(size: 54, weight: .thin, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text("Session locked until timer ends")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
        }
        .frame(width: ringSize, height: ringSize)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppTheme.accentBlue)
                .frame(width: 7, height: 7)

            Text("Blocking is active")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.accentBlue.opacity(0.95))
        }
    }
}
