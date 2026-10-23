using Microsoft.Win32;
using System.Diagnostics;
using System.Windows;

namespace WPStaticMigratorWindows;

public partial class MainWindow : Window
{
    private readonly MigratorViewModel model = new();

    public MainWindow()
    {
        InitializeComponent();
        DataContext = model;
        Closed += (_, _) => model.Dispose();
    }

    private void ChooseProject(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "作業フォルダーを選択", Multiselect = false };
        if (dialog.ShowDialog() == true) model.SelectProject(dialog.FolderName);
    }

    private void RevealProject(object sender, RoutedEventArgs e) => model.RevealProject();
    private async void Initialize(object sender, RoutedEventArgs e) => await RunAsync(Operation.Initialize);
    private async void Crawl(object sender, RoutedEventArgs e) => await RunAsync(Operation.Crawl);
    private async void Build(object sender, RoutedEventArgs e) => await RunAsync(Operation.Build);
    private async void Validate(object sender, RoutedEventArgs e) => await RunAsync(Operation.Validate);
    private async void RunAll(object sender, RoutedEventArgs e) => await RunAsync(Operation.All);
    private async Task RunAsync(Operation operation)
    {
        try { await model.RunAsync(operation); }
        catch (NodeNotFoundException)
        {
            var answer = MessageBox.Show(
                "WP Static Migratorの実行にはNode.js 22.23.4以上が必要です。アプリ専用領域へインストールしますか？\n\nOneDriveなどの作業フォルダーには保存せず、システムのPATHやレジストリも変更しません。",
                "Node.jsが見つかりません", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (answer == MessageBoxResult.Yes)
            {
                try { await model.InstallNodeAsync(); }
                catch (Exception ex) { ShowError(ex); }
            }
        }
        catch (Exception ex) { ShowError(ex); }
    }

    private async void TogglePreview(object sender, RoutedEventArgs e)
    {
        try { await model.TogglePreviewAsync(); }
        catch (NodeNotFoundException)
        {
            var answer = MessageBox.Show(
                "WP Static Migratorの実行にはNode.js 22.23.4以上が必要です。アプリ専用領域へインストールしますか？\n\nOneDriveなどの作業フォルダーには保存せず、システムのPATHやレジストリも変更しません。",
                "Node.jsが見つかりません", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (answer == MessageBoxResult.Yes)
            {
                try { await model.InstallNodeAsync(); await model.TogglePreviewAsync(); }
                catch (Exception ex) { ShowError(ex); }
            }
        }
        catch (Exception ex) { ShowError(ex); }
    }

    private void OpenPreview(object sender, RoutedEventArgs e) => model.OpenPreview();
    private void ClearLog(object sender, RoutedEventArgs e) => model.Log = "";
    private void CancelOperation(object sender, RoutedEventArgs e) => model.CancelCurrentOperation();
    private void ShowAbout(object sender, RoutedEventArgs e) => new AboutWindow { Owner = this }.ShowDialog();
    private static void ShowError(Exception ex) => MessageBox.Show(ex.Message, "WP Static Migrator", MessageBoxButton.OK, MessageBoxImage.Error);
}
