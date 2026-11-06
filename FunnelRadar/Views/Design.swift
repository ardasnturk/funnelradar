import SwiftUI

/// FunnelRadar's look: the same cards, buttons and soft background as MRRadar, Remote Code, Vitrin
/// and Promo Studio, with a violet and blue gradient of its own.
enum Brand {
    static let violet = Color(red: 0.49, green: 0.31, blue: 0.95)
    static let blue = Color(red: 0.20, green: 0.48, blue: 0.97)
    static let pink = Color(red: 0.86, green: 0.36, blue: 0.82)
    static let gold = Color(red: 0.96, green: 0.70, blue: 0.22)
    static let coral = Color(red: 0.97, green: 0.42, blue: 0.42)
    static let mint = Color(red: 0.23, green: 0.80, blue: 0.62)

    static let gradient = LinearGradient(colors: [violet, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let buttonGradient = LinearGradient(colors: [violet, blue], startPoint: .leading, endPoint: .trailing)
    /// One colour per app in a chart, in a fixed order.
    static let series: [Color] = [violet, blue, mint, gold, pink, coral]
}

struct BrandBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    /// Snapshots can't draw a blur, so they use a plain gradient.
    nonisolated(unsafe) static var isFlat = false

    var body: some View {
        if Self.isFlat {
            LinearGradient(colors: [Color(red: 0.11, green: 0.09, blue: 0.20), Color(red: 0.07, green: 0.08, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        } else {
            blobs
        }
    }

    private var blobs: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Circle().fill(Brand.violet).frame(width: size.width * 0.8, height: size.width * 0.8)
                        .offset(x: -size.width * 0.35, y: -size.height * 0.35)
                    Circle().fill(Brand.blue).frame(width: size.width * 0.7, height: size.width * 0.7)
                        .offset(x: size.width * 0.4, y: -size.height * 0.1)
                    Circle().fill(Brand.pink).frame(width: size.width * 0.6, height: size.width * 0.6)
                        .offset(x: -size.width * 0.1, y: size.height * 0.5)
                }
                .frame(width: size.width, height: size.height)
            }
            .blur(radius: 70)
            .opacity(colorScheme == .dark ? 0.32 : 0.2)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 14, padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }
}

struct IconBadge: View {
    let symbol: String
    var colors: [Color] = [Brand.violet, Brand.blue]
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol).font(.system(size: size * 0.52, weight: .semibold)).foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .background(Brand.buttonGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct StatusPill: View {
    let text: Text
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            text
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.white.opacity(0.18), in: Capsule())
    }
}

/// A project's initial. Mixpanel projects have no icons.
struct ProjectIcon: View {
    let name: String
    var size: CGFloat = 28

    var body: some View {
        Brand.gradient
            .overlay {
                Text(verbatim: String(name.prefix(1)))
                    .font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}
