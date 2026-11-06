import AppKit
import FunnelKit
import UserNotifications

/// Texts of an alert, here so the Mac notification and the list in the app read the same.
extension FunnelAlert {
    var title: String {
        switch kind {
        case .conversionDrop: String(localized: "Conversion fell · \(projectName)")
        case .eventSpike: String(localized: "Unusually busy day · \(projectName)")
        case .eventDip: String(localized: "Unusually quiet day · \(projectName)")
        case .retentionDrop: String(localized: "Retention fell · \(projectName)")
        }
    }

    var body: String {
        switch kind {
        case .conversionDrop:
            return String(localized: "\(subject): \(Format.percent(value)) now, \(Format.percent(baseline)) the period before.")
        case .eventSpike, .eventDip:
            return String(localized: "\(subject): \(Format.count(value)) users, against about \(Format.count(baseline)) on a normal day.")
        case .retentionDrop:
            return String(localized: "Day 7 retention is \(Format.percent(value)), down from \(Format.percent(baseline)).")
        }
    }

    var symbol: String {
        switch kind {
        case .conversionDrop: "line.3.horizontal.decrease"
        case .eventSpike: "arrow.up.right"
        case .eventDip: "arrow.down.right"
        case .retentionDrop: "person.badge.minus"
        }
    }

    var isGood: Bool { kind == .eventSpike }
}

@MainActor
enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func post(_ alert: FunnelAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.userInfo = ["project": alert.projectID]
        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Shows banners while FunnelRadar is in front, and opens the project a notification is about.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    let open: @MainActor @Sendable (String) -> Void

    init(open: @escaping @MainActor @Sendable (String) -> Void) {
        self.open = open
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let project = response.notification.request.content.userInfo["project"] as? String else { return }
        await open(project)
    }
}
