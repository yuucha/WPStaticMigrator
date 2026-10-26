using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Windows;
using System.Windows.Media;

namespace WPStaticMigratorWindows;

public enum Operation { Initialize, Crawl, Build, Validate, All, Preview }

public sealed class NodeNotFoundException : Exception
{
    public NodeNotFoundException() : base("Node.js 22.23.4以上が見つかりません。") { }
}

public sealed class MigratorViewModel : INotifyPropertyChanged, IDisposable
{
    public sealed class ValidationSummaryItem
    {
        [JsonPropertyName("category")] public string Category { get; set; } = "";
        [JsonPropertyName("label")] public string Label { get; set; } = "";
        [JsonPropertyName("count")] public int Count { get; set; }
    }
    private sealed class ValidationIssue
    {
        [JsonPropertyName("page")] public string Page { get; set; } = "";
        [JsonPropertyName("file")] public string File { get; set; } = "";
        [JsonPropertyName("categoryLabel")] public string CategoryLabel { get; set; } = "";
        [JsonPropertyName("type")] public string Type { get; set; } = "";
        [JsonPropertyName("value")] public string Value { get; set; } = "";
    }
    private sealed class ValidationReport
    {
        [JsonPropertyName("issueCount")] public int? IssueCount { get; set; }
        [JsonPropertyName("summary")] public List<ValidationSummaryItem> Summary { get; set; } = [];
        [JsonPropertyName("issues")] public List<ValidationIssue> Issues { get; set; } = [];
    }

    private string projectPath = "作業フォルダーが未選択です";
    private string sourceUrl = "";
    private string? configuredOrigin;
    private string port = "8080";
    private string log = "Windows用 WP Static Migrator を起動しました。\r\n";
    private string status = "準備完了";
    private string currentUrl = "";
    private bool isRunning;
    private bool isInstallingNode;
    private bool previewIsRunning;
    private Process? task;
    private Process? previewTask;
    private ValidationReport? validationReport;

    public event PropertyChangedEventHandler? PropertyChanged;
    public string ProjectPath { get => projectPath; private set => Set(ref projectPath, value); }
    public string SourceUrl { get => sourceUrl; set { if (Set(ref sourceUrl, value)) NotifyState(); } }
    public string Port { get => port; set => Set(ref port, value); }
    public string Log { get => log; set => Set(ref log, value); }
    public string Status { get => status; private set => Set(ref status, value); }
    public string CurrentUrl { get => currentUrl; private set => Set(ref currentUrl, value); }
    public bool HasProject => Directory.Exists(ProjectPath);
    public bool IsWorking => isRunning || isInstallingNode;
    public bool PreviewIsRunning => previewIsRunning;
    public bool CanRun => HasProject && !IsWorking;
    public bool CanInitialize => HasProject && NormalizeOrigin(SourceUrl) is not null && (!string.Equals(configuredOrigin, NormalizeOrigin(SourceUrl), StringComparison.OrdinalIgnoreCase));
    public string InitializeButtonTitle => configuredOrigin is null ? "初期設定を作成" : "設定URLを更新";
    public string PreviewButtonTitle => PreviewIsRunning ? "停止" : "起動";
    public Visibility WorkingVisibility => IsWorking ? Visibility.Visible : Visibility.Collapsed;
    public Visibility CancelVisibility => isRunning ? Visibility.Visible : Visibility.Collapsed;
    public string WorkingTitle => isInstallingNode ? "Node.jsを準備しています" : "処理を実行しています";
    public string ConfigurationNotice => configuredOrigin is null
        ? "空の作業フォルダーを選び、取得するサイトのURLを入力してください。"
        : CanInitialize ? "実行時に設定URLをこの入力内容へ更新します" : $"設定済み: {configuredOrigin}";
    public Brush ConfigurationNoticeBrush => CanInitialize ? Brushes.DodgerBlue : configuredOrigin is null ? Brushes.DimGray : Brushes.ForestGreen;
    public IReadOnlyList<ValidationSummaryItem> ValidationSummary => validationReport?.Summary ?? [];
    public int ValidationIssueCount => validationReport?.IssueCount ?? validationReport?.Issues.Count ?? 0;
    public bool HasValidationReport => validationReport is not null;
    public string ValidationReportNotice => HasValidationReport ? $"合計 {ValidationIssueCount}件" : "検証後に種類別の内訳を表示します";

