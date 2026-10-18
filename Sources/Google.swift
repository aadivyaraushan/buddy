import AppKit
import CryptoKit
import Network
import SwiftUI

// MARK: Google Tasks (opt-in: right-click → Personal → Connect Google Tasks…). Shows your Google tasks due today in the to-do list.
// Off until you sign in: no Google call happens before that. You bring your own OAuth client (README → Google Tasks), so nothing
// secret is in this repo. Sign-in is Google's installed-app flow: PKCE, a one-time listener on 127.0.0.1, your browser.
// The client and the refresh token live in your login Keychain ("Buddy Google Tasks"); the access token only in memory.
// Sign out revokes the token at Google and deletes the Keychain item.

let googleScope = "https://www.googleapis.com/auth/tasks"   // read, and tick done
let googleKeychain = "Buddy Google Tasks"

/// One task from tasks.list. `due` is Google's RFC 3339 text: a day, stored as midnight UTC.
struct GTask: Equatable { var id, list, title, status: String; var due: String?; var hidden = false, deleted = false }
enum TokenReply: Equatable { case ok(access: String, expiresIn: Int, refresh: String?); case revoked; case failed(String) }
enum Callback: Equatable { case code(String); case denied(String); case bad }

// MARK: pure parts (checked by googleSelftest)

func base64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
func pkceChallenge(_ verifier: String) -> String { base64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }

func googleAuthURL(clientId: String, redirect: String, challenge: String, state: String) -> URL {
    var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    c.queryItems = [.init(name: "client_id", value: clientId), .init(name: "redirect_uri", value: redirect), .init(name: "response_type", value: "code"),
                    .init(name: "scope", value: googleScope), .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                    .init(name: "state", value: state), .init(name: "prompt", value: "consent")]
    return c.url!
}

/// The first line of the browser's request to the loopback listener → the code, Google's refusal, or not ours.
func callbackResult(_ requestLine: String, state: String) -> Callback {
    let parts = requestLine.split(separator: " ")
    guard parts.count >= 2, parts[0] == "GET", let c = URLComponents(string: "http://127.0.0.1" + parts[1]) else { return .bad }
    let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    guard q["state"] == state else { return .bad }
    if let e = q["error"] { return .denied(e) }
    return q["code"].map(Callback.code) ?? .bad
}

func parseTokenReply(_ data: Data, status: Int) -> TokenReply {
    let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    if status == 200, let a = o?["access_token"] as? String { return .ok(access: a, expiresIn: o?["expires_in"] as? Int ?? 3600, refresh: o?["refresh_token"] as? String) }
    if let e = o?["error"] as? String { return e == "invalid_grant" ? .revoked : .failed(e) }   // invalid_grant: expired or revoked; sign in again
    return .failed("HTTP \(status)")
}

/// "2026-10-18T00:00:00.000Z" → "2026-10-18". Read in UTC: it is a day, not a moment, so your time zone must not move it.
func googleDay(_ due: String) -> String? {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
    let day = String(due.prefix(10))
    return f.date(from: day).map(f.string) == day ? day : nil
}

/// dueMin / dueMax for tasks.list: a day either side of today. googleToday keeps exactly today.
func dueWindow(today: String) -> (min: String, max: String) {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
    let d = f.date(from: today) ?? Date()
    let s = { (n: Double) in f.string(from: d.addingTimeInterval(n * 86400)) + "T00:00:00.000Z" }
    return (s(-1), s(1))
}

/// One page of tasks.list or tasklists.list → items and the next page token.
func parseGoogleTasks(_ data: Data, list: String) -> (tasks: [GTask], next: String?) {
    guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ([], nil) }
    let items = (o["items"] as? [[String: Any]] ?? []).compactMap { t -> GTask? in
        guard let id = t["id"] as? String else { return nil }
        return GTask(id: id, list: list, title: t["title"] as? String ?? "", status: t["status"] as? String ?? "", due: t["due"] as? String,
                     hidden: t["hidden"] as? Bool ?? false, deleted: t["deleted"] as? Bool ?? false)
    }
    return (items, o["nextPageToken"] as? String)
}

