#!/usr/bin/env swift

import Darwin
import Foundation

guard CommandLine.arguments.count == 4 || CommandLine.arguments.count == 6 else {
  fputs(
    "usage: atomic_replace.swift <staged-path> <destination-path> " +
      "absent|existing [expected-device expected-inode]\n",
    stderr
  )
  exit(2)
}

let staged = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]
let destinationExpectation = CommandLine.arguments[3]

struct ObjectIdentity: Equatable {
  let device: UInt64
  let inode: UInt64
  let fileType: mode_t
}

func objectIdentity(at path: String) -> ObjectIdentity? {
  var metadata = stat()
  guard lstat(path, &metadata) == 0 else { return nil }
  return ObjectIdentity(
    device: UInt64(metadata.st_dev),
    inode: UInt64(metadata.st_ino),
    fileType: metadata.st_mode & S_IFMT
  )
}

guard let stagedIdentity = objectIdentity(at: staged) else {
  fputs("staged path does not exist: \(staged)\n", stderr)
  exit(1)
}

guard stagedIdentity.fileType != S_IFLNK else {
  fputs("atomic replacement refuses a symbolic-link source\n", stderr)
  exit(1)
}

let stagedParent = URL(fileURLWithPath: staged).deletingLastPathComponent().standardizedFileURL.path
let destinationParent = URL(fileURLWithPath: destination).deletingLastPathComponent().standardizedFileURL.path
guard stagedParent == destinationParent else {
  fputs("atomic replacement requires staged and destination paths in one directory\n", stderr)
  exit(1)
}

let testFault = ProcessInfo.processInfo.environment["LEXIRAY_ATOMIC_REPLACE_TEST_FAULT"]
let testMode = ProcessInfo.processInfo.environment["LEXIRAY_INSTALL_TEST_MODE"] == "1"
if testMode, testFault == "before" {
  fputs("injected failure before atomic replacement\n", stderr)
  exit(86)
}

switch destinationExpectation {
case "absent":
  guard CommandLine.arguments.count == 4 else {
    fputs("absent destination mode does not accept object identity arguments\n", stderr)
    exit(2)
  }
  let status = staged.withCString { stagedPath in
    destination.withCString { destinationPath in
      renameatx_np(
        AT_FDCWD,
        stagedPath,
        AT_FDCWD,
        destinationPath,
        UInt32(RENAME_EXCL | RENAME_NOFOLLOW_ANY)
      )
    }
  }
  guard status == 0 else {
    perror("renameatx_np(RENAME_EXCL)")
    exit(1)
  }
case "existing":
  guard CommandLine.arguments.count == 6,
        let expectedDevice = UInt64(CommandLine.arguments[4]),
        let expectedInode = UInt64(CommandLine.arguments[5])
  else {
    fputs("existing destination mode requires numeric device and inode values\n", stderr)
    exit(2)
  }
  let expectedDestination = ObjectIdentity(
    device: expectedDevice,
    inode: expectedInode,
    fileType: S_IFDIR
  )
  guard objectIdentity(at: destination) == expectedDestination else {
    fputs("atomic replacement destination identity changed before exchange\n", stderr)
    exit(1)
  }
  let status = staged.withCString { stagedPath in
    destination.withCString { destinationPath in
      renameatx_np(
        AT_FDCWD,
        stagedPath,
        AT_FDCWD,
        destinationPath,
        UInt32(RENAME_SWAP | RENAME_NOFOLLOW_ANY)
      )
    }
  }
  guard status == 0 else {
    perror("renameatx_np(RENAME_SWAP)")
    exit(1)
  }

  let stagedAfterExchange = objectIdentity(at: staged)
  let destinationAfterExchange = objectIdentity(at: destination)
  if stagedAfterExchange != expectedDestination || destinationAfterExchange != stagedIdentity {
    var restored = false
    if destinationAfterExchange == stagedIdentity, let displacedIdentity = stagedAfterExchange {
      let restoreStatus = staged.withCString { stagedPath in
        destination.withCString { destinationPath in
          renameatx_np(
            AT_FDCWD,
            stagedPath,
            AT_FDCWD,
            destinationPath,
            UInt32(RENAME_SWAP | RENAME_NOFOLLOW_ANY)
          )
        }
      }
      restored = restoreStatus == 0 &&
        objectIdentity(at: staged) == stagedIdentity &&
        objectIdentity(at: destination) == displacedIdentity
    }
    if restored {
      fputs("atomic replacement destination changed during exchange; original names restored\n", stderr)
    } else {
      fputs("atomic replacement postcondition failed; all objects were preserved\n", stderr)
    }
    exit(1)
  }
default:
  fputs("destination mode must be absent or existing\n", stderr)
  exit(2)
}

guard objectIdentity(at: destination) == stagedIdentity else {
  fputs("atomic replacement destination does not contain the staged object\n", stderr)
  exit(1)
}

if destinationExpectation == "absent" {
  guard objectIdentity(at: staged) == nil else {
    fputs("exclusive atomic rename left the staged path behind\n", stderr)
    exit(1)
  }
} else {
  guard CommandLine.arguments.count == 6,
        let expectedDevice = UInt64(CommandLine.arguments[4]),
        let expectedInode = UInt64(CommandLine.arguments[5]),
        objectIdentity(at: staged) == ObjectIdentity(
          device: expectedDevice,
          inode: expectedInode,
          fileType: S_IFDIR
        )
  else {
    fputs("atomic exchange did not preserve the expected destination object\n", stderr)
    exit(1)
  }
}

if testMode, testFault == "after" {
  fputs("injected failure after atomic replacement\n", stderr)
  exit(87)
}
