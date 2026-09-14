import Foundation

/// What kind of app a window belongs to, which decides how its text is read.
public enum CaptureAppKind: String, Codable, Sendable {
    case messaging, browser, mail, code, terminal, generic
}

/// Which apps and sites memory reads, and which it never touches.
public enum CaptureRules {
    public static let messagingApps: Set<String> = [
        "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "com.tdesktop.Telegram", "com.tinyspeck.slackmacgap",
        "com.microsoft.teams2", "com.microsoft.teams", "com.hnc.Discord", "org.whispersystems.signal-desktop",
        "com.apple.MobileSMS", "com.facebook.archon", "com.readdle.smartemail-Mac.messenger",
    ]
    public static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary",
        "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "app.zen-browser.zen",
    ]
    public static let mailApps: Set<String> = [
        "com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac", "com.superhuman.electron",
    ]
    public static let codeApps: Set<String> = [
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode", "dev.zed.Zed",
        "com.exafunction.windsurf", "com.sublimetext.4", "com.panic.Nova",
    ]
    public static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm",
    ]

    /// Never read, whatever the user's settings: secrets, system surfaces, Gobbl itself.
    public static let deniedApps: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal", "com.apple.keychainaccess", "com.apple.Passwords",
        "com.apple.systempreferences", "com.apple.loginwindow", "com.apple.SecurityAgent", "com.apple.ScreenSaver.Engine",
        // Notification banners: one-time codes and other people's messages, out of context.
        "com.apple.UserNotificationCenter", "com.apple.notificationcenterui",
        "com.xeve.gobbl",
    ]

    /// Sites skipped by default: banking, brokerage, crypto, health portals.
    static let deniedDomainWords = [
        "bank", "netbanking", "paypal", "zerodha", "groww", "upstox", "robinhood", "schwab", "fidelity",
        "vanguard", "coinbase", "binance", "kraken", "mychart", "patientportal", "healthrecords",
    ]

    public static func kind(of bundleID: String) -> CaptureAppKind {
        if messagingApps.contains(bundleID) { return .messaging }
        if browsers.contains(bundleID) { return .browser }
        if mailApps.contains(bundleID) { return .mail }
        if codeApps.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.") { return .code }
        if terminals.contains(bundleID) { return .terminal }
        return .generic
    }

    public static func isDeniedDomain(_ domain: String?, extra: Set<String> = []) -> Bool {
        guard let domain = domain?.lowercased(), !domain.isEmpty else { return false }
        if extra.contains(where: { domain == $0 || domain.hasSuffix("." + $0) }) { return true }
        if domain.hasSuffix(".bank") { return true }
        return deniedDomainWords.contains { domain.contains($0) }
    }

    /// Private windows, by title: Safari, Chrome, Edge, Brave, Firefox and Arc mark them there.
    public static func isPrivateWindow(title: String) -> Bool {
        let t = title.lowercased()
        return ["private browsing", "incognito", "inprivate", "private window", "— private", "- private"].contains { t.contains($0) }
    }

    public static func domain(of url: String?) -> String? {
        guard let url, let host = URL(string: url)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
