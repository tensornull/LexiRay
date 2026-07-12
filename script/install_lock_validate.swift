#!/usr/bin/env swift

import Darwin
import Foundation

var arguments = Array(CommandLine.arguments.dropFirst())
let testMode = arguments.first == "--test"
if testMode { arguments.removeFirst() }
guard arguments.count == 2, let descriptor = Int32(arguments[1]) else {
  fputs("usage: install_lock_validate.swift [--test] <lock-path> <fd>\n", stderr)
  exit(2)
}

let expectedLock = "/Applications/.io.github.tensornull.lexiray.install.lock"
let lockPath = URL(fileURLWithPath: arguments[0]).standardizedFileURL.path
guard testMode || lockPath == expectedLock else {
  fputs("install lock path is not canonical\n", stderr)
  exit(1)
}

var pathInfo = stat()
var descriptorInfo = stat()
guard lstat(lockPath, &pathInfo) == 0,
      (pathInfo.st_mode & S_IFMT) == S_IFREG,
      fstat(descriptor, &descriptorInfo) == 0,
      (descriptorInfo.st_mode & S_IFMT) == S_IFREG,
      pathInfo.st_dev == descriptorInfo.st_dev,
      pathInfo.st_ino == descriptorInfo.st_ino
else {
  fputs("inherited install lock fd does not identify the canonical regular lock file\n", stderr)
  exit(1)
}

guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
  fputs("INSTALL_ERROR: another LexiRay installation is active\n", stderr)
  exit(1)
}
