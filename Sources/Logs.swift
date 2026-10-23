import Foundation

/// Buddy's logs. Not in /tmp: there another program can make the file first, to read what Buddy writes or to point it at another file.
let logDir = NSHomeDirectory() + "/Library/Logs/Buddy"
let ghLogPath = logDir + "/gh.log"
let saidLogPath = logDir + "/said.log"
let updateLogPath = logDir + "/update.log"

/// A log file only you can read, or nil. Its folder is made 0700. Refuses a symlink, anything but a plain file, a file with
/// other links, or one you don't own, so another program can't pre-create it to read it or point it at another file.
func openPrivateLog(_ path: String) -> FileHandle? {
    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var ds = stat()
    guard lstat(dir, &ds) == 0, ds.st_mode & S_IFMT == S_IFDIR, ds.st_uid == getuid() else { return nil }   // not a symlink, and yours
    if ds.st_mode & 0o077 != 0 { chmod(dir, 0o700) }
    let fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)   // O_NONBLOCK: a FIFO there can't hang Buddy
    guard fd >= 0 else { return nil }
    var st = stat()
    guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_uid == getuid(), st.st_nlink == 1 else { close(fd); return nil }
    if st.st_mode & 0o077 != 0 { fchmod(fd, 0o600) }
    return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
}

/// One line on the end of a log from openPrivateLog; nothing if that refuses the file.
func appendPrivateLog(_ path: String, _ line: String) {
    openPrivateLog(path)?.write(line.data(using: .utf8)!)
}