/// Open tasks due on `today` (your local yyyy-MM-dd), minus the ones you put off ("☾ tomorrow": id → the day they come back).
func googleToday(_ tasks: [GTask], today: String, snoozed: [String: String]) -> [Todo] {
    tasks.filter { $0.status == "needsAction" && !$0.hidden && !$0.deleted && $0.due.flatMap(googleDay) == today
                   && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty && (snoozed[$0.id] ?? "") <= today }
        .map { Todo(text: $0.title.trimmingCharacters(in: .whitespaces), due: isoDay.date(from: today), gid: $0.id, glist: $0.list) }
}

func googleMorningText(_ todos: [Todo]) -> String? {
    guard let first = todos.first else { return nil }
    if todos.count == 1 { return "1 Google task today: \(first.text)" }
    return "\(todos.count) Google tasks today:\n" + todos.prefix(3).map { "• \($0.text)" }.joined(separator: "\n") + (todos.count > 3 ? "\n+ \(todos.count - 3) more" : "")
}

/// The small mark on a Google row, in the theme's quiet colour.
func googleMark(_ c: Color) -> some View { Image(systemName: "g.circle.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(c).help("From Google Tasks") }

// MARK: Keychain, through /usr/bin/security so a rebuilt Buddy reads it without a password prompt.
// The value goes in on stdin (security -i), never on a command line where `ps` could see it.

struct GoogleCreds: Codable { var clientId, clientSecret: String; var refresh: String }

func loadGoogleCreds() -> GoogleCreds? {
    guard let out = run("/usr/bin/security", ["find-generic-password", "-s", googleKeychain, "-a", "buddy", "-w"]),
          let b64 = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), let d = Data(base64Encoded: b64) else { return nil }
    return try? JSONDecoder().decode(GoogleCreds.self, from: d)
}
@discardableResult
func saveGoogleCreds(_ c: GoogleCreds) -> Bool {
    guard let d = try? JSONEncoder().encode(c) else { return false }
    let p = Process(), inp = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security"); p.arguments = ["-i"]
    p.standardInput = inp; p.standardOutput = Pipe(); p.standardError = Pipe()
    guard (try? p.run()) != nil else { return false }
    inp.fileHandleForWriting.write("add-generic-password -U -s \"\(googleKeychain)\" -a buddy -l \"\(googleKeychain)\" -w \"\(d.base64EncodedString())\"\n".data(using: .utf8)!)
    inp.fileHandleForWriting.closeFile(); p.waitUntilExit()
    return loadGoogleCreds()?.refresh == c.refresh
}
func deleteGoogleCreds() { run("/usr/bin/security", ["delete-generic-password", "-s", googleKeychain, "-a", "buddy"]) }

/// What Buddy did with Google, for when something goes wrong: events and HTTP codes only, never a token or a task. Readable by you only.
func glog(_ s: String) {
    let path = "/tmp/buddy.google.log", line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
    if let h = FileHandle(forWritingAtPath: path) ?? { FileManager.default.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600]); return FileHandle(forWritingAtPath: path) }() {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
    }
}

/// Time to ask Google again? Every 10 minutes, whether the last try worked or not, and at once on a new day.
func googleDue(now: Date, last: Date, lastDay: String, today: String) -> Bool { now.timeIntervalSince(last) >= 600 || lastDay != today }

// MARK: the connection

enum GErr: Error, Equatable { case offline, revoked, failed(String) }

/// Google state. `gq` does every network and Keychain call; the rest is main-thread only unless marked.
final class Google {
    static let shared = Google()
    let gq = DispatchQueue(label: "buddy.google")   // one call at a time: no two refreshes race
    var checked = false, signedIn = false   // signedIn is read from the Keychain once, on gq, at the first dayCare
    var hasClient = false                   // your OAuth client is in the Keychain (stays after access ends, until sign out)
    var epoch = 0                           // +1 on sign-in, sign-out and lost access: answers from before are dropped
    var raw: [GTask] = []                   // the last fetch, before today's filter
    var doneAt: [String: Date] = [:]        // ticked in Buddy: hidden until a fetch that started after Google said OK
    var lastFetch = Date.distantPast, fetchedDay = "", busy = false
    var access: String?, accessUntil = Date.distantPast   // gq only
    var listener: NWListener?

