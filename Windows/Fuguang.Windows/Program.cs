namespace Fuguang.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) => ShowFatalError(e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            if (e.ExceptionObject is Exception exception)
            {
                ShowFatalError(exception);
            }
        };

        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }

    private static void ShowFatalError(Exception exception)
    {
        MessageBox.Show(
            exception.ToString(),
            "Fuguang 启动或运行异常",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error);
    }
}
