import XCTest
@testable import lifelify

final class ScheduleLinkTests: XCTestCase {
    func testOptionalEmptyInput_isValidAndStoresNoLink() {
        for value: String? in [nil, "", " \n "] {
            XCTAssertTrue(ScheduleLink.isValid(value))
            XCTAssertNil(ScheduleLink.url(from: value))
            XCTAssertNil(ScheduleLink.normalizedString(from: value))
        }
    }

    func testBareHostAndPort_addHTTPSWithoutChangingPathOrQuery() {
        for (input, expected) in [
            ("example.com/book?shop=hair#reservation", "https://example.com/book?shop=hair#reservation"),
            ("  example.com  ", "https://example.com"),
            ("example.com:8443/book", "https://example.com:8443/book"),
            ("localhost:8080/book", "https://localhost:8080/book"),
            ("127.0.0.1:8080/book", "https://127.0.0.1:8080/book")
        ] {
            XCTAssertEqual(ScheduleLink.normalizedString(from: input), expected)
            XCTAssertTrue(ScheduleLink.isValid(input))
        }
    }

    func testWebURLs_keepHTTPAndEncodedCharacters() {
        let inputs = ["https://example.com/reserve?q=a%20b&token=a%2Fb#time", "http://example.com:8080/book"]
        for input in inputs {
            XCTAssertEqual(ScheduleLink.normalizedString(from: input), input)
        }
        XCTAssertEqual(ScheduleLink.url(from: "HTTPS://example.com")?.scheme, "https")
        XCTAssertNotNil(ScheduleLink.url(from: "https://例え.テスト/予約"))
    }

    func testInvalidInputAndNonWebSchemes_cannotBeOpened() {
        for input in ["not a URL", "example", "https://", "https:///book", "https://example.com:99999",
                      "javascript:alert(1)", "file:///tmp/example", "mailto:shop@example.com", "tel:12345",
                      "https://example.com/line\nbreak", "https://exa mple.com", "https://."] {
            XCTAssertFalse(ScheduleLink.isValid(input), input)
            XCTAssertNil(ScheduleLink.url(from: input), input)
        }
    }
}
