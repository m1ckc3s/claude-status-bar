import Cocoa

enum ColorTheme: String { case claude, system, mono }            // key statusColorTheme, default claude
enum UsageScope: String { case session, week, urgent }           // key usageWindow, default urgent
enum UsageDisplay: String { case bar, dot, percent, off }        // key usageDisplay, default bar; off hides the menu-bar widget

// Single source of truth for all global prefs. NSObject so it can be the target of its
// own @objc menu actions. didSet persists + broadcasts; observers never run during init,
// so the initial reads below do no write-back.
final class AppSettings: NSObject {
    static let shared = AppSettings()

    private let d: UserDefaults

    var refreshIntervalMinutes: Int  { didSet { d.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes"); onChange?() } }
    var launchAtLogin: Bool          { didSet { d.set(launchAtLogin, forKey: "launchAtLogin"); onChange?() } }
    var statusColorTheme: ColorTheme { didSet { d.set(statusColorTheme.rawValue, forKey: "statusColorTheme"); onChange?() } }
    var usageWindow: UsageScope      { didSet { d.set(usageWindow.rawValue, forKey: "usageWindow"); onChange?() } }
    var usageDisplay: UsageDisplay   { didSet { d.set(usageDisplay.rawValue, forKey: "usageDisplay"); onChange?() } }

    // Controllers chain into this so BOTH widgets re-render after any setter writes.
    var onChange: (() -> Void)?

    // defaults is injectable purely so the self-test can use an isolated suite.
    init(defaults: UserDefaults = .standard) {
        d = defaults
        // object(forKey:) presence test keeps "real default" distinct from a stored 0/false.
        refreshIntervalMinutes = d.object(forKey: "refreshIntervalMinutes") != nil ? d.integer(forKey: "refreshIntervalMinutes") : 5
        launchAtLogin          = d.object(forKey: "launchAtLogin") != nil ? d.bool(forKey: "launchAtLogin") : true
        statusColorTheme       = ColorTheme(rawValue: d.string(forKey: "statusColorTheme") ?? "") ?? .claude
        usageWindow            = UsageScope(rawValue: d.string(forKey: "usageWindow") ?? "") ?? .urgent
        usageDisplay           = UsageDisplay(rawValue: d.string(forKey: "usageDisplay") ?? "") ?? .bar
        super.init()
    }

    // MARK: @objc menu action (reads sender.representedObject, then writes a setter)

    @objc func chooseRefreshInterval(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let v = Int(key) else { return }
        refreshIntervalMinutes = v
    }
}
