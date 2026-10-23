# WP Static Migrator for Mac

既存のNode.js版WP Static Migratorを、ターミナル操作なしで利用するためのmacOSネイティブUIです。

## 必要環境

- macOS 14以降
- Node.js 22.23.4以降（未導入の場合は作業フォルダ内へインストール可能）
- アプリをビルドする場合はXcode 16以降

Node.jsが見つからない場合、アプリにインストール確認が表示されます。インストール先は選択したプロジェクトの `.wpsm/runtime/node/` です。システムのPATH、Homebrew、ほかのプロジェクトには影響しません。配布ファイルはNode.js公式サイトから取得し、公式のSHA-256値と照合してから展開します。

## 開発実行

リポジトリ直下で依存関係をインストールしてから実行します。

```bash
npm install
cd macos/WPStaticMigratorMac
swift run
```

## `.app` の作成

```bash
cd macos/WPStaticMigratorMac
./build-app.sh
```

`dist/WP Static Migrator.app` が生成されます。CLIとnpm依存関係はアプリへ同梱されますが、Node.js本体はMacにインストールされているものを使用します。

`Developer ID Application` 証明書がキーチェーンにある場合、ビルドスクリプトは自動的に証明書を選択し、Hardened Runtimeとセキュアタイムスタンプを付けて署名します。証明書がない場合のみローカル実行用のアドホック署名へフォールバックします。複数のDeveloper ID証明書がある場合は、環境変数 `CODESIGN_IDENTITY` で使用する証明書名を指定できます。

Developer ID署名後も、第三者へ配布する前にAppleのNotarizationとStaplingが必要です。

## 基本操作

1. 新規移行では空の作業フォルダを選び、WordPress URLを入力して「初期設定を作成」します。
2. 「すべて実行」または各工程のボタンを実行します。
3. 「プレビュー」を起動すると、既定ブラウザでローカルサイトが開きます。
4. 終了前にプレビューを停止します。
