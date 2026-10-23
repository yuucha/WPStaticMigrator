import AppKit
import SwiftUI

struct AboutView: View {
    private let githubURL = URL(string: "https://github.com/yuucha/WPStaticMigrator")!

    var body: some View {
        VStack(spacing: 18) {
            appIcon
                .frame(width: 112, height: 112)

            VStack(spacing: 4) {
                Text("WPStaticMigrator")
                    .font(.title.bold())
                Text("バージョン 0.1.0")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 11) {
                aboutRow("作者", value: "yuucha")
                aboutRow("ライセンス", value: "MIT")
                GridRow(alignment: .top) {
                    Text("オープンソース")
                        .foregroundStyle(.secondary)
                    Text("Node.js、Cheerio、Handlebars、およびnpm依存パッケージ（MIT・BSD・ISCライセンス等）")
                        .fixedSize(horizontal: false, vertical: true)
                }
                GridRow {
                    Text("GitHub")
                        .foregroundStyle(.secondary)
                    Link("github.com/yuucha/WPStaticMigrator", destination: githubURL)
                }
            }
            .font(.callout)
            .frame(maxWidth: 440)

            Divider()

            Text("Copyright © 2026 yuucha")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 540)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let url = Bundle.main.url(forResource: "AppIcon-master", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
        }
    }

    private func aboutRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

struct AboutCommandButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("WPStaticMigratorについて") {
            openWindow(id: "about")
        }
    }
}
