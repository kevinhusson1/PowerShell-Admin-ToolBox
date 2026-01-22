using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Navigation;
using System.Windows.Shapes;

namespace STB.Host;

/// <summary>
/// Interaction logic for MainWindow.xaml
/// </summary>
public partial class MainWindow : Window
{
    private STB.Core.Services.PowerShellEngine _psEngine;

    public MainWindow()
    {
        InitializeComponent();
        _psEngine = new STB.Core.Services.PowerShellEngine();
        Loaded += MainWindow_Loaded;
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        try 
        {
            await _psEngine.InitializeAsync();
            MessageBox.Show("PowerShell Engine Initialized!");
            
            // Auto-run test
            string scriptPath = System.IO.Path.GetFullPath(@"..\..\..\..\..\Scripts\test\hello.ps1");
            await _psEngine.ExecuteScriptAsync(scriptPath);
            MessageBox.Show("Script Executed Successfully!");
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Error: {ex.Message}");
        }
    }
}