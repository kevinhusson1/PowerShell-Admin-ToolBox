using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;

namespace STB.Core.Services
{
    public interface IPowerShellEngine
    {
        Task InitializeAsync();
        Task ExecuteScriptAsync(string scriptPath, Dictionary<string, object> parameters = null);
        void StopAll();
    }

    public class PowerShellEngine : IPowerShellEngine, IDisposable
    {
        private RunspacePool? _runspacePool;
        private readonly int _minRunspaces = 2;
        private readonly int _maxRunspaces = 10;
        private bool _isInitialized;

        public PowerShellEngine()
        {
        }

        public async Task InitializeAsync()
        {
            if (_isInitialized) return;

            await Task.Run(() =>
            {
                var sessionState = InitialSessionState.CreateDefault();
                // Optimization: Set execution policy for the process scope to bypass
                sessionState.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;

                // Future: Add custom cmdlets from STB.Interop here
                // sessionState.Commands.Add(new SessionStateCmdletEntry("Write-AppLog", typeof(WriteAppLogCmdlet), ""));

                _runspacePool = RunspaceFactory.CreateRunspacePool(sessionState);
                _runspacePool.SetMinRunspaces(_minRunspaces);
                _runspacePool.SetMaxRunspaces(_maxRunspaces);
                _runspacePool.ThreadOptions = PSThreadOptions.UseNewThread;
                
                _runspacePool.Open();
                _isInitialized = true;
            });
        }

        public async Task ExecuteScriptAsync(string scriptPath, Dictionary<string, object>? parameters = null)
        {
            if (!_isInitialized || _runspacePool == null)
            {
                throw new InvalidOperationException("PowerShellEngine is not initialized.");
            }

            if (!File.Exists(scriptPath))
            {
                throw new FileNotFoundException($"Script not found: {scriptPath}");
            }

            // Read script content
            string scriptContent = await File.ReadAllTextAsync(scriptPath);

            // Execute in a task
            await Task.Run(async () =>
            {
                using var ps = PowerShell.Create();
                ps.RunspacePool = _runspacePool;
                
                // Add script logic
                ps.AddScript(scriptContent);

                // Add parameters
                if (parameters != null)
                {
                    ps.AddParameters(parameters);
                }

                // Prepare output collection
                var outputCollection = new PSDataCollection<PSObject>();
                
                // Event handling for logging (simplified for MVP)
                outputCollection.DataAdded += (sender, e) => 
                {
                    // Real-time output handling will go here
                };

                // Invoke Async
                try 
                {
                    var result = await ps.InvokeAsync();
                    
                    if (ps.HadErrors)
                    {
                        var sb = new StringBuilder();
                        foreach (var err in ps.Streams.Error)
                        {
                            sb.AppendLine(err.ToString());
                        }
                        throw new Exception($"Script execution error: {sb}");
                    }
                }
                catch (Exception ex)
                {
                    // Log error through standard logger
                    throw; 
                }
            });
        }

        public void StopAll()
        {
             _runspacePool?.Dispose();
             _isInitialized = false;
        }

        public void Dispose()
        {
            StopAll();
        }
    }
}
