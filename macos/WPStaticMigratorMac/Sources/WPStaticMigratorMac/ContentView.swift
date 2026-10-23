import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: MigratorModel

    var body: some View {
        ZStack {
            HSplitView {
                controls
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
                logPanel
                    .frame(minWidth: 480)
            }
            .background(Color(nsColor: .windowBackgroundColor))

            if model.isRunning || model.isInstallingNode {
                workingOverlay
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.isRunning || model.isInstallingNode)
        .alert("WP Static Migrator", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .alert("Node.jsが見つかりません", isPresented: $model.showsNodeInstallPrompt) {
            Button("作業フォルダへインストール") { model.installNodeInProject() }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("WP Static Migratorの実行にはNode.js 20以上が必要です。選択中の作業フォルダへインストールしますか？\n\nシステムのPATHやHomebrew環境は変更しません。")
        }
    }

    private var workingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(1.25)

                VStack(spacing: 7) {
                    Text(model.isInstallingNode ? "Node.jsを準備しています" : "処理を実行しています")
                        .font(.title2.weight(.semibold))
                    Text(model.status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if model.isRunning {
                    Button("処理を停止", role: .destructive) {
                        model.cancelCurrentOperation()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 42)
            .padding(.vertical, 34)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.separator.opacity(0.45))
            }
            .shadow(color: .black.opacity(0.14), radius: 24, y: 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.status)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("WP Static Migrator")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("WordPressサイトを静的HTMLへ移行")
                        .foregroundStyle(.secondary)
                }

                section("プロジェクト") {
                    Text(model.projectPath.isEmpty ? "作業フォルダが未選択です" : model.projectPath)
                        .font(.callout)
                        .foregroundStyle(model.projectPath.isEmpty ? .secondary : .primary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    HStack {
                        Button("フォルダを選択…") { model.chooseProjectFolder() }
                        Button("Finderで表示") { model.revealProject() }
                            .disabled(!model.hasProject)
                    }
                }

                section("新しいサイト") {
                    TextField("https://example.com/", text: $model.sourceURL)
                        .textFieldStyle(.roundedBorder)
                    if model.configurationMismatch {
                        Label("実行時に設定URLをこの入力内容へ更新します", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    } else if let configuredOrigin = model.configuredOrigin {
                        Label("設定済み: \(configuredOrigin)", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("空の作業フォルダを選び、取得するサイトのURLを入力してください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(model.configuredOrigin == nil ? "初期設定を作成" : "設定URLを更新") {
                        model.run(.initialize)
                    }
                        .disabled(!model.canInitialize || model.isRunning)
                }

                section("変換") {
                    operationButton("1  サイトを取得", systemImage: "arrow.down.doc", operation: .crawl)
                    operationButton("2  HTMLを生成", systemImage: "hammer", operation: .build)
                    operationButton("3  リンクを検証", systemImage: "checkmark.shield", operation: .validate)
                    Divider()
                    operationButton("すべて実行", systemImage: "play.fill", operation: .all, prominent: true)
                    if model.isRunning {
                        Button("現在の処理を停止", role: .destructive) { model.cancelCurrentOperation() }
                    }
                }

                section("プレビュー") {
                    HStack {
                        Text("ポート")
                        TextField("8080", text: $model.port)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Button(model.previewIsRunning ? "停止" : "起動") { model.togglePreview() }
                            .buttonStyle(.borderedProminent)
                            .tint(model.previewIsRunning ? .red : .accentColor)
                            .disabled(!model.hasProject)
                        Button("ブラウザで開く") { model.openPreview() }
                            .disabled(!model.previewIsRunning)
                    }
                    if model.previewIsRunning {
                        Label("127.0.0.1 で実行中", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(24)
        }
    }

    private var logPanel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("実行ログ").font(.headline)
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("消去") { model.clearLog() }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.log.isEmpty ? "ログはありません。" : model.log)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(model.log.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(18)
                    Color.clear.frame(height: 1).id("logEnd")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: model.log) { _, _ in proxy.scrollTo("logEnd", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func operationButton(
        _ title: String,
        systemImage: String,
        operation: MigratorModel.Operation,
        prominent: Bool = false
    ) -> some View {
        if prominent {
            Button { model.run(operation) } label: {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.hasProject || model.isRunning)
        } else {
            Button { model.run(operation) } label: {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(!model.hasProject || model.isRunning)
        }
    }
}
