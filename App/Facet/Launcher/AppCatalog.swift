import Foundation

/// One launchable target for a launcher tile.
///
/// `sfSymbol` is a *stand-in* glyph, not the app's real icon: iOS ships no API
/// to read another app's icon asset, and shipping traced copies of third-party
/// marks would be a trademark problem. A symbol is also the right primitive for
/// Facet — themes restyle it (weight, fill, gradient) the way they restyle any
/// other layer, which is the whole point of a *themed* launcher.
struct CatalogApp: Identifiable, Hashable, Sendable {
    /// Stable slug. Persisted in documents, so never renumber or rename these.
    let id: String
    let displayName: String
    /// Full scheme including the separator, e.g. `"spotify://"`, `"mailto:"`.
    let urlScheme: String
    let sfSymbol: String
    let category: Category

    /// False when the scheme is community-sourced rather than documented by the
    /// vendor. Unverified schemes are usually right, but a wrong one fails
    /// *silently* — iOS just does nothing on tap — so the picker labels them
    /// instead of letting the user discover it on their home screen.
    let isVerified: Bool
    /// Why it's unverified, or a caveat about what the scheme actually opens.
    let note: String?

    init(
        id: String,
        displayName: String,
        urlScheme: String,
        sfSymbol: String,
        category: Category,
        isVerified: Bool = true,
        note: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.urlScheme = urlScheme
        self.sfSymbol = sfSymbol
        self.category = category
        self.isVerified = isVerified
        self.note = note
    }

    /// The URL a tile tap opens. nil only for the "Custom…" placeholder.
    var launchURL: URL? {
        urlScheme.isEmpty ? nil : URL(string: urlScheme)
    }

    enum Category: String, CaseIterable, Identifiable, Sendable {
        // allCases order is the picker's section order: the things people
        // launch most, first.
        case communication
        case social
        case music
        case productivity
        case photo
        case travel
        case finance
        case health
        case utilities
        case system

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .communication: return "Communication"
            case .social: return "Social"
            // Broader than the case name: streaming video lives here too,
            // rather than inventing a category the schema doesn't have.
            case .music: return "Music & Media"
            case .productivity: return "Productivity"
            case .photo: return "Photo & Camera"
            case .travel: return "Travel & Maps"
            case .finance: return "Finance"
            case .health: return "Health & Fitness"
            case .utilities: return "Shopping & Utilities"
            case .system: return "System"
            }
        }
    }
}

// MARK: - Custom entries

extension CatalogApp {
    /// Placeholder id for the picker's "Custom…" affordance. Never persisted.
    static let customPlaceholderID = "custom"
    private static let customPrefix = "custom:"

    /// The "type your own scheme" row. Has no URL by design.
    static let customEntry = CatalogApp(
        id: customPlaceholderID,
        displayName: "Custom…",
        urlScheme: "",
        sfSymbol: "app.dashed",
        category: .utilities,
        isVerified: false,
        note: "Point a tile at any URL scheme by hand."
    )

    var isCustom: Bool {
        id == Self.customPlaceholderID || id.hasPrefix(Self.customPrefix)
    }

    /// A user-entered target. nil when the scheme can't form a URL — better to
    /// disable the button than to save a tile that will never open.
    static func custom(
        displayName: String,
        urlScheme: String,
        sfSymbol: String = "app.dashed"
    ) -> CatalogApp? {
        guard let scheme = normalizedScheme(urlScheme) else { return nil }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return CatalogApp(
            // Keyed by scheme so re-entering the same target is the same app.
            id: customPrefix + scheme,
            displayName: name.isEmpty ? scheme : name,
            urlScheme: scheme,
            sfSymbol: sfSymbol,
            category: .utilities,
            isVerified: false,
            note: "Hand-entered — Facet can't check that this app is installed."
        )
    }

    /// Accepts what people actually type: `spotify`, `spotify:`, `spotify://`,
    /// `Spotify://` all normalize to `spotify://`. Returns nil for anything
    /// that isn't a usable scheme.
    static func normalizedScheme(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains(":") { text += "://" }

        let head = text.prefix { $0 != ":" }
        guard let first = head.first, first.isLetter,
              head.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else { return nil }

        // Schemes are case-insensitive (RFC 3986), so fold them: otherwise
        // "Bandcamp://" and "bandcamp://" become two different saved apps.
        let normalized = head.lowercased() + text.dropFirst(head.count)
        guard URL(string: normalized) != nil else { return nil }
        return normalized
    }
}