    /// POST a form, wait for the reply. nil data = no network.
    func post(_ url: String, _ form: [String: String]) -> (Data?, Int) {
        var r = URLRequest(url: URL(string: url)!, timeoutInterval: 15); r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        r.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        return send(r)
    }
    func send(_ r: URLRequest) -> (Data?, Int) {
        var out: (Data?, Int) = (nil, 0)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: r) { d, resp, _ in out = (d, (resp as? HTTPURLResponse)?.statusCode ?? 0); done.signal() }.resume()
        done.wait(); return out
    }

    /// A live access token, refreshed a minute before it runs out. On gq.
    func token() -> Result<String, GErr> {
        if let a = access, Date() < accessUntil { return .success(a) }
        guard let c = loadGoogleCreds(), !c.refresh.isEmpty else { return .failure(.revoked) }
        let (d, code) = post("https://oauth2.googleapis.com/token", ["client_id": c.clientId, "client_secret": c.clientSecret, "refresh_token": c.refresh, "grant_type": "refresh_token"])
        guard let d else { glog("refresh: no network"); return .failure(.offline) }
        switch parseTokenReply(d, status: code) {
        case let .ok(a, exp, _): access = a; accessUntil = Date().addingTimeInterval(Double(exp) - 60); glog("refresh: ok"); return .success(a)
        case .revoked: glog("refresh: invalid_grant (revoked or expired)"); return .failure(.revoked)
        case .failed(let e): glog("refresh: \(e)"); return .failure(.failed(e))
        }
    }

    /// One Tasks API call with the token; a 401 gets one fresh token and one retry. On gq.
    func api(_ method: String, _ url: URL, json: [String: Any]? = nil) -> Result<Data, GErr> {
        for attempt in 0..<2 {
            let t: String
            switch token() { case .success(let s): t = s; case .failure(let e): return .failure(e) }
            var r = URLRequest(url: url, timeoutInterval: 15); r.httpMethod = method
            r.setValue("Bearer " + t, forHTTPHeaderField: "Authorization")
            if let json { r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: json) }
            let (d, code) = send(r)
            guard let d else { glog("\(method) \(url.path): no network"); return .failure(.offline) }
            if code == 401 && attempt == 0 { access = nil; continue }
            guard (200..<300).contains(code) else { glog("\(method) \(url.path): HTTP \(code)"); return .failure(.failed("HTTP \(code)")) }
            return .success(d)
        }
        return .failure(.failed("HTTP 401"))
    }

    /// Every list's open tasks due within a day of today. On gq.
    func fetch(today: String) -> Result<[GTask], GErr> {
        let base = "https://tasks.googleapis.com/tasks/v1"
        var lists: [String] = [], page: String? = nil
        repeat {
            var c = URLComponents(string: base + "/users/@me/lists")!
            c.queryItems = [.init(name: "maxResults", value: "100")] + (page.map { [.init(name: "pageToken", value: $0)] } ?? [])
            switch api("GET", c.url!) {
            case .success(let d): let p = parseGoogleTasks(d, list: ""); lists += p.tasks.map(\.id); page = p.next
            case .failure(let e): return .failure(e)
            }
        } while page != nil
        let w = dueWindow(today: today)
        var all: [GTask] = []
        for l in lists {
            page = nil
            repeat {
                var c = URLComponents(string: base + "/lists/\(pathPart(l))/tasks")!
                c.queryItems = [.init(name: "dueMin", value: w.min), .init(name: "dueMax", value: w.max), .init(name: "showCompleted", value: "false"),
                                .init(name: "maxResults", value: "100")] + (page.map { [.init(name: "pageToken", value: $0)] } ?? [])
                switch api("GET", c.url!) {
                case .success(let d): let p = parseGoogleTasks(d, list: l); all += p.tasks; page = p.next
                case .failure(let e): return .failure(e)
                }
            } while page != nil
        }
        glog("fetch: \(lists.count) lists, \(all.count) tasks in the window")
        return .success(all)
    }
}
func pathPart(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? s }

