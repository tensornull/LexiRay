#!/usr/bin/env swift

import Darwin
import Foundation

var inputArguments = Array(CommandLine.arguments.dropFirst())
let testMode = inputArguments.first == "--test"
if testMode { inputArguments.removeFirst() }
guard inputArguments.count >= 2 else {
  fputs("usage: install_lock.swift [--test] <lock-path> <installer-script> [arguments...]\n", stderr)
  exit(2)
}

let expectedLock = "/Applications/.io.github.tensornull.lexiray.install.lock"
let lockPath = URL(fileURLWithPath: inputArguments[0]).standardizedFileURL.path
let scriptPath = URL(fileURLWithPath: inputArguments[1]).standardizedFileURL.path
guard testMode || lockPath == expectedLock else {
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

let descriptor = open(lockPath, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o666)
guard descriptor >= 0 else {
  perror("open install lock")
  exit(1)
}

var pathInfo = stat()
var descriptorInfo = stat()
guard lstat(lockPath, &pathInfo) == 0,
      (pathInfo.st_mode & S_IFMT) == S_IFREG,
      pathInfo.st_nlink == 1,
      fstat(descriptor, &descriptorInfo) == 0,
      (descriptorInfo.st_mode & S_IFMT) == S_IFREG,
      descriptorInfo.st_nlink == 1,
      pathInfo.st_dev == descriptorInfo.st_dev,
      pathInfo.st_ino == descriptorInfo.st_ino,
      fchmod(descriptor, 0o666) == 0
else {
  fputs("install lock must be a unique regular file\n", stderr)
  close(descriptor)
  exit(1)
}

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
guard fcntl(9, F_SETFD, 0) == 0 else {
  perror("clear install lock close-on-exec")
  close(9)
  exit(1)
}

setenv("LEXIRAY_INSTALL_LOCK_HELD", "1", 1)

var command = ["/bin/bash", scriptPath]
command.append(contentsOf: inputArguments.dropFirst(2))
let cArguments = command.map { strdup($0) } + [nil]
defer { cArguments.compactMap(\.self).forEach { free($0) } }
execv("/bin/bash", cArguments)
perror("exec installer")
exit(1)
