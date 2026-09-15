// Markdown Reader 启动外壳（右键「打开方式」用）。
//
// 它的存在只有一个理由：Windows 的「打开方式」菜单里显示的名字，取自命令行中那个
// 可执行文件自己的版本信息。若直接让 wscript.exe 去跑脚本，菜单里就会显示成
//   「Microsoft ® Windows Based Script Host」
// 而这个程序集标题是 Markdown Reader，所以菜单里显示的就是 Markdown Reader。
//
// 本身不做任何业务逻辑：把参数原样转交给仓库里的 tools\open-with.ps1，
// 以隐藏窗口方式运行，脚本失败时弹窗提示并给出日志路径。
//
// 由 tools\install-open-with.ps1 用 csc.exe 编译到
//   %LOCALAPPDATA%\MarkdownReader\MarkdownReader.exe
// 编译命令：csc /target:winexe /codepage:65001 /win32icon:... /out:...
// 不要改成 /target:exe —— 那会带出一个黑框控制台窗口。

using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

[assembly: System.Reflection.AssemblyTitle("Markdown Reader")]
[assembly: System.Reflection.AssemblyProduct("Markdown Reader")]
[assembly: System.Reflection.AssemblyCompany("markdown-reader")]
[assembly: System.Reflection.AssemblyDescription("本地 Markdown 阅读器 · 右键「打开方式」启动外壳")]
[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("1.0.0.0")]

internal static class MarkdownReaderLauncher
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr hWnd, string lpText, string lpCaption, uint uType);

    private const uint MB_ICONERROR = 0x00000010;
    private const uint MB_ICONINFORMATION = 0x00000040;
    private const string Caption = "Markdown Reader";

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            MessageBoxW(IntPtr.Zero,
                "用法：MarkdownReader.exe \"<仓库>\\tools\\open-with.ps1\" <要打开的 .md>…",
                Caption, MB_ICONINFORMATION);
            return 2;
        }

        string script = args[0];
        if (!File.Exists(script))
        {
            MessageBoxW(IntPtr.Zero,
                "找不到启动脚本：\r\n" + script +
                "\r\n\r\n仓库被移动过？移动后请重新运行 tools\\install-open-with.cmd。",
                Caption, MB_ICONERROR);
            return 2;
        }

        StringBuilder cmdline = new StringBuilder();
        cmdline.Append("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"");
        cmdline.Append(script);
        cmdline.Append('"');
        for (int i = 1; i < args.Length; i++)
        {
            cmdline.Append(" \"");
            cmdline.Append(args[i].Replace("\"", "\\\""));
            cmdline.Append('"');
        }

        ProcessStartInfo psi = new ProcessStartInfo(PowerShellPath(), cmdline.ToString());
        psi.UseShellExecute = false;      // 配合 winexe + CreateNoWindow：全程不闪黑框
        psi.CreateNoWindow = true;
        psi.WindowStyle = ProcessWindowStyle.Hidden;

        try
        {
            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
                if (p.ExitCode != 0)
                {
                    MessageBoxW(IntPtr.Zero,
                        "启动失败（退出码 " + p.ExitCode + "）。\r\n\r\n" + LogTail(),
                        Caption, MB_ICONERROR);
                    return p.ExitCode;
                }
            }
        }
        catch (Exception ex)
        {
            MessageBoxW(IntPtr.Zero, "无法运行 PowerShell：\r\n" + ex.Message, Caption, MB_ICONERROR);
            return 1;
        }
        return 0;
    }

    private static string PowerShellPath()
    {
        string sys = Environment.GetFolderPath(Environment.SpecialFolder.System);
        string full = Path.Combine(sys, @"WindowsPowerShell\v1.0\powershell.exe");
        return File.Exists(full) ? full : "powershell.exe";
    }

    private static string LogTail()
    {
        try
        {
            string log = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                @"MarkdownReader\open-with.log");
            if (!File.Exists(log)) return "（没有日志文件）";
            string all = File.ReadAllText(log);
            return all.Length <= 900 ? all : all.Substring(all.Length - 900);
        }
        catch (Exception ex)
        {
            return "（读取日志失败：" + ex.Message + "）";
        }
    }
}
