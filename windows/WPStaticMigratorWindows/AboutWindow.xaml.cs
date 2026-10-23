using System.Diagnostics;
using System.Windows;
using System.Windows.Input;

namespace WPStaticMigratorWindows;

public partial class AboutWindow : Window
{
    public AboutWindow() => InitializeComponent();
    private void CloseWindow(object sender, RoutedEventArgs e) => Close();
    private void OpenGitHub(object sender, MouseButtonEventArgs e) => Process.Start(new ProcessStartInfo("https://github.com/yuucha/WPStaticMigrator") { UseShellExecute = true });
}
