#!/usr/bin/env swift

import Darwin
import Foundation

var arguments = Array(CommandLine.arguments.dropFirst())
let testMode = arguments.first == "--test"
if testMode { arguments.removeFirst() }
guard arguments.count == 2, let descriptor = Int32(arguments[1]) else {
  fputs("usage: release_lock_validate.swift [--test] <lock-path> <fd>\n", stderr)
  exit(2)
}

let userID = getuid()
let expectedLock = "/private/tmp/io.github.tensornull.lexiray.release.\(userID)/lock"
let lockPath = arguments[0]
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
var parentInfo = stat()
var pathInfo = stat()
var descriptorInfo = stat()
let resolvedParent = realpath(parent, nil).map { String(cString: $0) } ?? ""
guard lstat(parent, &parentInfo) == 0,
      (parentInfo.st_mode & S_IFMT) == S_IFDIR,
      parentInfo.st_uid == userID,
      parentInfo.st_mode & 0o777 == 0o700,
      resolvedParent == parent
else {
  fputs(
    "inherited release lock parent is not private and canonical "
      + "(uid=\(parentInfo.st_uid), mode=\(String(parentInfo.st_mode & 0o777, radix: 8)), "
      + "resolved=\(resolvedParent), expected=\(parent))\n",
    stderr
  )
  exit(1)
}

guard lstat(lockPath, &pathInfo) == 0,
      (pathInfo.st_mode & S_IFMT) == S_IFREG,
      pathInfo.st_uid == userID,
      pathInfo.st_nlink == 1,
      pathInfo.st_mode & 0o777 == 0o600,
      fstat(descriptor, &descriptorInfo) == 0,
      (descriptorInfo.st_mode & S_IFMT) == S_IFREG,
      descriptorInfo.st_uid == userID,
      descriptorInfo.st_nlink == 1,
      pathInfo.st_dev == descriptorInfo.st_dev,
      pathInfo.st_ino == descriptorInfo.st_ino
else {
  fputs("inherited release lock fd is not the canonical regular lock file\n", stderr)
  exit(1)
}

guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
  fputs("inherited release lock fd does not retain the kernel lock\n", stderr)
  exit(1)
}
