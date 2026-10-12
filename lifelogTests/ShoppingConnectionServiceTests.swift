#if DEBUG
import XCTest
@testable import lifelify

final class ShoppingConnectionServiceTests: XCTestCase {
    @MainActor
    func testApprovalLink_requiresVerifiedHTTPSOriginAndExactOpaquePath() throws {
        let id = String(repeating: "A", count: 43)
        let base = "https://lifelify-connect-dev.inazumimakoto.workers.dev"
        XCTAssertEqual(ShoppingConnectionService.approvalID(from: try XCTUnwrap(URL(string: "\(base)/connect/\(id)"))), id)
        let invalid = [
            "http://lifelify-connect-dev.inazumimakoto.workers.dev/connect/\(id)",
            "lifelog://lifelify-connect-dev.inazumimakoto.workers.dev/connect/\(id)",
            "https://example.com/connect/\(id)",
            "https://lifelify-connect-dev.inazumimakoto.workers.dev.example.com/connect/\(id)",
            "https://user@lifelify-connect-dev.inazumimakoto.workers.dev/connect/\(id)",
            "https://lifelify-connect-dev.inazumimakoto.workers.dev:443/connect/\(id)",
            "\(base)/connect/\(id)?decision=approve", "\(base)/connect/\(id)#approve",
            "\(base)/connect/\(id)/", "\(base)/connect/\(id.dropLast())", "\(base)/connect/\(id)A",
            "\(base)/%63onnect/\(id)", "\(base)/connect/%41\(id.dropLast())",
            "\(base)/connect/\(String(repeating: "A", count: 42))+"
        ]
        for value in invalid {
            XCTAssertNil(ShoppingConnectionService.approvalID(from: try XCTUnwrap(URL(string: value))), value)
        }
    }

    @MainActor
    func testIncomingRequests_queueWithoutSigningInOrGrantingAccess() throws {
        let service = ShoppingConnectionService()
        let firstID = String(repeating: "A", count: 43)
        let secondID = String(repeating: "B", count: 43)
        let first = try XCTUnwrap(URL(string: "https://lifelify-connect-dev.inazumimakoto.workers.dev/connect/\(firstID)"))
        let second = try XCTUnwrap(URL(string: "https://lifelify-connect-dev.inazumimakoto.workers.dev/connect/\(secondID)"))
        XCTAssertTrue(service.handleApprovalURL(first))
        XCTAssertTrue(service.handleApprovalURL(first))
        XCTAssertTrue(service.handleApprovalURL(second))
        XCTAssertNil(service.accountID)
        XCTAssertNil(service.challenge)
        XCTAssertEqual(service.approvalRequestID, firstID)
        XCTAssertTrue(service.presentationRequested)
        XCTAssertFalse(service.handleApprovalURL(try XCTUnwrap(URL(string: "lifelog://connect/\(secondID)"))))
        XCTAssertEqual(service.approvalRequestID, firstID)
        service.dismissConnection()
        XCTAssertEqual(service.approvalRequestID, secondID)
        XCTAssertTrue(service.presentationRequested)
        service.dismissConnection()
        XCTAssertNil(service.approvalRequestID)
        XCTAssertFalse(service.presentationRequested)
    }
}
#endif