    public void SelectProject(string path)
    {
        ProjectPath = path;
        LoadConfiguration();
        LoadValidationReport();
        NotifyState();
    }

    public async Task RunAsync(Operation operation)
    {
        if (operation == Operation.Preview) { await InstallNodeAsync(); return; }
        EnsureProject();
        if (operation == Operation.Initialize && configuredOrigin is not null)
        {
            if (!CanInitialize) throw new InvalidOperationException("このフォルダーは入力済みのURL用に設定されています。");
            await UpdateConfigurationAsync();
            return;
        }
        if (operation != Operation.Initialize && configuredOrigin is null)
            throw new InvalidOperationException("このフォルダーには初期設定がありません。先に初期設定を作成してください。");
        if (operation != Operation.Initialize && CanInitialize) await UpdateConfigurationAsync();

        var manifestPath = Path.Combine(ProjectPath, "src", "manifest.json");
        if (operation is Operation.Build or Operation.Validate && !File.Exists(manifestPath))
            throw new InvalidOperationException("サイト取得結果がありません。先に「1 サイトを取得」を実行してください。");
        if (operation == Operation.Validate && !Directory.Exists(Path.Combine(ProjectPath, "dist")))
            throw new InvalidOperationException("生成済みHTMLがありません。先に「2 HTMLを生成」を実行してください。");

        var node = FindNode();
        var cli = FindRuntimeFile("bin", "wp-static-migrator.js");
        var command = operation switch { Operation.Initialize => "init", Operation.Crawl => "crawl", Operation.Build => "build", Operation.Validate => "validate", _ => "all" };
        var args = new List<string> { cli, command };
        if (operation == Operation.Initialize) args.AddRange(["--url", SourceUrl]);
        args.AddRange(["--output", ProjectPath]);
        await RunProcessAsync(node, args, operation switch { Operation.Initialize => "初期設定", Operation.Crawl => "サイト取得", Operation.Build => "HTML生成", Operation.Validate => "検証", _ => "すべて実行" });
        if (operation == Operation.Initialize) LoadConfiguration();
        if (operation is Operation.Validate or Operation.All) LoadValidationReport();
    }

    public async Task TogglePreviewAsync()
    {
        if (PreviewIsRunning) { StopPreview(); return; }
        EnsureProject();
        if (!int.TryParse(Port, out var portNumber) || portNumber is < 1 or > 65535) throw new InvalidOperationException("ポート番号は1〜65535で入力してください。");
        var node = FindNode();
        var script = FindRuntimeFile("scripts", "preview.js");
        var info = CreateStartInfo(node, [script]);
        info.Environment["WPSM_WORKDIR"] = ProjectPath;
        info.Environment["WPSM_PORT"] = portNumber.ToString();
        previewTask = StartAttachedProcess(info, "[Preview] ");
        previewTask.EnableRaisingEvents = true;
        previewTask.Exited += (_, _) => Application.Current.Dispatcher.Invoke(() =>
        {
            previewIsRunning = false;
            previewTask?.Dispose(); previewTask = null;
            Status = "プレビューを終了しました";
            NotifyState();
        });
        previewIsRunning = true;
        Status = "プレビューを起動しました";
        AppendLog($"\r\n▶ Preview: http://127.0.0.1:{portNumber}/\r\n");
        NotifyState();
        await Task.Delay(600);
        OpenPreview();
    }

