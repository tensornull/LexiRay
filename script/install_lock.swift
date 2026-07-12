#!/usr/bin/env swift

import Darwin
import Foundation

guard CommandLine.arguments.count >= 3 else {
  fputs("usage: install_lock.swift <lock-path> <installer-script> [arguments...]\n", stderr)
  exit(2)
}

let expectedLock = "/Applications/.io.github.tensornull.lexiray.install.lock"
let lockPath = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.path
let scriptPath = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL.path
guard lockPath == expectedLock else {
  fputs("production install lock path is not canonical\n", stderr)
  exit(1)
}

let parent = URL(fileURLWithPath: lockPath).deletingLastPathComponent().path
var parentInfo = stat()
guard lstat(parent, &parentInfo) == 0,
      (parentInfo.st_mode & S_IFMT) == S_IFDIR,
      realpath(parent, nil).map({ String(cString: $0) }) == parent
else {
  fputs("install lock parent must be a canonical non-symlink directory\n", stderr)
  exit(1)
}

let descriptor = open(lockPath, O_RDWR | O_CREAT | O_NOFOLLOW, 0o666)
guard descriptor >= 0 else {
  perror("open install lock")
  exit(1)
}

var lockInfo = stat()
guard fstat(descriptor, &lockInfo) == 0, (lockInfo.st_mode & S_IFMT) == S_IFREG else {
  fputs("install lock must be a regular file\n", stderr)
  close(descriptor)
  exit(1)
}

_ = fchmod(descriptor, 0o666)
guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
  fputs("INSTALL_ERROR: another LexiRay installation is active\n", stderr)
  close(descriptor)
  exit(1)
}

guard dup2(descriptor, 9) == 9 else {
  perror("dup2 install lock")
  close(descriptor)
  exit(1)
}

if descriptor != 9 { close(descriptor) }
_ = fcntl(9, F_SETFD, 0)
setenv("LEXIRAY_INSTALL_LOCK_HELD", "1", 1)

var arguments = ["/bin/bash", scriptPath]
arguments.append(contentsOf: CommandLine.arguments.dropFirst(3))
let cArguments = arguments.map { strdup($0) } + [nil]
defer { cArguments.compactMap(\.self).forEach { free($0) } }
execv("/bin/bash", cArguments)
perror("exec installer")
exit(1)
