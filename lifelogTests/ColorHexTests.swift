//
//  ColorHexTests.swift
//  lifelogTests
//

import XCTest
import SwiftUI
@testable import lifelify

/// 共有 ColorHex.swift の HEX パースを固定する。
/// 旧実装では ScheduleWidget の UIColor(hex:) だけが3桁HEXを弾いて
/// いたため、アプリとウィジェットで同じカテゴリ色が食い違っていた。
/// 3桁が CSS 慣習どおり展開されること、不正入力で nil になることを
/// 退行検知できるようにする。
final class ColorHexTests: XCTestCase {

    // UIColor へ変換して RGB 成分を 0..255 で取り出すヘルパ。
    private func rgb(_ hex: String, file: StaticString = #filePath, line: UInt = #line) -> (Int, Int, Int)? {
        guard let color = UIColor(hex: hex) else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            XCTFail("RGB 成分を取得できない", file: file, line: line)
            return nil
        }
        return (Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }

    func testSixDigitHex() {
        XCTAssertEqual(rgb("F97316").map { [$0.0, $0.1, $0.2] }, [0xF9, 0x73, 0x16])
        XCTAssertEqual(rgb("000000").map { [$0.0, $0.1, $0.2] }, [0, 0, 0])
        XCTAssertEqual(rgb("FFFFFF").map { [$0.0, $0.1, $0.2] }, [255, 255, 255])
    }

    func testThreeDigitHexExpandsPerCSS() {
        // #F00 → FF0000
        XCTAssertEqual(rgb("F00").map { [$0.0, $0.1, $0.2] }, [255, 0, 0])
        // #ABC → AABBCC
        XCTAssertEqual(rgb("ABC").map { [$0.0, $0.1, $0.2] }, [0xAA, 0xBB, 0xCC])
    }

    func testLeadingHashIsAccepted() {
        XCTAssertEqual(rgb("#F97316").map { [$0.0, $0.1, $0.2] }, [0xF9, 0x73, 0x16])
        XCTAssertEqual(rgb("#F00").map { [$0.0, $0.1, $0.2] }, [255, 0, 0])
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(UIColor(hex: ""))
        XCTAssertNil(UIColor(hex: "12345"))      // 桁数不正(5桁)
        XCTAssertNil(UIColor(hex: "GGGGGG"))     // 16進として不正
        XCTAssertNil(UIColor(hex: "ZZZ"))        // 3桁だが16進として不正
        XCTAssertNil(Color(hex: "12345"))
        XCTAssertNil(Color(hex: "nope"))
    }

    func testColorInitMatchesUIColorForThreeDigit() {
        // Color 側も同じ経路を通ることを確認(nil にならない)。
        XCTAssertNotNil(Color(hex: "F00"))
        XCTAssertNotNil(Color(hex: "#ABC"))
    }
}
