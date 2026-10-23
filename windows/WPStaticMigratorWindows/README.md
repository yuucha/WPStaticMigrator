# WP Static Migrator for Windows

既存のNode.js版WP Static Migratorを操作する、Windows 10/11向けのWPF GUIアプリです。

## ダウンロード

[WP Static Migrator for Windowsをダウンロード](https://github.com/yuucha/WPStaticMigrator/releases/latest/download/WP-Static-Migrator-v0.1.0-Windows-x64.zip)

Windows 10またはWindows 11の64ビット版に対応しています。

ZIPを展開すると、起動に必要な内容をまとめた `WP Static Migrator.exe` が入っています。

## 使い方

1. 配布ZIPをダウンロードして、任意のフォルダーへすべて展開します。
2. `WP Static Migrator.exe` を起動します。
3. 作業フォルダーを選択し、WordPressサイトのURLを入力します。
4. Node.js 22.23.4以上が見つからない場合は「アプリ専用領域へインストール」を選択します。

Node.jsは `%LOCALAPPDATA%\WPStaticMigrator\node\v22` に保存されます。OneDriveなどの作業フォルダーには保存せず、WindowsのPATH、レジストリ、システムのNode.js環境も変更しません。

サイトの作業フォルダーにはOneDrive同期フォルダーも選択できます。ただし、処理中にOneDriveがファイルを同期すると競合する可能性があるため、変換中は同期を一時停止するか、ローカルフォルダーの利用を推奨します。

プレビューは `127.0.0.1` のみに公開されます。既定URLは `http://127.0.0.1:8080/` です。
