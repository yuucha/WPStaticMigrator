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
4. Node.jsが見つからない場合は「作業フォルダーへインストール」を選択します。

Node.jsは作業フォルダー内の `.wpsm\runtime\node` にのみ保存されます。WindowsのPATH、レジストリ、システムのNode.js環境は変更しません。

プレビューは `127.0.0.1` のみに公開されます。既定URLは `http://127.0.0.1:8080/` です。
