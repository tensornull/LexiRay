#!/usr/bin/env swift

import Darwin
import Foundation

var arguments = Array(CommandLine.arguments.dropFirst())
let testMode = arguments.first == "--test"
if testMode { arguments.removeFirst() }
guard arguments.count >= 2 else {
  fputs("usage: release_lock.swift [--test] <lock-path> <release-script> [arguments...]\n", stderr)
  exit(2)
}

let userID = getuid()
let expectedLock = "/private/tmp/io.github.tensornull.lexiray.release.\(userID)/lock"
let lockPath = arguments[0]
let scriptPath = URL(fileURLWithPath: arguments[1]).standardizedFileURL.path
guard lockPath.hasPrefix("/"),
      !lockPath.hasSuffix("/"),
      !lockPath.contains("//"),
      !lockPath.contains("/./"),
      !lockPath.contains("/../"),
      testMode || lockPath == expectedLock
else {
  fputs("release lock path is not canonical\n", stderr)
  exit(1)
}

let parent = URL(fileURLWithPath: lockPath).deletingLastPathComponent().path
if mkdir(parent, 0o700) != 0, errno != EEXIST {
  perror("mkdir release lock parent")
  exit(1)
}

var parentInfo = stat()
guard lstat(parent, &parentInfo) == 0,
      (parentInfo.st_mode & S_IFMT) == S_IFDIR,
      parentInfo.st_uid == userID,
      parentInfo.st_mode & 0o777 == 0o700,
      realpath(parent, nil).map({ String(cString: $0) }) == parent
else {
  fputs("release lock parent must be a private, user-owned canonical directory\n", stderr)
  exit(1)
}

let descriptor = open(lockPath, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
guard descriptor >= 0 else {
  perror("open release lock")
  exit(1)
}

var pathInfo = stat()
var descriptorInfo = stat()
guard lstat(lockPath, &pathInfo) == 0,
      (pathInfo.st_mode & S_IFMT) == S_IFREG,
      pathInfo.st_uid == userID,
      pathInfo.st_nlink == 1,
      fstat(descriptor, &descriptorInfo) == 0,
      (descriptorInfo.st_mode & S_IFMT) == S_IFREG,
      descriptorInfo.st_uid == userID,
      descriptorInfo.st_nlink == 1,
      pathInfo.st_dev == descriptorInfo.st_dev,
      pathInfo.st_ino == descriptorInfo.st_ino,
      fchmod(descriptor, 0o600) == 0
else {
  fputs("release lock must be a unique, user-owned regular file\n", stderr)
  close(descriptor)
  exit(1)
}

guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
  fputs("release: Another release command is active.\n", stderr)
  close(descriptor)
  exit(1)
}

guard dup2(descriptor, 9) == 9 else {
  perror("dup2 release lock")
  close(descriptor)
  exit(1)
}

if descriptor != 9 { close(descriptor) }
_ = fcntl(9, F_SETFD, 0)
setenv("LEXIRAY_RELEASE_LOCK_HELD", "1", 1)

var command = ["/bin/bash", scriptPath]
command.append(contentsOf: arguments.dropFirst(2))
let cArguments = command.map { strdup($0) } + [nil]
defer { cArguments.compactMap(\.self).forEach { free($0) } }
execv("/bin/bash", cArguments)
perror("exec release orchestrator")
exit(1)
