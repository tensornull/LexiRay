#!/usr/bin/swift

import CryptoKit
import Foundation
import LocalAuthentication
import Security

guard CommandLine.arguments.count == 3 else {
  exit(2)
}

let expectedName = CommandLine.arguments[1]
let expectedFingerprint = CommandLine.arguments[2].uppercased()
let context = LAContext()
context.interactionNotAllowed = true

let certificateQuery: [CFString: Any] = [
  kSecClass: kSecClassCertificate,
  kSecMatchLimit: kSecMatchLimitAll,
  kSecReturnRef: true,
  kSecUseAuthenticationContext: context
]
var certificateResult: CFTypeRef?
guard SecItemCopyMatching(certificateQuery as CFDictionary, &certificateResult) == errSecSuccess else {
  exit(1)
}

guard let certificates = certificateResult as? [SecCertificate] else {
  exit(1)
}

guard let certificate = certificates.first(where: { certificate in
  let name = SecCertificateCopySubjectSummary(certificate) as String? ?? ""
  let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
    .map { String(format: "%02X", $0) }
    .joined()
  return name == expectedName && digest == expectedFingerprint
}),
  let publicKey = SecCertificateCopyKey(certificate),
  let publicAttributes = SecKeyCopyAttributes(publicKey) as? [CFString: Any],
  let applicationLabel = publicAttributes[kSecAttrApplicationLabel]
else {
  exit(1)
}

let privateKeyQuery: [CFString: Any] = [
  kSecClass: kSecClassKey,
  kSecAttrKeyClass: kSecAttrKeyClassPrivate,
  kSecAttrApplicationLabel: applicationLabel,
  kSecReturnRef: true,
  kSecUseAuthenticationContext: context
]
var privateKeyResult: CFTypeRef?
guard SecItemCopyMatching(privateKeyQuery as CFDictionary, &privateKeyResult) == errSecSuccess,
      let privateKeyResult,
      CFGetTypeID(privateKeyResult) == SecKeyGetTypeID()
else {
  exit(1)
}

let privateKey = unsafeDowncast(privateKeyResult, to: SecKey.self)

let algorithms: [SecKeyAlgorithm] = [
  .rsaSignatureMessagePKCS1v15SHA256,
  .ecdsaSignatureMessageX962SHA256
]
guard let algorithm = algorithms.first(where: {
  SecKeyIsAlgorithmSupported(privateKey, .sign, $0)
}) else {
  exit(1)
}

var error: Unmanaged<CFError>?
let payload = Data("LexiRay non-interactive release signing probe".utf8) as CFData
guard SecKeyCreateSignature(privateKey, algorithm, payload, &error) != nil else {
  exit(1)
}

exit(0)
