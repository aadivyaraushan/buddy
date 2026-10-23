import Foundation

/// Buddy's logs: in ~/Library/Logs/Buddy, not /tmp, where another program could make the file first to read it or point it elsewhere.
func logsSelftest() {
    let logs = NSHomeDirectory() + "/Library/Logs/Buddy/"
    precondition([ghLogPath, saidLogPath, updateLogPath].allSatisfy { $0.hasPrefix(logs) })
    let fm = FileManager.default, ld = NSTemporaryDirectory() + "buddy-log-test-\(getpid())", lp = ld + "/sub/gh.log"
    try? fm.removeItem(atPath: ld)
    // made 0600 in a 0700 folder, and each line goes on the end
    appendPrivateLog(lp, "one\n"); appendPrivateLog(lp, "two\n")
    precondition((try? String(contentsOfFile: lp, encoding: .utf8)) == "one\ntwo\n")
    precondition((try? fm.attributesOfItem(atPath: lp)[.posixPermissions] as? Int) == 0o600)
    precondition((try? fm.attributesOfItem(atPath: ld + "/sub")[.posixPermissions] as? Int) == 0o700)
    // a symlink in its place is refused: nothing is written through it
    try? fm.removeItem(atPath: lp)
    try? fm.createSymbolicLink(atPath: lp, withDestinationPath: ld + "/target")
    appendPrivateLog(lp, "x\n"); precondition(openPrivateLog(lp) == nil && !fm.fileExists(atPath: ld + "/target"))
    // a hard link to another file of yours is refused too
    try? fm.removeItem(atPath: lp); fm.createFile(atPath: ld + "/other", contents: nil); try? fm.linkItem(atPath: ld + "/other", toPath: lp)
    appendPrivateLog(lp, "x\n"); precondition(openPrivateLog(lp) == nil && (try? Data(contentsOf: URL(fileURLWithPath: ld + "/other")))?.isEmpty == true)
    // a FIFO is refused, and does not hang
    try? fm.removeItem(atPath: lp); mkfifo(lp, 0o600)
    precondition(openPrivateLog(lp) == nil)
    // a symlinked folder is refused
    try? fm.removeItem(atPath: ld + "/sub"); try? fm.createDirectory(atPath: ld + "/real", withIntermediateDirectories: true)
    try? fm.createSymbolicLink(atPath: ld + "/sub", withDestinationPath: ld + "/real")
    precondition(openPrivateLog(lp) == nil && !fm.fileExists(atPath: ld + "/real/gh.log"))
    try? fm.removeItem(atPath: ld)
}