    public async Task InstallNodeAsync()
    {
        isInstallingNode = true; Status = "Node.jsをアプリ専用領域へインストール中…"; NotifyState();
        try
        {
            var architecture = Environment.Is64BitOperatingSystem ? "x64" : throw new PlatformNotSupportedException("64ビットWindowsのみ対応しています。");
            const string baseUrl = "https://nodejs.org/dist/latest-v22.x/";
            using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
            var checksums = await client.GetStringAsync(baseUrl + "SHASUMS256.txt");
            var suffix = $"-win-{architecture}.zip";
            var line = checksums.Split('\n').FirstOrDefault(value => value.TrimEnd().EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
                ?? throw new InvalidOperationException("Node.js 22のWindows配布ファイルが見つかりません。");
            var fields = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            var expectedHash = fields[0].ToLowerInvariant();
            var filename = fields[1];
            var runtime = AppNodeRoot;
            var archive = Path.Combine(runtime, filename);
            var staging = Path.Combine(runtime, "node-new");
            var destination = Path.Combine(runtime, "node");
            Directory.CreateDirectory(runtime);
            AppendLog($"\r\n▶ Node.js 22.23.4以上をアプリ専用領域へインストールします\r\n  {destination}\r\n");
            await using (var input = await client.GetStreamAsync(baseUrl + filename))
            await using (var output = File.Create(archive)) await input.CopyToAsync(output);
            await using (var file = File.OpenRead(archive))
            {
                var actualHash = Convert.ToHexString(await SHA256.HashDataAsync(file)).ToLowerInvariant();
                if (actualHash != expectedHash) throw new InvalidDataException("ダウンロードしたNode.jsのSHA-256検証に失敗しました。");
            }
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
            Directory.CreateDirectory(staging);
            ZipFile.ExtractToDirectory(archive, staging);
            var extracted = Directory.GetDirectories(staging).Single();
            if (Directory.Exists(destination)) Directory.Delete(destination, true);
            Directory.Move(extracted, destination);
            Directory.Delete(staging, true); File.Delete(archive);
            if (!File.Exists(Path.Combine(destination, "node.exe"))) throw new InvalidDataException("node.exeが見つかりません。");
            Status = "Node.jsのローカルインストールが完了しました";
            AppendLog($"✓ インストール完了: {Path.Combine(destination, "node.exe")}\r\n");
        }
        finally { isInstallingNode = false; NotifyState(); }
    }

    private async Task RunProcessAsync(string executable, IReadOnlyList<string> args, string title)
    {
        if (isRunning) return;
        AppendLog($"\r\n▶ {title}\r\n"); Status = $"{title}を実行中…"; CurrentUrl = ""; isRunning = true; NotifyState();
        try
        {
            task = StartAttachedProcess(CreateStartInfo(executable, args), "");
            await task.WaitForExitAsync();
            var exitCode = task.ExitCode;
            if (exitCode == 0) { Status = $"{title}が完了しました"; AppendLog($"\r\n✓ {title} 完了\r\n"); }
            else { Status = $"{title}で問題が見つかりました"; AppendLog($"\r\n⚠ 終了コード: {exitCode}\r\n"); }
        }
        finally { task?.Dispose(); task = null; CurrentUrl = ""; isRunning = false; NotifyState(); }
    }

    private Process StartAttachedProcess(ProcessStartInfo info, string prefix)
    {
        var process = new Process { StartInfo = info };
        process.OutputDataReceived += (_, e) => { if (e.Data is not null) Application.Current.Dispatcher.Invoke(() => { UpdateCurrentUrl(e.Data); AppendLog(prefix + e.Data + "\r\n"); }); };
        process.ErrorDataReceived += (_, e) => { if (e.Data is not null) Application.Current.Dispatcher.Invoke(() => { UpdateCurrentUrl(e.Data); AppendLog(prefix + e.Data + "\r\n"); }); };
        process.Start(); process.BeginOutputReadLine(); process.BeginErrorReadLine();
        return process;
    }

    private void UpdateCurrentUrl(string line)
    {
        if (!(line.StartsWith("[PAGE ") || line.StartsWith("[ASSET]") || line.StartsWith("[ERROR]") || line.StartsWith("[ASSET ERROR]"))) return;
        var closingBracket = line.IndexOf(']');
        if (closingBracket < 0) return;
        var value = line[(closingBracket + 1)..].TrimStart().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        if (value?.StartsWith("http://", StringComparison.OrdinalIgnoreCase) == true || value?.StartsWith("https://", StringComparison.OrdinalIgnoreCase) == true)
            CurrentUrl = value;
    }

    private ProcessStartInfo CreateStartInfo(string executable, IReadOnlyList<string> args)
    {
        var info = new ProcessStartInfo(executable) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true, WorkingDirectory = RuntimeRoot };
        foreach (var arg in args) info.ArgumentList.Add(arg);
        return info;
    }

