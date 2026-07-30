import AppKit
import UserNotifications

struct Search: Hashable {
    let type: String
    let ticket: String
    let category: String
    let camping: String
    let campingLabel: String

    var url: URL {
        var components = URLComponents(string: "https://tickets.pukkelpop.be/nl/meetup/demand/")!
        components.queryItems = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "camping", value: camping),
            URLQueryItem(name: "price", value: "all"),
            URLQueryItem(name: "cb", value: String(Date().timeIntervalSince1970))
        ]
        components.fragment = "tickets"
        return components.url!
    }
}

struct Row {
    let time: String
    let ticket: String
    let camping: String
    let result: String
    let url: URL
}

struct RequestResult {
    let search: Search
    let html: String
    let statusCode: Int
    let durationMs: Int
    let cacheStatus: String
    let age: String
    let errorDescription: String?
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, UNUserNotificationCenterDelegate {
    private let interval: TimeInterval = 20
    private var timer: DispatchSourceTimer?
    private var isChecking = false
    private var runNumber = 0
    private var rows: [Row] = []
    private var currentOfferURL: URL?
    private var activeOffers: [String: Row] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = [
            "Cache-Control": "no-cache, no-store, max-age=0",
            "Pragma": "no-cache"
        ]
        return URLSession(configuration: configuration)
    }()
    private var seen: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "seenOffers") ?? [])

    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    private let status = NSTextField(labelWithString: "Klaar om te controleren")
    private let startStop = NSButton(title: "Start controle", target: nil, action: nil)
    private let openPage = NSButton(title: "Open officiële Meet-up-pagina", target: nil, action: nil)
    private let clearLog = NSButton(title: "Wis overzicht", target: nil, action: nil)
    private let foundBanner = NSButton(title: "Nog geen ticket gevonden", target: nil, action: nil)
    private let vipLimit = NSTextField(string: "225")
    private let combiLimit = NSTextField(string: "250")
    private let friday = NSButton(checkboxWithTitle: "Vrijdag", target: nil, action: nil)
    private let saturday = NSButton(checkboxWithTitle: "Zaterdag", target: nil, action: nil)
    private let sunday = NSButton(checkboxWithTitle: "Zondag", target: nil, action: nil)
    private let combi = NSButton(checkboxWithTitle: "Combi", target: nil, action: nil)
    private let vip = NSButton(checkboxWithTitle: "VIP", target: nil, action: nil)
    private let about = NSButton(title: "About", target: nil, action: nil)
    private let openLogs = NSButton(title: "Open diagnostische logs", target: nil, action: nil)
    private let table = NSTableView()

    private var logDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Pukkelhack", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let buyAction = UNNotificationAction(identifier: "BUY_NOW", title: "Koop nu", options: [.foreground])
        let category = UNNotificationCategory(identifier: "TICKET_FOUND", actions: [buyAction], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        setupWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        beginMonitoring()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func setupWindow() {
        window.title = "Pukkelhack"
        window.center()
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let title = NSTextField(labelWithString: "Pukkelhack")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        let subtitle = NSTextField(wrappingLabelWithString: "Officiële Pukkelpop Meet-up monitor. Controleert elke 20 seconden; koopt nooit automatisch.")
        subtitle.textColor = .secondaryLabelColor

        startStop.target = self; startStop.action = #selector(toggleMonitoring)
        openPage.target = self; openPage.action = #selector(openOfficialPage)
        clearLog.target = self; clearLog.action = #selector(clearOverview)
        about.target = self; about.action = #selector(showAbout)
        openLogs.target = self; openLogs.action = #selector(revealLogs)
        foundBanner.target = self; foundBanner.action = #selector(openFoundTicket)
        foundBanner.isBordered = true
        foundBanner.bezelStyle = .rounded
        foundBanner.isEnabled = false
        foundBanner.font = .systemFont(ofSize: 16, weight: .semibold)
        foundBanner.contentTintColor = .secondaryLabelColor

        vipLimit.alignment = .right; vipLimit.maximumNumberOfLines = 1
        combiLimit.alignment = .right; combiLimit.maximumNumberOfLines = 1
        friday.state = .on; sunday.state = .on; combi.state = .on; vip.state = .on
        for box in [friday, saturday, sunday, combi, vip] {
            box.target = self; box.action = #selector(selectionChanged)
        }
        let selection = NSStackView(views: [
            NSTextField(labelWithString: "Zoek:"), friday, saturday, sunday, combi, vip
        ])
        selection.orientation = .horizontal; selection.spacing = 10
        let rules = NSStackView(views: [
            NSTextField(labelWithString: "Meld VIP tot €"), vipLimit,
            NSTextField(labelWithString: "• combi tot €"), combiLimit,
            NSTextField(labelWithString: "• camping is optioneel")
        ])
        rules.orientation = .horizontal; rules.spacing = 8

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        table.usesAlternatingRowBackgroundColors = true
        table.delegate = self; table.dataSource = self
        addColumn("Tijd", width: 80)
        addColumn("Ticket", width: 170)
        addColumn("Camping", width: 150)
        addColumn("Status", width: 330)
        addColumn("Kooplink", width: 110)
        scroll.documentView = table

        let buttons = NSStackView(views: [startStop, openPage, clearLog, openLogs, about])
        buttons.orientation = .horizontal; buttons.spacing = 10
        let stack = NSStackView(views: [title, subtitle, selection, rules, foundBanner, status, buttons, scroll])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 380),
            vipLimit.widthAnchor.constraint(equalToConstant: 55),
            combiLimit.widthAnchor.constraint(equalToConstant: 55)
        ])
    }

    private func addColumn(_ id: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = id; column.width = width
        table.addTableColumn(column)
    }

    @objc private func buyFromRow(_ sender: NSButton) {
        let row = sender.tag
        guard rows.indices.contains(row), rows[row].result.hasPrefix("BESCHIKBAAR") else { return }
        NSWorkspace.shared.open(freshURL(rows[row].url))
    }

    @objc private func toggleMonitoring() {
        if timer == nil {
            beginMonitoring()
        } else {
            timer?.cancel(); timer = nil
            startStop.title = "Start controle"
            status.stringValue = "Gepauzeerd"
        }
    }

    private func beginMonitoring() {
        guard timer == nil else { return }
        startStop.title = "Stop controle"
        status.stringValue = "Actief — eerste controle loopt nu"
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        source.schedule(deadline: .now(), repeating: interval, leeway: .seconds(1))
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async { self?.checkNow() }
        }
        timer = source
        source.resume()
    }

    @objc private func openOfficialPage() {
        NSWorkspace.shared.open(freshURL(URL(string: "https://tickets.pukkelpop.be/nl/meetup/demand")!))
    }

    @objc private func clearOverview() {
        rows.removeAll(); table.reloadData(); status.stringValue = "Overzicht gewist"
    }

    @objc private func selectionChanged() {
        activeOffers.removeAll()
        currentOfferURL = nil
        foundBanner.title = "Selectie aangepast — volgende controle loopt binnen 20 sec."
        foundBanner.isEnabled = false
        status.stringValue = "Selectie aangepast"
    }

    @objc private func showAbout() {
        let year = Calendar.current.component(.year, from: Date())
        let alert = NSAlert()
        alert.messageText = "Pukkelhack"
        alert.informativeText = "Built with respect for the festival and love for the music by Fillter | Filip De Clerck\n\nPukkelhack is een onafhankelijk, niet-officieel hobbyproject en is op geen enkele manier verbonden met Pukkelpop of de festivalorganisatie. De app is er niet om het festival in de weg te zitten, maar om mensen met een drukke dag wat rust te geven door het handmatige checken te verminderen.\n\nPukkelhack biedt nooit garantie op een ticket. Hopelijk helpt de app je wel op het juiste moment kijken. Aan iedereen die dankzij deze tool een ticket kan bemachtigen: heel veel plezier en een fantastisch festival! 🎉\n\n© \(year) All rights reserved."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func revealLogs() {
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([logDirectory])
    }

    @objc private func openFoundTicket() {
        guard let url = currentOfferURL else { return }
        NSWorkspace.shared.open(freshURL(url))
    }

    private func checkNow() {
        guard !isChecking else { return }
        isChecking = true
        let searches = selectedSearches()
        guard !searches.isEmpty else {
            isChecking = false
            status.stringValue = "Kies minstens één dag of Combi om te controleren"
            return
        }
        status.stringValue = "Controle bezig…"
        let group = DispatchGroup()
        let lock = NSLock()
        var responses: [RequestResult] = []

        for search in searches {
            group.enter()
            var request = URLRequest(url: search.url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            request.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            let started = Date()
            session.dataTask(with: request) { data, response, error in
                let http = response as? HTTPURLResponse
                let httpStatus = http?.statusCode ?? 0
                let html = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let headers = http?.allHeaderFields ?? [:]
                let cacheStatus = (headers["CF-Cache-Status"] ?? headers["X-Cache"] ?? "") as? String ?? ""
                let age = (headers["Age"] as? String) ?? ""
                let result = RequestResult(search: search, html: html, statusCode: httpStatus, durationMs: Int(Date().timeIntervalSince(started) * 1000), cacheStatus: cacheStatus, age: age, errorDescription: error?.localizedDescription)
                lock.lock(); responses.append(result); lock.unlock()
                group.leave()
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            self?.process(responses)
        }
    }

    private func selectedSearches() -> [Search] {
        var tickets: [(type: String, label: String, category: String)] = []
        let days: [(NSButton, String, String)] = [
            (friday, "day1", "Vrijdagticket"),
            (saturday, "day2", "Zaterdagticket"),
            (sunday, "day3", "Zondagticket")
        ]
        for (box, type, label) in days where box.state == .on {
            tickets.append((type, label, "normal"))
            if vip.state == .on { tickets.append(("vip_\(type)", "VIP \(label)", "vip")) }
        }
        if combi.state == .on {
            tickets.append(("combi", "Combiticket", "combi"))
            if vip.state == .on { tickets.append(("vip_combi", "VIP Combiticket", "combi")) }
        }
        let camping = [("n", "ZONDER camping"), ("a", "Camping CHILL"), ("b", "Camping RELAX")]
        return tickets.flatMap { ticket in
            camping.map { Search(type: ticket.type, ticket: ticket.label, category: ticket.category, camping: $0.0, campingLabel: $0.1) }
        }
    }

    private func process(_ responses: [RequestResult]) {
        let date = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        runNumber += 1
        writeDiagnostics(responses, at: date)
        var available = 0
        var currentlyAvailable: [String: Row] = [:]
        for response in responses {
            let search = response.search
            if !(200...299).contains(response.statusCode) {
                let detail = response.statusCode == 429 ? "Server vraagt om trager te controleren" : "Ophalen mislukt"
                add(Row(time: date, ticket: search.ticket, camping: search.campingLabel, result: detail, url: search.url))
                continue
            }
            let html = response.html
            let text = html.replacingOccurrences(of: "&euro;", with: "€").replacingOccurrences(of: "&#8364;", with: "€")
            guard let section = text.components(separatedBy: "id=\"tickets\"").dropFirst().first,
                  !section.contains("Geen tickets beschikbaar.") else {
                add(Row(time: date, ticket: search.ticket, camping: search.campingLabel, result: "Geen tickets", url: search.url))
                continue
            }
            let prices = prices(in: section)
            let eligible = prices.filter { eligiblePrice($0, category: search.category) }
            if eligible.isEmpty {
                add(Row(time: date, ticket: search.ticket, camping: search.campingLabel, result: "Beschikbaar, maar boven je limiet", url: search.url))
                continue
            }
            for price in eligible {
                available += 1
                let key = "\(search.type)|\(search.camping)|\(price)"
                let offer = Row(time: date, ticket: search.ticket, camping: search.campingLabel, result: "BESCHIKBAAR — \(price)", url: search.url)
                currentlyAvailable[key] = offer
                add(offer)
                currentOfferURL = search.url
                foundBanner.title = "🎟  Koop nu: \(search.ticket) — \(search.campingLabel) — \(price)"
                foundBanner.contentTintColor = .systemGreen
                foundBanner.isEnabled = true
                if seen.insert(key).inserted {
                    UserDefaults.standard.set(Array(seen), forKey: "seenOffers")
                    sendNotification(ticket: search.ticket, camping: search.campingLabel, price: price, url: search.url)
                }
            }
        }
        for (key, previous) in activeOffers where currentlyAvailable[key] == nil {
            add(Row(time: date, ticket: previous.ticket, camping: previous.camping, result: "Niet meer beschikbaar", url: previous.url))
        }
        activeOffers = currentlyAvailable
        isChecking = false
        if available > 0 {
            status.stringValue = "Run #\(runNumber) — \(date) — passende aanbieding gevonden; klik op ‘Koop nu’"
        } else {
            currentOfferURL = nil
            foundBanner.title = "Nog geen ticket gevonden"
            foundBanner.contentTintColor = .secondaryLabelColor
            foundBanner.isEnabled = false
            status.stringValue = "Run #\(runNumber) — \(date) — geen passende aanbieding (volgende controle binnen 20 sec.)"
        }
    }

    private func prices(in text: String) -> [String] {
        let pattern = "€\\s*[0-9]+(?:[,.][0-9]{1,2})?"
        let range = NSRange(text.startIndex..., in: text)
        return (try? NSRegularExpression(pattern: pattern).matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }) ?? []
    }

    private func cents(_ price: String) -> Int {
        let clean = price.replacingOccurrences(of: "€", with: "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return Int((Double(clean) ?? 0) * 100)
    }

    private func eligiblePrice(_ price: String, category: String) -> Bool {
        let limit: String
        switch category { case "vip": limit = vipLimit.stringValue; case "combi": limit = combiLimit.stringValue; default: return true }
        guard !limit.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        return cents(price) <= cents("€ \(limit)")
    }

    private func add(_ row: Row) { rows.insert(row, at: 0); table.reloadData() }

    private func writeDiagnostics(_ responses: [RequestResult], at displayTime: String) {
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            let stamp = formatter.string(from: Date())
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            let file = logDirectory.appendingPathComponent("pukkelhack-\(dayFormatter.string(from: Date())).jsonl")
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            let logFile = (attributes?[.size] as? NSNumber)?.intValue ?? 0 > 2_000_000
                ? logDirectory.appendingPathComponent("pukkelhack-\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")).jsonl")
                : file
            for result in responses {
                let item: [String: Any] = [
                    "timestamp": stamp,
                    "run": runNumber,
                    "ticket": result.search.ticket,
                    "camping": result.search.campingLabel,
                    "http_status": result.statusCode,
                    "duration_ms": result.durationMs,
                    "cache_status": result.cacheStatus,
                    "age": result.age,
                    "error": result.errorDescription ?? ""
                ]
                let data = try JSONSerialization.data(withJSONObject: item, options: [])
                if !FileManager.default.fileExists(atPath: logFile.path) { FileManager.default.createFile(atPath: logFile.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: logFile)
                try handle.seekToEnd()
                handle.write(data)
                handle.write(Data("\n".utf8))
                try handle.close()
            }
        } catch {
            status.stringValue = "Diagnostische log kon niet worden geschreven"
        }
    }

    private func freshURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter { $0.name != "cb" }
        items.append(URLQueryItem(name: "cb", value: String(Date().timeIntervalSince1970)))
        components.queryItems = items
        return components.url ?? url
    }

    private func sendNotification(ticket: String, camping: String, price: String, url: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Pukkelhack: ticket gevonden"
        content.body = "\(ticket) — \(camping) — \(price)"
        content.sound = .default
        content.categoryIdentifier = "TICKET_FOUND"
        content.userInfo = ["url": url.absoluteString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let value = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: value) {
            NSWorkspace.shared.open(freshURL(url))
        }
        completionHandler()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableColumn?.identifier.rawValue == "Kooplink" {
            let button = NSButton(title: rows[row].result.hasPrefix("BESCHIKBAAR") ? "Koop nu" : "Verlopen", target: self, action: #selector(buyFromRow(_:)))
            button.tag = row
            button.isEnabled = rows[row].result.hasPrefix("BESCHIKBAAR")
            button.bezelStyle = .rounded
            return button
        }
        let value: String
        switch tableColumn?.identifier.rawValue {
        case "Tijd": value = rows[row].time
        case "Ticket": value = rows[row].ticket
        case "Camping": value = rows[row].camping
        default: value = rows[row].result.hasPrefix("BESCHIKBAAR") ? "Actief — \(rows[row].result)" : rows[row].result
        }
        let cell = NSTextField(labelWithString: value)
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard row >= 0, rows[row].result.hasPrefix("BESCHIKBAAR") else {
            if row >= 0 { status.stringValue = "Alleen een rij met ‘BESCHIKBAAR’ opent een kooplink" }
            return
        }
        NSWorkspace.shared.open(freshURL(rows[row].url))
        table.deselectRow(row)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
