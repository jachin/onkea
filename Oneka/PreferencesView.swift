import SwiftUI

struct PreferencesView: View {
    @AppStorage(EditorColorScheme.appStorageKey) private var selectedSchemeID = EditorColorScheme.defaultPreset.id
    @AppStorage(PostDatePreferences.autoUpdateLastModifiedKey) private var autoUpdateLastModified = PostDatePreferences.autoUpdateLastModifiedDefault
    @AppStorage(HugoDateTimeFormat.appStorageKey) private var selectedDateTimeFormatID = HugoDateTimeFormat.defaultFormat.rawValue

    private var selectedScheme: EditorColorScheme {
        EditorColorScheme.preset(withID: selectedSchemeID)
    }

    private var selectedDateTimeFormat: HugoDateTimeFormat {
        HugoDateTimeFormat.from(appStorageValue: selectedDateTimeFormatID)
    }

    var body: some View {
        TabView {
            editorAppearancePane
                .tabItem {
                    Label("Editor", systemImage: "paintpalette")
                }

            postDatesPane
                .tabItem {
                    Label("Dates", systemImage: "calendar.badge.clock")
                }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var editorAppearancePane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Editor Appearance")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                Text("Color Scheme")
                    .font(.headline)

                Picker("Color Scheme", selection: $selectedSchemeID) {
                    ForEach(EditorColorScheme.allPresets) { scheme in
                        Text(scheme.name).tag(scheme.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 220, alignment: .leading)

                Text(selectedScheme.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            themePreview(for: selectedScheme)

            Spacer()
        }
        .padding(24)
    }

    private var postDatesPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Post Dates")
                .font(.title2.weight(.semibold))

            Toggle("Automatically update last modified dates on save", isOn: $autoUpdateLastModified)

            VStack(alignment: .leading, spacing: 12) {
                Text("Date and Time Format")
                    .font(.headline)

                Picker("Date and Time Format", selection: $selectedDateTimeFormatID) {
                    ForEach(HugoDateTimeFormat.allCases) { format in
                        Text(format.title).tag(format.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)

                Text(selectedDateTimeFormat.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    labeledValue("Hugo layout", value: selectedDateTimeFormat.rawValue)
                    labeledValue("Example", value: selectedDateTimeFormat.sampleValue)
                }
                .font(.callout.monospaced())
            }

            Spacer()
        }
        .padding(24)
    }

    private func themePreview(for scheme: EditorColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 10) {
                previewLine("# Corn Maze Season", color: scheme.headingColor, weight: .semibold)
                previewLine("draft: true", color: scheme.frontMatterKeyColor)
                previewLine("[tickets](/visit-us)", color: scheme.linkColor)
                previewLine("> Peak color is late October.", color: scheme.quoteColor)
                previewLine("**Friday nights** now include live music.", color: scheme.strongColor)
                previewLine("`hugo server -D`", color: scheme.codeColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(nsColor: scheme.backgroundColor))
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }

    private func previewLine(_ text: String, color: NSColor, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.system(.body, design: .monospaced, weight: weight))
            .foregroundStyle(Color(nsColor: color))
    }

    private func labeledValue(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }
}

#Preview {
    PreferencesView()
}
