#!/usr/bin/env swift

import Darwin
import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("usage: atomic_rename.swift <source-file> <destination-file>\n", stderr)
  exit(2)
}

let source = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]
guard source.hasPrefix("/"), destination.hasPrefix("/"),
      !source.contains("//"), !destination.contains("//"),
      !source.contains("/./"), !destination.contains("/./"),
      !source.contains("/../"), !destination.contains("/../")
else {
  fputs("atomic rename paths must be canonical absolute paths\n", stderr)
  exit(1)
}

let sourceParent = (source as NSString).deletingLastPathComponent
let destinationParent = (destination as NSString).deletingLastPathComponent

func lstatInfo(_ path: String) -> stat? {
  var info = stat()
  return lstat(path, &info) == 0 ? info : nil
}

guard sourceParent == destinationParent else {
  fputs("atomic rename requires one parent directory: \(sourceParent) != \(destinationParent)\n", stderr)
  exit(1)
}

guard let parentInfo = lstatInfo(sourceParent),
      (parentInfo.st_mode & S_IFMT) == S_IFDIR,
      realpath(sourceParent, nil).map({ String(cString: $0) }) == sourceParent
else {
  fputs("atomic rename parent must be a canonical non-symlink directory\n", stderr)
  exit(1)
}

guard let sourceInfo = lstatInfo(source), (sourceInfo.st_mode & S_IFMT) == S_IFREG else {
  fputs("atomic rename source must be a regular file\n", stderr)
  exit(1)
}

if let destinationInfo = lstatInfo(destination), (destinationInfo.st_mode & S_IFMT) != S_IFREG {
  fputs("atomic rename destination must be absent or a regular file\n", stderr)
  exit(1)
}

guard Darwin.rename(source, destination) == 0 else {
  perror("rename")
  exit(1)
}
