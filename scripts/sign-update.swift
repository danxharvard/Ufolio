// Signs a Hush update so installed copies can tell it really came from you.
//   HUSH_UPDATE_KEY=<base64 private key> swift scripts/sign-update.swift build/HushBrowser-1.0.0.zip
// Prints the signature (base64). The private key is never stored in the project: it lives in
// ~/.hush-update-signing-key on your Mac and as the HUSH_UPDATE_KEY secret on GitHub.
import CryptoKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: sign-update.swift <file>\n".utf8)); exit(2)
}
guard let text = ProcessInfo.processInfo.environment["HUSH_UPDATE_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty, let raw = Data(base64Encoded: text),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
    FileHandle.standardError.write(Data("HUSH_UPDATE_KEY is missing or invalid: releases must be signed.\n".utf8)); exit(1)
}
let file = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let signature = try key.signature(for: file)
print(signature.base64EncodedString())
