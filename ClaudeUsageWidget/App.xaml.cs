using System.Threading;
using System.Windows;

namespace ClaudeUsageWidget;

public partial class App : Application
{
    // PowerShell surumuyle ayni isimler: iki surum ayni anda calisamaz,
    // ikinci kopya mevcut pencereyi one getirip cikar
    private const string MutexName = @"Local\ClaudeUsageWidgetSingleton";
    private const string ShowEventName = @"Local\ClaudeUsageWidgetShow";

    private Mutex? _mutex;
    public static EventWaitHandle? ShowEvent { get; private set; }

    protected override void OnStartup(StartupEventArgs e)
    {
        _mutex = new Mutex(false, MutexName);
        if (!_mutex.WaitOne(0))
        {
            try { EventWaitHandle.OpenExisting(ShowEventName).Set(); } catch { }
            Shutdown();
            return;
        }
        ShowEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);

        base.OnStartup(e);
        new MainWindow().Show();
    }
}
