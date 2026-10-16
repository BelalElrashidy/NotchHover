import Foundation

/// Meeting links found in real-looking invitation text: --calendar-selftest
enum CalendarSelfTest {
    static func run() {
        var results: [String] = []
        func expect(_ label: String, _ condition: Bool) {
            results.append((condition ? "✓ " : "✗ ") + label)
        }

        let zoomInvite = """
        Bilal is inviting you to a scheduled Zoom meeting.
        Join Zoom Meeting
        <https://us02web.zoom.us/j/81234567890?pwd=AbCdEf123>.
        Meeting ID: 812 3456 7890
        """
        let zoom = MeetingLink.find(in: zoomInvite)
        expect("Zoom, inside <…> with a password", zoom?.service == "Zoom" && zoom?.url.absoluteString == "https://us02web.zoom.us/j/81234567890?pwd=AbCdEf123")
        let app = zoom?.appURL(isInstalled: { _ in true })?.absoluteString ?? ""
        expect("Zoom opens in the app with its number and password", app == "zoommtg://zoom.us/join?confno=81234567890&pwd=AbCdEf123")

        expect("Google Meet", MeetingLink.find(in: "Join with Google Meet: https://meet.google.com/abc-defg-hij\nOr dial…")?.service == "Google Meet")
        let teams = MeetingLink.find(in: "Microsoft Teams meeting\nJoin: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d")
        expect("Teams", teams?.service == "Teams")
        expect("Teams opens in the app", teams?.appURL(isInstalled: { _ in true })?.scheme == "msteams")
        expect("FaceTime", MeetingLink.find(in: "https://facetime.apple.com/join#v=1&p=AbC&k=xyz")?.service == "FaceTime")
        expect("Webex", MeetingLink.find(in: "https://acme.webex.com/acme/j.php?MTID=m123")?.service == "Webex")
        expect("No link, no button", MeetingLink.find(in: "Lunch with Sam at Dishoom. See https://dishoom.com") == nil)
        expect("Without the app, the web link", zoom?.appURL(isInstalled: { _ in false }) == nil)

        let failed = results.filter { $0.hasPrefix("✗") }.count
        FileHandle.standardError.write(Data(("calendar: " + results.joined(separator: "  ") + "\n").utf8))
        exit(failed == 0 ? 0 : 1)
    }
}
