//
//  E2EEServiceTests.swift
//  lifelogTests
//

import XCTest
@testable import lifelify

/// E2EE の暗号化往復テスト。
/// 鍵は Keychain(シミュレータ)に作られる実物を使う — 暗号往復が
/// 壊れると既存ユーザーの手紙が読めなくなるため、最優先の回帰テスト。
final class E2EEServiceTests: XCTestCase {

    private var service: E2EEService { E2EEService.shared }

    /// 自分の公開鍵宛てに暗号化し、自分の秘密鍵で復号できる(文字列)
    func testEncryptDecryptMessageRoundtrip() throws {
        let publicKey = service.encodePublicKey(try service.getOrCreateKeyPair())
        let original = "未来のわたしへ。絵文字😊と改行\nも壊れないこと。"

        let encrypted = try service.encrypt(message: original, recipientPublicKey: publicKey)
        let decrypted = try service.decrypt(encryptedMessage: encrypted)

        XCTAssertEqual(decrypted, original)
    }

    /// バイナリデータ(写真相当)の往復
    func testEncryptDecryptDataRoundtrip() throws {
        let publicKey = service.encodePublicKey(try service.getOrCreateKeyPair())
        let original = Data((0..<4096).map { _ in UInt8.random(in: .min ... .max) })

        let encrypted = try service.encrypt(data: original, recipientPublicKey: publicKey)
        let decrypted = try service.decryptData(encryptedMessage: encrypted)

        XCTAssertEqual(decrypted, original)
    }

    /// Firestore 保存形式(シリアライズ文字列)を経由しても復号できる
    func testSerializeDeserializeRoundtrip() throws {
        let publicKey = service.encodePublicKey(try service.getOrCreateKeyPair())
        let original = "serialize roundtrip"

        let encrypted = try service.encrypt(message: original, recipientPublicKey: publicKey)
        let serialized = try service.serializeEncryptedMessage(encrypted)
        let restored = try service.deserializeEncryptedMessage(serialized)
        let decrypted = try service.decrypt(encryptedMessage: restored)

        XCTAssertEqual(decrypted, original)
    }

    /// 暗号文の改ざんは復号エラーになる(AES-GCM の認証タグ検証)
    func testTamperedCiphertextFailsToDecrypt() throws {
        let publicKey = service.encodePublicKey(try service.getOrCreateKeyPair())
        let encrypted = try service.encrypt(message: "tamper me", recipientPublicKey: publicKey)

        var serialized = try service.serializeEncryptedMessage(encrypted)
        // Base64 の途中の1文字を別の文字に差し替えて暗号文を壊す
        let index = serialized.index(serialized.startIndex, offsetBy: serialized.count / 2)
        let replacement: Character = serialized[index] == "A" ? "B" : "A"
        serialized.replaceSubrange(index...index, with: String(replacement))

        do {
            let restored = try service.deserializeEncryptedMessage(serialized)
            _ = try service.decrypt(encryptedMessage: restored)
            XCTFail("改ざんされた暗号文の復号が成功してしまった")
        } catch {
            // 期待どおり: デシリアライズか復号のどこかで必ず失敗する
        }
    }
}
