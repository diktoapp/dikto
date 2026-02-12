import SwiftUI

// MARK: - Design Tokens

enum Theme {

    // MARK: Spacing (8pt grid)

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs:  CGFloat = 4
        static let xs:   CGFloat = 6
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 12
        static let lg:   CGFloat = 16
        static let xl:   CGFloat = 24
        static let xxl:  CGFloat = 32
    }

    // MARK: Typography

    enum Typography {
        static let largeTitle   = Font.title2.bold()
        static let sectionTitle = Font.headline
        static let body         = Font.body
        static let bodyMedium   = Font.body.weight(.medium)
        static let callout      = Font.callout
        static let caption      = Font.caption
        static let captionMedium = Font.caption.weight(.medium)
        static let mono         = Font.caption.monospaced()
        static let monoSmall    = Font.system(size: 9, weight: .medium, design: .monospaced)
    }

    // MARK: Colors

    enum Colors {
        static let accent           = Color.accentColor
        static let statusActive     = Color.green
        static let statusWarning    = Color.orange
        static let statusError      = Color.red
        static let statusRecording  = Color.red
        static let statusProcessing = Color.orange

        static let badgeGranted     = Color.green.opacity(0.12)
        static let badgeDenied      = Color.red.opacity(0.12)
        static let badgeWarning     = Color.orange.opacity(0.10)

        static let cardBackground   = Color(nsColor: .controlBackgroundColor)
        static let menuHover        = Color.primary.opacity(0.08)
        static let overlayBorder    = Color.primary.opacity(0.1)

        static let recordingGlow    = Color.red.opacity(0.6)
        static let processingGlow   = Color.orange.opacity(0.6)
    }

    // MARK: Radius

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 12
    }

    // MARK: Animation

    enum Animation {
        static let quick    = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let gentle   = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let spring   = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
        static let pulse    = SwiftUI.Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    }

    // MARK: Layout

    enum Layout {
        static let menuBarWidth:      CGFloat = 280
        static let settingsWidth:     CGFloat = 680
        static let settingsHeight:    CGFloat = 520
        static let settingsMinHeight: CGFloat = 400
        static let sidebarWidth:      CGFloat = 220
        static let onboardingWidth:   CGFloat = 480
        static let onboardingHeight:  CGFloat = 500
        static let overlayWidth:      CGFloat = 360
        static let overlayHeight:     CGFloat = 56
        static let recordingDotSize:  CGFloat = 10
    }

    // MARK: Icon Sizes

    enum IconSize {
        static let sm: CGFloat = 16
        static let md: CGFloat = 20
        static let lg: CGFloat = 24
        static let xl: CGFloat = 36
    }
}

// MARK: - Shared Components

/// Reusable permission status badge used in both OnboardingView and PermissionView.
struct StatusBadge: View {
    let granted: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xxxs) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2)
            Text(granted ? "Granted" : "Not Granted")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(granted ? Theme.Colors.statusActive : .secondary)
    }
}

