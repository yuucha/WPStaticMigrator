# WP Static Migrator for Windows

既存のNode.js版WP Static Migratorを操作する、Windows 10/11向けのWPF GUIアプリです。

## 利用者向け

1. 配布ZIPをダウンロードして、任意のフォルダーへすべて展開します。
2. `WP Static Migrator.exe` を起動します。
3. 作業フォルダーを選択し、WordPressサイトのURLを入力します。
4. Node.jsが見つからない場合は「作業フォルダーへインストール」を選択します。

Node.jsは作業フォルダー内の `.wpsm\runtime\node` にのみ保存されます。WindowsのPATH、レジストリ、システムのNode.js環境は変更しません。

プレビューは `127.0.0.1` のみに公開されます。既定URLは `http://127.0.0.1:8080/` です。

## 開発・配布ビルド

必要な環境:

- Windows 10またはWindows 11（64ビット）
- .NET 8 SDK
- Node.js 20以上（配布物へのCLI依存ファイル収集に使用）
- PowerShell 5.1以上

リポジトリのルートから実行します。

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\WPStaticMigratorWindows\build-windows.ps1
```

生成物:

```text
windows\WPStaticMigratorWindows\dist\WP-Static-Migrator-v0.1.0-Windows-x64.zip
```

Windows PCが手元にない場合は、GitHubの **Actions → Build Windows app → Run workflow** から同じビルドを実行できます。完了後、実行結果のArtifacts欄にある `WP-Static-Migrator-Windows-x64` をダウンロードしてください。

配布ZIPには自己完結型.NETランタイム、WPFアプリ、既存CLI、CLIのnpm依存パッケージが入ります。Node.js本体は含めず、必要な場合だけ利用者が選択した作業フォルダーへ公式配布ZIPからインストールします。

## コード署名

現段階のWindows版は未署名です。一般配布前に、Windowsコード署名証明書を使って公開バイナリへ署名し、署名後のZIPをGitHub Releasesへ登録してください。署名されていないアプリではMicrosoft Defender SmartScreenの警告が表示される可能性があります。
