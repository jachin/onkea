import Foundation
import Testing
@testable import Oneka

struct PostDatePreferencesTests {
    @Test
    func hugoDateTimeFormatsExposeStableChoices() {
        let formats = HugoDateTimeFormat.allCases

        #expect(formats.count == 4)
        #expect(Set(formats.map(\.rawValue)).count == formats.count)
        #expect(HugoDateTimeFormat.defaultFormat == .rfc3339Offset)
        #expect(formats.allSatisfy { !$0.title.isEmpty })
        #expect(formats.allSatisfy { !$0.sampleValue.isEmpty })
    }

    @Test
    func fallsBackToDefaultFormatForUnknownStoredValue() {
        let format = HugoDateTimeFormat.from(appStorageValue: "invalid")

        #expect(format == .rfc3339Offset)
    }

    @Test
    func autoUpdateLastModifiedDefaultsToDisabled() {
        #expect(PostDatePreferences.autoUpdateLastModifiedDefault == false)
    }
}
