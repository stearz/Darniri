#!/usr/bin/env swift
import CryptoKit
import Foundation
import Security

// Export exactly one certificate/private-key pair, never the whole Keychain.
// The password is read from a private file so it cannot appear in arguments.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

let environment = ProcessInfo.processInfo.environment
guard let fingerprint = environment["DARNIRI_EXPORT_IDENTITY_SHA1"],
      fingerprint.count == 40, fingerprint.allSatisfy(\.isHexDigit),
      let passwordPath = environment["DARNIRI_P12_PASSWORD_FILE"],
      let outputPath = environment["DARNIRI_P12_OUTPUT_FILE"],
      outputPath.hasPrefix("/"), !FileManager.default.fileExists(atPath: outputPath)
else {
    fail("Set DARNIRI_EXPORT_IDENTITY_SHA1, DARNIRI_P12_PASSWORD_FILE, and a new absolute DARNIRI_P12_OUTPUT_FILE.")
}

let password = try String(contentsOfFile: passwordPath, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard !password.isEmpty else { fail("The P12 export password must not be empty.") }
let query: [CFString: Any] = [
    kSecClass: kSecClassIdentity,
    kSecReturnRef: true,
    kSecMatchLimit: kSecMatchLimitAll
]
var result: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &result)
guard status == errSecSuccess, let identities = result as? [SecIdentity] else {
    fail("Cannot find Keychain identities (OSStatus \(status)).")
}

let matches = identities.filter { identity in
    var certificate: SecCertificate?
    guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
          let certificate else { return false }
    let data = SecCertificateCopyData(certificate) as Data
    let sha = Insecure.SHA1.hash(data: data).map { String(format: "%02X", $0) }.joined()
    return sha == fingerprint.uppercased()
}

guard matches.count == 1 else { fail("Expected exactly one identity matching the requested certificate.") }
let passphrase = password as CFString
var parameters = SecItemImportExportKeyParameters()
parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
parameters.passphrase = Unmanaged.passUnretained(passphrase)
var exported: CFData?
let exportStatus = SecItemExport(matches[0], .formatPKCS12, [], &parameters, &exported)
guard exportStatus == errSecSuccess, let exported else {
    fail("Cannot export the selected identity (OSStatus \(exportStatus)).")
}

// Restrict access before writing any private bytes.
let output = URL(fileURLWithPath: outputPath)
guard FileManager.default.createFile(
    atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]
) else { fail("Cannot create private P12 output.") }
let handle = try FileHandle(forWritingTo: output)
try handle.write(contentsOf: exported as Data)
try handle.close()
print("Selected identity exported to the private output file.")