extension Model {
    var googleSignedIn: Bool { Google.shared.signedIn }
    var googleHasClient: Bool { Google.shared.hasClient }

    /// "☾ tomorrow" on Google rows: id → the day it comes back. Kept in Buddy only; Google is not changed.
    private var googleSnoozed: [String: String] { UserDefaults.standard.dictionary(forKey: "bit.gsnooze") as? [String: String] ?? [:] }
    func showGoogle() {
        let g = Google.shared
        let t = googleToday(g.raw.filter { g.doneAt[$0.id] == nil }, today: isoDay.string(from: Date()), snoozed: googleSnoozed)
        if t != google { google = t }
    }

    /// From dayCare (every 30 s while you're at the Mac). First time: read the Keychain off the main thread. Then fetch every 10 minutes.
    func googleTick(_ now: Date) {
        let g = Google.shared, today = isoDay.string(from: now)
        if !g.checked {
            g.checked = true
            g.gq.async { let c = loadGoogleCreds(), on = !(c?.refresh ?? "").isEmpty; DispatchQueue.main.async { g.hasClient = c != nil; if on { g.signedIn = true; self.fetchGoogle() } } }
            return
        }
        guard g.signedIn, !g.busy, googleDue(now: now, last: g.lastFetch, lastDay: g.fetchedDay, today: today) else { return }
        fetchGoogle()
    }

    func fetchGoogle() {
        let g = Google.shared, today = isoDay.string(from: Date()), epoch = g.epoch, started = Date()
        g.busy = true; g.lastFetch = started; g.fetchedDay = today
        g.gq.async {
            let r = g.fetch(today: today)
            DispatchQueue.main.async {
                g.busy = false
                guard g.epoch == epoch else { return }   // signed out (or in again) meanwhile
                switch r {
                case .success(let t):
                    g.raw = t
                    g.doneAt = g.doneAt.filter { $0.value >= started }   // this fetch saw those ticks: Google has them
                    self.showGoogle()
                case .failure(.revoked): self.googleLost()
                case .failure(.offline): self.showGoogle()   // keep the last list; try again in 10 minutes, quietly
                case .failure(.failed(let e)):
                    self.showGoogle()
                    if Day.once("gtasks-error") {
                        let hint = e == "HTTP 403" ? " Is the Google Tasks API enabled in your Cloud project?" : e == "invalid_client" ? " Your OAuth client was deleted or its secret changed: sign out of Google Tasks, then connect again." : ""
                        self.say("Google Tasks isn't working (\(e)).\(hint) Details: /tmp/buddy.google.log", .calm, seconds: 20, kind: .ambient)
                    }
                }
            }
        }
    }

    /// The refresh token stopped working (you revoked Buddy, or it expired). Forget it, keep your client, say so once.
    func googleLost() {
        let g = Google.shared
        guard g.signedIn else { return }
        g.signedIn = false; g.epoch += 1; g.raw = []; g.doneAt = [:]; google = []
        g.gq.async { g.access = nil; if var c = loadGoogleCreds() { c.refresh = ""; saveGoogleCreds(c) } }
        say("Google Tasks stopped working: access ended or expired. Right-click → Personal → Connect Google Tasks… to sign in again.", .calm, seconds: 30, kind: .ambient)
    }

    func tickGoogle(_ t: Todo) {
        guard let id = t.gid, let list = t.glist else { return }
        let g = Google.shared, epoch = g.epoch
        g.doneAt[id] = .distantFuture; showGoogle(); celebrate += 1   // gone at once; back if Google says no
        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(pathPart(list))/tasks/\(pathPart(id))")!
        g.gq.async {
            let r = g.api("PATCH", url, json: ["status": "completed"])
            DispatchQueue.main.async {
                guard g.epoch == epoch else { return }
                switch r {
                case .success: glog("tick: ok"); g.doneAt[id] = Date()
                case .failure(.revoked): self.googleLost()
                case .failure: g.doneAt[id] = nil; self.showGoogle(); self.say("I couldn't mark \"\(t.text)\" done in Google. It's back on the list.", .calm, seconds: 10, kind: .ambient)
                }
            }
        }
    }