/// The curated launcher catalog.
///
/// This list is hand-maintained and always will be. iOS has no public API to
/// enumerate installed apps (`LSApplicationWorkspace` is private and an
/// App Store rejection), no API to read another app's icon, and
/// `canOpenURL` is capped at 50 pre-declared schemes in Info.plist — so Facet
/// can't even reliably tell you whether a target is installed. What it *can*
/// do is offer a good list of published schemes and be honest about which ones
/// it trusts.
///
/// Schemes are undocumented, unversioned API for most third-party apps. They
/// break when a vendor rewrites their client and nobody announces it. Entries
/// carry `isVerified` for that reason; see the notes on individual apps.
enum AppCatalog {
    typealias Category = CatalogApp.Category

    // MARK: Query

    /// Case- and diacritic-insensitive match on `displayName`, ranked so a
    /// prefix hit beats a mid-word one ("map" surfaces Maps before Snapchat).
    static func search(_ query: String) -> [CatalogApp] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return ranked(all) }

        return all
            .compactMap { app in matchRank(app.displayName, needle).map { (app, $0) } }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.0.isVerified != rhs.0.isVerified { return lhs.0.isVerified }
                return lhs.0.displayName.localizedCaseInsensitiveCompare(rhs.0.displayName) == .orderedAscending
            }
            .map(\.0)
    }

    /// Sections in `Category.allCases` order; empty categories are dropped.
    static func grouped() -> [(Category, [CatalogApp])] {
        Category.allCases.compactMap { category in
            let apps = ranked(all.filter { $0.category == category })
            return apps.isEmpty ? nil : (category, apps)
        }
    }

    static func grouped(_ apps: [CatalogApp]) -> [(Category, [CatalogApp])] {
        Category.allCases.compactMap { category in
            let matches = ranked(apps.filter { $0.category == category })
            return matches.isEmpty ? nil : (category, matches)
        }
    }

    static func app(id: String) -> CatalogApp? {
        all.first { $0.id == id }
    }

    static var verified: [CatalogApp] { all.filter(\.isVerified) }

    /// Verified first, then alphabetical — the picker's default ordering.
    static func ranked(_ apps: [CatalogApp]) -> [CatalogApp] {
        apps.sorted { lhs, rhs in
            if lhs.isVerified != rhs.isVerified { return lhs.isVerified }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func matchRank(_ name: String, _ needle: String) -> Int? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        guard let range = name.range(of: needle, options: options) else { return nil }
        if range.lowerBound == name.startIndex { return 0 }
        let preceding = name[name.index(before: range.lowerBound)]
        return preceding.isLetter || preceding.isNumber ? 2 : 1
    }

    // MARK: Data

    private static func entry(
        _ id: String,
        _ displayName: String,
        _ urlScheme: String,
        _ sfSymbol: String,
        _ category: Category,
        verified: Bool = true,
        note: String? = nil
    ) -> CatalogApp {
        CatalogApp(
            id: id,
            displayName: displayName,
            urlScheme: urlScheme,
            sfSymbol: sfSymbol,
            category: category,
            isVerified: verified,
            note: note
        )
    }

    static let all: [CatalogApp] = [

        // MARK: Communication

        entry("phone", "Phone", "tel://", "phone.fill", .communication,
              verified: false,
              note: "tel: is documented for dialing a number; bare tel:// only opens the keypad on some iOS versions."),
        entry("messages", "Messages", "sms://", "message.fill", .communication),
        entry("mail", "Mail", "mailto:", "envelope.fill", .communication,
              note: "Opens a new message — Mail publishes no scheme for the inbox."),
        entry("facetime", "FaceTime", "facetime://", "video.fill", .communication,
              note: "With a handle appended it places a call immediately."),
        entry("whatsapp", "WhatsApp", "whatsapp://", "bubble.left.fill", .communication),
        entry("telegram", "Telegram", "tg://", "paperplane.fill", .communication),
        entry("signal", "Signal", "sgnl://", "shield.fill", .communication),
        entry("messenger", "Messenger", "fb-messenger://", "ellipsis.bubble.fill", .communication),
        entry("discord", "Discord", "discord://", "bubble.left.and.bubble.right.fill", .communication),
        entry("slack", "Slack", "slack://", "number.square.fill", .communication),
        entry("teams", "Microsoft Teams", "msteams://", "person.3.fill", .communication),
        entry("zoom", "Zoom", "zoomus://", "person.2.fill", .communication),
        entry("gmail", "Gmail", "googlegmail://", "envelope.badge.fill", .communication),
        entry("outlook", "Outlook", "ms-outlook://", "envelope.open.fill", .communication),
        entry("spark", "Spark Mail", "readdle-spark://", "envelope.circle.fill", .communication),

        // MARK: Social

        entry("instagram", "Instagram", "instagram://", "camera.aperture", .social),
        entry("tiktok", "TikTok", "tiktok://", "music.note.tv.fill", .social,
              note: "The app also registers snssdk1233:// as a fallback."),
        entry("x", "X (Twitter)", "twitter://", "at", .social,
              note: "The X app still registers the legacy twitter:// scheme."),
        entry("threads", "Threads", "barcelona://", "at.circle.fill", .social,
              note: "barcelona:// is the app's shipping scheme — a leftover from its codename."),
        entry("facebook", "Facebook", "fb://", "person.2.circle.fill", .social),
        entry("reddit", "Reddit", "reddit://", "text.bubble.fill", .social),
        entry("snapchat", "Snapchat", "snapchat://", "camera.viewfinder", .social),
        entry("pinterest", "Pinterest", "pinterest://", "pin.fill", .social),
        entry("linkedin", "LinkedIn", "linkedin://", "briefcase.fill", .social),
        entry("bereal", "BeReal", "bereal://", "bell.badge.fill", .social,
              verified: false,
              note: "Community-reported; not published by the vendor."),

        // MARK: Music & media

        entry("applemusic", "Music", "music://", "music.note", .music),
        entry("spotify", "Spotify", "spotify://", "music.note.list", .music),
        entry("soundcloud", "SoundCloud", "soundcloud://", "waveform", .music),
        entry("pandora", "Pandora", "pandora://", "dot.radiowaves.left.and.right", .music),
        entry("shazam", "Shazam", "shazam://", "magnifyingglass.circle.fill", .music,
              verified: false,
              note: "Widely used but undocumented since the Apple acquisition."),
        entry("podcasts", "Podcasts", "podcasts://", "mic.fill", .music),
        entry("overcast", "Overcast", "overcast://", "dot.radiowaves.right", .music),
        entry("pocketcasts", "Pocket Casts", "pktc://", "antenna.radiowaves.left.and.right", .music),
        entry("audible", "Audible", "audible://", "headphones", .music,
              verified: false,
              note: "Community-reported; Amazon documents no launch scheme."),
        entry("youtube", "YouTube", "youtube://", "play.rectangle.fill", .music),
        entry("youtubemusic", "YouTube Music", "youtubemusic://", "play.circle.fill", .music,
              verified: false,
              note: "Community-reported."),
        entry("netflix", "Netflix", "nflx://", "popcorn.fill", .music),
        entry("twitch", "Twitch", "twitch://", "play.tv.fill", .music),
        entry("hulu", "Hulu", "hulu://", "film.fill", .music,
              verified: false,
              note: "Community-reported."),
        entry("disneyplus", "Disney+", "disneyplus://", "wand.and.stars", .music,
              verified: false,
              note: "Community-reported."),
        entry("max", "Max", "hbomax://", "star.circle.fill", .music,
              verified: false,
              note: "Legacy HBO Max scheme; may have changed with the Max rebrand."),
        entry("primevideo", "Prime Video", "aiv://", "rectangle.stack.fill", .music,
              verified: false,
              note: "Community-reported."),
        entry("appletv", "TV", "videos://", "sparkles.tv.fill", .music,
              verified: false,
              note: "Inherited from the old Videos app; unreliable on recent iOS."),
        entry("books", "Books", "ibooks://", "book.fill", .music),
        entry("kindle", "Kindle", "kindle://", "books.vertical.fill", .music),
        entry("news", "News", "applenews://", "newspaper.fill", .music),

        // MARK: Productivity

        entry("notes", "Notes", "mobilenotes://", "note.text", .productivity),
        entry("reminders", "Reminders", "x-apple-reminderkit://", "checklist", .productivity),
        entry("calendar", "Calendar", "calshow://", "calendar", .productivity),
        entry("notion", "Notion", "notion://", "doc.text.fill", .productivity),
        entry("todoist", "Todoist", "todoist://", "checkmark.circle.fill", .productivity),
        entry("things", "Things", "things://", "checkmark.square.fill", .productivity),
        entry("bear", "Bear", "bear://", "pencil.and.outline", .productivity),
        entry("drafts", "Drafts", "drafts://", "square.and.pencil", .productivity),
        entry("obsidian", "Obsidian", "obsidian://", "diamond.fill", .productivity),
        entry("fantastical", "Fantastical", "fantastical2://", "calendar.badge.clock", .productivity),
        entry("omnifocus", "OmniFocus", "omnifocus://", "target", .productivity),
        entry("trello", "Trello", "trello://", "rectangle.grid.2x2.fill", .productivity),
        entry("asana", "Asana", "asana://", "flowchart.fill", .productivity,
              verified: false,
              note: "Community-reported."),
        entry("linear", "Linear", "linear://", "square.grid.3x3.fill", .productivity,
              verified: false,
              note: "Community-reported."),
        entry("figma", "Figma", "figma://", "paintbrush.pointed.fill", .productivity),
        entry("googledrive", "Google Drive", "googledrive://", "externaldrive.fill", .productivity),
        entry("dropbox", "Dropbox", "dropbox://", "shippingbox.fill", .productivity,
              verified: false,
              note: "Dropbox documents dbapi-2:// for API callbacks, not for launching."),
        entry("onedrive", "OneDrive", "ms-onedrive://", "cloud.fill", .productivity,
              verified: false,
              note: "Community-reported."),
        entry("github", "GitHub", "github://", "chevron.left.forwardslash.chevron.right", .productivity),
        entry("onepassword", "1Password", "onepassword://", "key.fill", .productivity),
        entry("chatgpt", "ChatGPT", "chatgpt://", "sparkles", .productivity,
              verified: false,
              note: "Community-reported; OpenAI publishes no scheme."),
        entry("claude", "Claude", "claude://", "sparkle", .productivity,
              verified: false,
              note: "Community-reported; Anthropic publishes no scheme."),
        entry("duolingo", "Duolingo", "duolingo://", "graduationcap.fill", .productivity,
              verified: false,
              note: "Community-reported."),

        // MARK: Photo & camera

        entry("camera", "Camera", "camera://", "camera.fill", .photo,
              verified: false,
              note: "Unreliable on modern iOS — Apple never published a Camera scheme. Prefer a Shortcuts action."),
        entry("photos", "Photos", "photos-redirect://", "photo.fill", .photo),
        entry("googlephotos", "Google Photos", "googlephotos://", "photo.on.rectangle.angled", .photo,
              verified: false,
              note: "Community-reported."),
        entry("lightroom", "Lightroom", "lightroom://", "slider.horizontal.below.rectangle", .photo,
              verified: false,
              note: "Community-reported."),
        entry("vsco", "VSCO", "vsco://", "camera.filters", .photo,
              verified: false,
              note: "Community-reported."),
        entry("halide", "Halide", "halide://", "camera.metering.spot", .photo,
              verified: false,
              note: "Community-reported."),

        // MARK: Travel & maps

        entry("applemaps", "Maps", "maps://", "map.fill", .travel),
        entry("googlemaps", "Google Maps", "comgooglemaps://", "mappin.and.ellipse", .travel),
        entry("waze", "Waze", "waze://", "arrow.triangle.turn.up.right.diamond.fill", .travel),
        entry("uber", "Uber", "uber://", "car.fill", .travel),
        entry("lyft", "Lyft", "lyft://", "car.circle.fill", .travel),
        entry("airbnb", "Airbnb", "airbnb://", "bed.double.fill", .travel),
        entry("booking", "Booking.com", "booking://", "building.2.fill", .travel,
              verified: false,
              note: "Community-reported."),
        entry("tripit", "TripIt", "tripit://", "airplane", .travel,
              verified: false,
              note: "Community-reported."),
        entry("yelp", "Yelp", "yelp://", "star.bubble.fill", .travel),
        entry("opentable", "OpenTable", "opentable://", "fork.knife", .travel,
              verified: false,
              note: "Community-reported."),

        // MARK: Finance

        entry("wallet", "Wallet", "shoebox://", "wallet.pass.fill", .finance,
              verified: false,
              note: "shoebox:// is the legacy Passbook scheme; behaviour varies by iOS version."),
        entry("venmo", "Venmo", "venmo://", "dollarsign.circle.fill", .finance),
        entry("cashapp", "Cash App", "cashme://", "banknote.fill", .finance,
              verified: false,
              note: "cashme:// comes from the old cash.me branding; unconfirmed on current builds."),
        entry("paypal", "PayPal", "paypal://", "creditcard.fill", .finance),
        entry("robinhood", "Robinhood", "robinhood://", "chart.line.uptrend.xyaxis", .finance),
        entry("coinbase", "Coinbase", "coinbase://", "bitcoinsign.circle.fill", .finance),
        entry("chase", "Chase", "chase://", "building.columns.fill", .finance,
              verified: false,
              note: "Community-reported; banking apps change schemes often."),
        entry("stocks", "Stocks", "stocks://", "chart.bar.fill", .finance,
              verified: false,
              note: "Undocumented Apple scheme; unreliable on recent iOS."),
        entry("splitwise", "Splitwise", "splitwise://", "divide.circle.fill", .finance,
              verified: false,
              note: "Community-reported."),

        // MARK: Health & fitness

        entry("health", "Health", "x-apple-health://", "heart.fill", .health),
        entry("fitness", "Fitness", "fitness://", "figure.run", .health,
              verified: false,
              note: "Undocumented; the Fitness app has no published scheme."),
        entry("strava", "Strava", "strava://", "figure.run.circle.fill", .health),
        entry("nikerunclub", "Nike Run Club", "nikerunclub://", "shoeprints.fill", .health,
              verified: false,
              note: "Community-reported."),
        entry("myfitnesspal", "MyFitnessPal", "mfp://", "fork.knife.circle.fill", .health,
              verified: false,
              note: "Community-reported."),
        entry("headspace", "Headspace", "headspace://", "brain.head.profile", .health,
              verified: false,
              note: "Community-reported."),
        entry("calm", "Calm", "calm://", "moon.zzz.fill", .health,
              verified: false,
              note: "Community-reported."),
        entry("peloton", "Peloton", "peloton://", "bicycle", .health,
              verified: false,
              note: "Community-reported."),
        entry("fitbit", "Fitbit", "fitbit://", "heart.circle.fill", .health,
              verified: false,
              note: "Community-reported."),

        // MARK: Shopping & utilities

        entry("weather", "Weather", "weather://", "cloud.sun.fill", .utilities),
        entry("safari", "Safari", "x-web-search://", "safari.fill", .utilities,
              note: "Opens Safari focused on the search field — Safari has no plain launch scheme."),
        entry("chrome", "Chrome", "googlechrome://", "globe", .utilities),
        entry("amazon", "Amazon", "com.amazon.mobile.shopping://", "cart.fill", .utilities),
        entry("doordash", "DoorDash", "doordash://", "takeoutbag.and.cup.and.straw.fill", .utilities),
        entry("ubereats", "Uber Eats", "ubereats://", "bag.fill", .utilities),
        entry("grubhub", "Grubhub", "grubhub://", "fork.knife.circle.fill", .utilities,
              verified: false,
              note: "Community-reported."),
        entry("instacart", "Instacart", "instacart://", "cart.circle.fill", .utilities,
              verified: false,
              note: "Community-reported."),
        entry("starbucks", "Starbucks", "starbucks://", "cup.and.saucer.fill", .utilities,
              verified: false,
              note: "Community-reported."),
        entry("steam", "Steam", "steam://", "gamecontroller.fill", .utilities),
        entry("draftkings", "DraftKings", "draftkings://", "sportscourt.fill", .utilities,
              verified: false,
              note: "Community-reported."),
        entry("googletranslate", "Google Translate", "googletranslate://", "character.bubble.fill", .utilities,
              verified: false,
              note: "Community-reported."),

        // MARK: System

        entry("settings", "Settings", "App-Prefs://", "gearshape.fill", .system,
              verified: false,
              note: "prefs:// / App-Prefs:// is unsanctioned and has been blocked on and off since iOS 10. Expect it to fail."),
        entry("files", "Files", "shareddocuments://", "folder.fill", .system),
        entry("shortcuts", "Shortcuts", "shortcuts://", "square.stack.3d.up.fill", .system),
        entry("appstore", "App Store", "itms-apps://", "arrow.down.app.fill", .system),
        entry("clock", "Clock", "clock-alarm://", "alarm.fill", .system,
              verified: false,
              note: "Undocumented. clock-timer:// and clock-worldclock:// open other tabs."),
        entry("calculator", "Calculator", "calculator://", "plus.forwardslash.minus", .system,
              verified: false,
              note: "Calculator has never shipped a public scheme; this often does nothing."),
        entry("findmy", "Find My", "findmy://", "location.circle.fill", .system,
              verified: false,
              note: "Undocumented."),
        entry("home", "Home", "home://", "house.fill", .system,
              verified: false,
              note: "Undocumented."),
        entry("contacts", "Contacts", "contacts://", "person.crop.circle.fill", .system,
              verified: false,
              note: "Undocumented."),
        entry("voicememos", "Voice Memos", "voicememos://", "waveform.circle.fill", .system,
              verified: false,
              note: "Undocumented."),
    ]
}
