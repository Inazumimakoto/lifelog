import Foundation
import XCTest
@testable import lifelify

final class PhotoLocationSelectionTests: XCTestCase {
    func testLocationSelectedDuringLookup_keepsChoiceAndUntouchedEquivalentLink() {
        let equivalentLocation = UUID()
        let newlySelectedLocation = UUID()

        let selection = PhotoLocationSelection.merge(resolvedIDs: [equivalentLocation],
                                                    selectedIDs: [newlySelectedLocation],
                                                    touchedIDs: [newlySelectedLocation])

        XCTAssertEqual(selection, [equivalentLocation, newlySelectedLocation])
    }

    func testLocationDeselectedDuringLookup_doesNotReselectIt() {
        let deselectedLocation = UUID()
        let untouchedLocation = UUID()

        let selection = PhotoLocationSelection.merge(resolvedIDs: [deselectedLocation, untouchedLocation],
                                                    selectedIDs: [],
                                                    touchedIDs: [deselectedLocation])

        XCTAssertEqual(selection, [untouchedLocation])
    }

    func testLocationToggledTwice_finalUserChoiceWins() {
        let restoredLocation = UUID()

        let selection = PhotoLocationSelection.merge(resolvedIDs: [],
                                                    selectedIDs: [restoredLocation],
                                                    touchedIDs: [restoredLocation])

        XCTAssertEqual(selection, [restoredLocation])
    }
}