    func snoozeGoogle(_ t: Todo) {
        guard let id = t.gid else { return }
        let today = isoDay.string(from: Date())
        var s = googleSnoozed.filter { $0.value > today }   // drop ones that are back already
        s[id] = isoDay.string(from: Date().addingTimeInterval(86400))
        UserDefaults.standard.set(s, forKey: "bit.gsnooze"); showGoogle()
    }

    /// Once a day, 10:00–12:00, if Google has tasks for today. Privacy mode keeps it for later rather than spending it.
    func googleNudge(_ now: Date) -> Bool {
        let h = Calendar.current.component(.hour, from: now)
        guard !privacy, (10..<12).contains(h), let text = googleMorningText(google), Day.once("gtasks") else { return false }
        say(text, .calm, seconds: 30, kind: .ambient) { self.bubble = nil; self.tab = "personal"; self.showCard = true; self.onExpandChange?() }
        return true
    }

    /// Revoke at Google, delete the Keychain item (client and token). Also works after access was lost, to forget the client.
    func signOutGoogle() {
        let g = Google.shared
        g.signedIn = false; g.hasClient = false; g.epoch += 1; g.raw = []; g.doneAt = [:]; google = []
        g.gq.async {
            g.access = nil
            var revoked = true
            if let c = loadGoogleCreds(), !c.refresh.isEmpty {   // revoking the refresh token ends Buddy's access at Google too
                let code = g.post("https://oauth2.googleapis.com/revoke", ["token": c.refresh]).1
                glog("revoke: HTTP \(code)"); revoked = code == 200
            }
            deleteGoogleCreds()
            let gone = loadGoogleCreds() == nil
            glog("sign out: keychain item \(gone ? "deleted" : "NOT deleted")")
            DispatchQueue.main.async {
                var text = gone ? "Signed out of Google Tasks. I deleted the token from your Keychain." : "Signed out, but I couldn't delete the Keychain item \"\(googleKeychain)\". Delete it in Keychain Access."
                if !revoked { text += "\nI couldn't reach Google to revoke it: remove Buddy at myaccount.google.com/permissions." }
                self.say(text, .calm, seconds: 20, kind: .ambient)
            }
        }
    }

    /// Ask for your OAuth client (once), then sign in in your browser.
    func connectGoogle() {
        let saved = loadGoogleCreds()
        var c = saved ?? GoogleCreds(clientId: "", clientSecret: "", refresh: "")
        if c.clientId.isEmpty || c.clientSecret.isEmpty {
            guard let id = try? ask("Connect Google Tasks\n\nBuddy uses your own Google OAuth client, type \"Desktop app\". README → Google Tasks has the 5-minute setup.\n\nPaste the client ID:", "1234-abc.apps.googleusercontent.com"),
                  !id.isEmpty else { return }
            guard id.hasSuffix(".apps.googleusercontent.com") else { say("That doesn't look like a client ID. It ends in .apps.googleusercontent.com.", .calm, seconds: 10, kind: .ambient); return }
            guard let secret = try? ask("Now paste that client's secret.\nIt stays in your Keychain.", "GOCSPX-…"), !secret.isEmpty else { return }
            c = GoogleCreds(clientId: id, clientSecret: secret, refresh: "")
        }
        signInGoogle(c)
    }