    private static string RuntimeRoot => RuntimeBundle.ExtractIfNeeded();
    private string FindRuntimeFile(params string[] parts)
    {
        var path = RuntimeRoot;
        foreach (var part in parts) path = Path.Combine(path, part);
        return File.Exists(path) ? path : throw new FileNotFoundException("WP Static MigratorのCLIが見つかりません。配布版を再ビルドしてください。", path);
    }
    private string FindNode()
    {
        var local = Path.Combine(AppNodeRoot, "node", "node.exe");
        if (File.Exists(local) && NodeIsSupported(local)) return local;
        var system = FindOnPath("node.exe");
        if (system is not null && NodeIsSupported(system)) return system;
        throw new NodeNotFoundException();
    }
    private static bool NodeIsSupported(string path)
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo(path, "--version") { UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true });
            if (process is null) return false;
            var parts = process.StandardOutput.ReadToEnd().Trim().TrimStart('v').Split('.');
            return parts.Length >= 3
                && int.TryParse(parts[0], out var major)
                && int.TryParse(parts[1], out var minor)
                && int.TryParse(parts[2], out var patch)
                && new Version(major, minor, patch) >= new Version(22, 23, 4);
        }
        catch { return false; }
    }
    private static string? FindOnPath(string name) => (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator).Select(p => Path.Combine(p.Trim('"'), name)).FirstOrDefault(File.Exists);
    private static string AppNodeRoot => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "WPStaticMigrator", "node", "v22");

    private void LoadConfiguration()
    {
        try
        {
            var node = JsonNode.Parse(File.ReadAllText(Path.Combine(ProjectPath, "config.json")))?.AsObject();
            configuredOrigin = NormalizeOrigin(node?["origin"]?.GetValue<string>() ?? "");
            if (configuredOrigin is not null) { SourceUrl = configuredOrigin; Status = $"{configuredOrigin} のプロジェクトを選択しました"; }
            else Status = "新しいプロジェクトの保存先です";
        }
        catch { configuredOrigin = null; Status = "新しいプロジェクトの保存先です"; }
        NotifyState();
    }

    private async Task UpdateConfigurationAsync()
    {
        var origin = NormalizeOrigin(SourceUrl) ?? throw new InvalidOperationException("http:// または https:// で始まる正しいURLを入力してください。");
        var uri = new Uri(SourceUrl.Trim());
        var configPath = Path.Combine(ProjectPath, "config.json");
        var config = JsonNode.Parse(await File.ReadAllTextAsync(configPath))?.AsObject() ?? throw new InvalidDataException("config.jsonを読み込めません。");
        config["origin"] = origin;
        config["includeHosts"] = new JsonArray(uri.Host);
        config["startPaths"] = new JsonArray(string.IsNullOrEmpty(uri.AbsolutePath) ? "/" : uri.AbsolutePath);
        await File.WriteAllTextAsync(configPath, config.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + "\r\n");
        configuredOrigin = origin; SourceUrl = origin; Status = $"設定URLを {origin} に更新しました"; AppendLog($"\r\n✓ 設定URLを更新: {origin}\r\n"); NotifyState();
    }

    private void LoadValidationReport()
    {
        try
        {
            var reportPath = Path.Combine(ProjectPath, "logs", "validation.json");
            validationReport = File.Exists(reportPath)
                ? JsonSerializer.Deserialize<ValidationReport>(File.ReadAllText(reportPath))
                : null;
        }
        catch { validationReport = null; }
        NotifyState();
    }

    public void ExportValidationCsv(string destination)
    {
        if (validationReport is null) throw new InvalidOperationException("検証結果がありません。先に「3 リンクを検証」を実行してください。");
        static string Csv(string value) => $"\"{value.Replace("\"", "\"\"")}\"";
        var lines = new List<string> { "\"種類\",\"対象HTMLファイル\",\"ページURL\",\"問題\",\"参照先\"" };
        lines.AddRange(validationReport.Issues.Select(issue => string.Join(",", new[] {
            Csv(issue.CategoryLabel), Csv(issue.File), Csv(issue.Page), Csv(issue.Type), Csv(issue.Value)
        })));
        File.WriteAllText(destination, string.Join("\r\n", lines) + "\r\n", new UTF8Encoding(true));
        Status = $"CSVを書き出しました: {Path.GetFileName(destination)}";
    }

    private static string? NormalizeOrigin(string value)
    {
        if (!Uri.TryCreate(value.Trim(), UriKind.Absolute, out var uri) || (uri.Scheme != "http" && uri.Scheme != "https") || string.IsNullOrWhiteSpace(uri.Host)) return null;
        return uri.GetLeftPart(UriPartial.Authority).TrimEnd('/');
    }
    private void EnsureProject() { if (!HasProject) throw new InvalidOperationException("作業フォルダーを選択してください。"); }
    public void CancelCurrentOperation() { try { task?.Kill(true); AppendLog("\r\n停止を要求しました。\r\n"); } catch { } }
    private void StopPreview() { try { previewTask?.Kill(true); Status = "プレビューを停止しています…"; } catch { } }
    public void OpenPreview() { if (int.TryParse(Port, out var number)) Process.Start(new ProcessStartInfo($"http://127.0.0.1:{number}/") { UseShellExecute = true }); }
    public void RevealProject() { if (HasProject) Process.Start("explorer.exe", $"\"{ProjectPath}\""); }
    private void AppendLog(string value) => Log += value;
    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null) { if (EqualityComparer<T>.Default.Equals(field, value)) return false; field = value; OnPropertyChanged(name); return true; }
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    private void NotifyState() { foreach (var name in new[] { nameof(HasProject), nameof(CanRun), nameof(CanInitialize), nameof(InitializeButtonTitle), nameof(ConfigurationNotice), nameof(ConfigurationNoticeBrush), nameof(PreviewIsRunning), nameof(PreviewButtonTitle), nameof(WorkingVisibility), nameof(CancelVisibility), nameof(WorkingTitle), nameof(ValidationSummary), nameof(ValidationIssueCount), nameof(HasValidationReport), nameof(ValidationReportNotice) }) OnPropertyChanged(name); }
    public void Dispose() { try { task?.Kill(true); previewTask?.Kill(true); } catch { } task?.Dispose(); previewTask?.Dispose(); }
}

