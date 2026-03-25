import Testing
@testable import YouGoHugo

struct EditorColorSchemeTests {
    @Test
    func presetsHaveStableIdentityAndReadableMetadata() {
        let presets = EditorColorScheme.allPresets

        #expect(presets.count >= 5)
        #expect(Set(presets.map(\.id)).count == presets.count)
        #expect(Set(presets.map(\.name)).count == presets.count)
        #expect(presets.allSatisfy { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(presets.contains(EditorColorScheme.defaultPreset))
    }
}