    /// The installed-app flow: listen on 127.0.0.1 (any free port), open Google's page, take the code, swap it for tokens.
    func signInGoogle(_ c: GoogleCreds) {
        let g = Google.shared, lq = DispatchQueue(label: "buddy.google.listen")
        g.listener?.cancel()
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)   // loopback only: nothing else on the network can reach it
        guard let l = try? NWListener(using: params) else { glog("sign in: no listener"); say("I couldn't start the sign-in. Try again?", .calm, seconds: 10, kind: .ambient); return }
        g.listener = l
        var raw = Data(count: 32); _ = raw.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        let verifier = base64url(raw), state = UUID().uuidString
        var redirect = "", handled = false   // lq only
        func finish(_ text: String) { DispatchQueue.main.async { l.cancel(); if g.listener === l { g.listener = nil }; self.say(text, .calm, seconds: 12, kind: .ambient) } }
        l.stateUpdateHandler = { s in
            switch s {
            case .ready:
                guard let port = l.port?.rawValue else { return }
                redirect = "http://127.0.0.1:\(port)"
                glog("sign in: listening on port \(port)")
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(googleAuthURL(clientId: c.clientId, redirect: redirect, challenge: pkceChallenge(verifier), state: state))
                    self.say("Finish signing in to Google in your browser 🌐", .calm, seconds: 20, kind: .ambient)
                }
            case .failed(let e): glog("sign in: listener failed \(e)"); finish("The sign-in stopped. Try again?")
            default: break
            }
        }
        l.newConnectionHandler = { conn in
            conn.start(queue: lq)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
                let line = data.flatMap { String(data: $0, encoding: .utf8) }?.components(separatedBy: "\r\n").first ?? ""
                let page = { (code: Int, msg: String) in
                    let body = "<!doctype html><meta charset=utf-8><title>Buddy</title><body style=\"font:16px -apple-system;margin:4em;text-align:center\"><p>\(msg)</p>"
                    conn.send(content: "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)".data(using: .utf8),
                              completion: .contentProcessed { _ in conn.cancel() })
                }
                let result = handled ? .bad : callbackResult(line, state: state)
                switch result {
                case .bad: page(404, "Not found."); return   // the favicon, a stray request, or a repeat: keep waiting / ignore
                case .denied(let e): handled = true; glog("sign in: denied (\(e))"); page(200, "Sign-in cancelled. You can close this tab."); finish("Google sign-in cancelled.")
                case .code(let code):
                    handled = true; glog("sign in: got a code")
                    g.gq.async {
                        let (d, status) = g.post("https://oauth2.googleapis.com/token", ["client_id": c.clientId, "client_secret": c.clientSecret, "code": code,
                                                                                         "code_verifier": verifier, "grant_type": "authorization_code", "redirect_uri": redirect])
                        let fail = { (log: String, text: String) in glog("sign in: " + log); page(200, "Buddy couldn't finish the sign-in. See Buddy's bubble."); finish(text) }
                        guard let d else { fail("token exchange: no network", "I couldn't reach Google. Check your connection, then try again."); return }
                        switch parseTokenReply(d, status: status) {
                        case .ok(_, _, nil): fail("token exchange: ok, but no refresh token", "Google signed you in but gave no lasting token. Try again.")
                        case .revoked: fail("token exchange: invalid_grant", "Google didn't accept the sign-in code. Try again.")
                        case .failed(let e):
                            if e == "invalid_client" || e == "unauthorized_client" { deleteGoogleCreds(); DispatchQueue.main.async { g.hasClient = false } }   // a bad client: ask for it again next time
                            fail("token exchange: \(e)", "Google didn't accept the sign-in (\(e)). Check the client ID and secret, then try again.")
                        case let .ok(access, exp, refresh?):
                            var saved = c; saved.refresh = refresh
                            guard saveGoogleCreds(saved) else { fail("keychain save failed", "I couldn't save the token to your Keychain."); return }
                            g.access = access; g.accessUntil = Date().addingTimeInterval(Double(exp) - 60)
                            glog("sign in: ok")
                            page(200, "🐾 Buddy is connected to Google Tasks. You can close this tab.")
                            DispatchQueue.main.async { g.signedIn = true; g.hasClient = true; g.checked = true; g.epoch += 1; self.fetchGoogle() }
                            finish("Connected to Google Tasks ✓ Today's tasks show in your to-do list.")
                        }
                    }
                }
            }
        }
        l.start(queue: lq)
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { if g.listener === l { glog("sign in: timed out"); finish("The Google sign-in timed out. Try again when you're ready.") } }
    }
}