internal static class RuntimeBundle
{
    private const string ResourceName = "WPStaticMigratorWindows.RuntimeBundle.zip";
    private static readonly object Sync = new();
    private static string? extractedPath;

    public static string ExtractIfNeeded()
    {
        lock (Sync)
        {
            if (extractedPath is not null) return extractedPath;

            var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.1.0";
            var root = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "WPStaticMigrator", "runtime", version);
            var cli = Path.Combine(root, "bin", "wp-static-migrator.js");
            var defaultConfig = Path.Combine(root, "config.json");
            var defaultLayout = Path.Combine(root, "src", "layouts", "default.html");
            var marker = Path.Combine(root, ".ready");

            using var checksumStream = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName)
                ?? throw new InvalidOperationException("アプリ内のWP Static Migratorランタイムが見つかりません。");
            var bundleHash = Convert.ToHexString(SHA256.HashData(checksumStream));
            if (File.Exists(marker)
                && File.ReadAllText(marker).Trim() == bundleHash
                && File.Exists(cli)
                && File.Exists(defaultConfig)
                && File.Exists(defaultLayout))
            {
                extractedPath = root;
                return root;
            }

            var parent = Directory.GetParent(root)?.FullName
                ?? throw new InvalidOperationException("アプリ専用ランタイムの保存先を作成できません。");
            var staging = Path.Combine(parent, version + "-new");
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
            Directory.CreateDirectory(staging);

            using var bundle = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName)
                ?? throw new InvalidOperationException("アプリ内のWP Static Migratorランタイムが見つかりません。");
            ZipFile.ExtractToDirectory(bundle, staging);
            if (!File.Exists(Path.Combine(staging, "bin", "wp-static-migrator.js"))
                || !File.Exists(Path.Combine(staging, "config.json"))
                || !File.Exists(Path.Combine(staging, "src", "layouts", "default.html")))
                throw new InvalidDataException("アプリ内ランタイムを正しく展開できませんでした。");

            if (Directory.Exists(root)) Directory.Delete(root, true);
            Directory.Move(staging, root);
            File.WriteAllText(marker, bundleHash + "\r\n");
            extractedPath = root;
            return root;
        }
    }
}
