import Foundation

/// The pure parts of Google Tasks: PKCE, the sign-in URL and callback, token replies, due dates and time zones, task parsing.
/// Made-up data only. No network, no Keychain.
func googleSelftest() {
    // PKCE S256: the example in RFC 7636, appendix B
    precondition(pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")

    // the sign-in URL carries what Google's installed-app flow needs
    let u = URLComponents(url: googleAuthURL(clientId: "cid.apps.googleusercontent.com", redirect: "http://127.0.0.1:5123", challenge: "ch", state: "st"), resolvingAgainstBaseURL: false)!
    let q = Dictionary(uniqueKeysWithValues: (u.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    precondition(u.scheme == "https" && u.host == "accounts.google.com" && u.path == "/o/oauth2/v2/auth")
    precondition(q["client_id"] == "cid.apps.googleusercontent.com" && q["redirect_uri"] == "http://127.0.0.1:5123" && q["response_type"] == "code")
    precondition(q["scope"] == "https://www.googleapis.com/auth/tasks" && q["code_challenge"] == "ch" && q["code_challenge_method"] == "S256" && q["state"] == "st")
    precondition(q["prompt"] == "consent")   // so a second sign-in (after a sign-out whose revoke failed) still gets a refresh token

    // the browser comes back to the loopback listener: a code only with our state; a refusal says why
    precondition(callbackResult("GET /?state=st&code=4/0Ab-x_y&scope=https://www.googleapis.com/auth/tasks HTTP/1.1", state: "st") == .code("4/0Ab-x_y"))
    precondition(callbackResult("GET /?state=evil&code=4/0Ab HTTP/1.1", state: "st") == .bad)   // CSRF: someone else's code
    precondition(callbackResult("GET /?error=access_denied&state=st HTTP/1.1", state: "st") == .denied("access_denied"))
    precondition(callbackResult("GET /favicon.ico HTTP/1.1", state: "st") == .bad)

    // token replies: a fresh one, a refresh (no new refresh token), revoked access, and anything else
    precondition(parseTokenReply(Data(#"{"access_token":"ya29.a","expires_in":3599,"refresh_token":"1//r","scope":"x","token_type":"Bearer"}"#.utf8), status: 200) == .ok(access: "ya29.a", expiresIn: 3599, refresh: "1//r"))
    precondition(parseTokenReply(Data(#"{"access_token":"ya29.b","expires_in":3599,"token_type":"Bearer"}"#.utf8), status: 200) == .ok(access: "ya29.b", expiresIn: 3599, refresh: nil))
    precondition(parseTokenReply(Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8), status: 400) == .revoked)
    precondition(parseTokenReply(Data(#"{"error":"invalid_client"}"#.utf8), status: 401) == .failed("invalid_client"))
    precondition(parseTokenReply(Data("<html>".utf8), status: 502) == .failed("HTTP 502"))

    // due dates are a day, stored as midnight UTC: the day must not move with your time zone (in Los Angeles a plain
    // conversion makes 18 Oct 00:00 UTC the 17th; in Kolkata or Auckland it stays the 18th either way)
    let tz = NSTimeZone.default
    for z in ["America/Los_Angeles", "Asia/Kolkata", "Pacific/Auckland", "UTC"] {
        NSTimeZone.default = TimeZone(identifier: z)!
        precondition(googleDay("2026-10-18T00:00:00.000Z") == "2026-10-18", z)
    }
    NSTimeZone.default = tz
    precondition(googleDay("2026-10-18T00:00:00Z") == "2026-10-18" && googleDay("soon") == nil && googleDay("2026-13-45T00:00:00.000Z") == nil)
    // ask Google for a day either side (it doesn't say whether dueMax counts), then keep exactly today
    precondition(dueWindow(today: "2026-10-18") == ("2026-10-17T00:00:00.000Z", "2026-10-19T00:00:00.000Z"))
    precondition(dueWindow(today: "2026-11-01") == ("2026-10-31T00:00:00.000Z", "2026-11-02T00:00:00.000Z"))

    // a page of tasks.list: open, done, no due date, hidden, deleted, no title, and the next page
    let page = Data(#"""
    {"kind":"tasks#tasks","nextPageToken":"p2","items":[
     {"id":"a","title":"Call the bank","status":"needsAction","due":"2026-10-18T00:00:00.000Z"},
     {"id":"b","title":"Done already","status":"completed","due":"2026-10-18T00:00:00.000Z","completed":"2026-10-18T08:00:00.000Z"},
     {"id":"c","title":"Someday","status":"needsAction"},
     {"id":"d","title":"Cleared","status":"completed","due":"2026-10-18T00:00:00.000Z","hidden":true},
     {"id":"e","title":"Gone","status":"needsAction","due":"2026-10-18T00:00:00.000Z","deleted":true},
     {"id":"f","title":"  ","status":"needsAction","due":"2026-10-18T00:00:00.000Z"},
     {"id":"g","title":"Yesterday's","status":"needsAction","due":"2026-10-17T00:00:00.000Z"},
     {"id":"h","title":"Tomorrow's","status":"needsAction","due":"2026-10-19T00:00:00.000Z"},
     {"id":"i","title":"Pay rent","status":"needsAction","due":"2026-10-18T00:00:00.000Z","parent":"a"}]}
    """#.utf8)
    let p = parseGoogleTasks(page, list: "L1")
    precondition(p.next == "p2" && p.tasks.count == 9 && p.tasks[0] == GTask(id: "a", list: "L1", title: "Call the bank", status: "needsAction", due: "2026-10-18T00:00:00.000Z"))
    precondition(p.tasks[3].hidden && p.tasks[4].deleted && p.tasks[2].due == nil)
    precondition(parseGoogleTasks(Data(#"{"kind":"tasks#tasks"}"#.utf8), list: "L1").tasks.isEmpty && parseGoogleTasks(Data("x".utf8), list: "L").next == nil)

    // today only: open, titled, due today, not hidden in Buddy until tomorrow
    let today = googleToday(p.tasks, today: "2026-10-18", snoozed: [:])
    precondition(today.map(\.text) == ["Call the bank", "Pay rent"] && today[0].gid == "a" && today[0].glist == "L1" && today[0].line.isEmpty)
    precondition(today[0].id == "g:a" && today[0].due.map(isoDay.string) == "2026-10-18")   // shows as "today" in your own time zone
    precondition(googleToday(p.tasks, today: "2026-10-18", snoozed: ["a": "2026-10-19"]).map(\.text) == ["Pay rent"])   // ☾ tomorrow
    precondition(googleToday(p.tasks, today: "2026-10-18", snoozed: ["a": "2026-10-18"]).count == 2)   // snoozed until today: back
    precondition(googleToday(p.tasks, today: "2026-10-19", snoozed: [:]).map(\.text) == ["Tomorrow's"])

    precondition(parseGoogleTasks(Data(#"{"items":[{"id":"L1","title":"My Tasks"},{"id":"L2","title":"Work"}]}"#.utf8), list: "").tasks.map(\.id) == ["L1", "L2"])   // tasklists.list has the same shape

    // a failed fetch waits 10 minutes like a good one (it retried every 30 s, all day); a new day fetches at once
    let t9 = Date(timeIntervalSince1970: 1_800_000_000)
    precondition(!googleDue(now: t9, last: t9.addingTimeInterval(-60), lastDay: "2026-10-18", today: "2026-10-18"))
    precondition(googleDue(now: t9, last: t9.addingTimeInterval(-600), lastDay: "2026-10-18", today: "2026-10-18"))
    precondition(googleDue(now: t9, last: t9.addingTimeInterval(-60), lastDay: "2026-10-17", today: "2026-10-18"))

    // the morning bubble: nothing when there is nothing; three names at most
    precondition(googleMorningText([]) == nil)
    precondition(googleMorningText(Array(today.prefix(1))) == "1 Google task today: Call the bank")
    let four = (1...4).map { Todo(text: "T\($0)", gid: "\($0)") }
    precondition(googleMorningText(four) == "4 Google tasks today:\n• T1\n• T2\n• T3\n+ 1 more")
}

/// Made-up Google tasks for --snapshot. Never real data.
func googleSamples() -> [Todo] {
    let today = Calendar.current.startOfDay(for: Date())
    return [Todo(text: "Renew the car insurance", due: today, gid: "s1", glist: "L"), Todo(text: "Send the slides to Priya", due: today, gid: "s2", glist: "L")]
}
