// 享联 ShareLink 卸载程序
//
// 本文件是自包含的，可两种方式编译：
//   1) 与 ShareLinkSetup.cs 一起编译进安装向导（提供 --uninstall 兜底入口）；
//   2) 单独编译成 ~10 KB 的 Uninstall.exe，随安装流程写入安装目录。
// 因此这里不得引用 ShareLinkSetup.cs 中的任何类型。
//
// 单独编译：
//   csc /nologo /target:winexe /codepage:65001 /out:Uninstall.exe
//       /win32icon:assets\app_icon.ico
//       /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll
//       windows\installer\ShareLinkUninstaller.cs

using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using Microsoft.Win32;

namespace ShareLinkSetup
{
    /// <summary>
    /// 单独编译成 Uninstall.exe 时的入口点。
    /// 与安装向导一起编译时通过 /main:ShareLinkSetup.Program 指定向导为入口。
    /// </summary>
    internal static class UninstallEntry
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            UninstallMode.Run();
        }
    }

    internal static class UninstallMode
    {
        private const string AppName = "享联 ShareLink";
        private const string ShortcutName = "享联 ShareLink";
        private const string UninstallExeName = "Uninstall.exe";
        private const string UninstallRegPath =
            @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ShareLink";

        internal static void Run()
        {
            string installDir = ResolveInstallDir();
            if (string.IsNullOrEmpty(installDir))
            {
                MessageBox.Show(
                    "未找到 " + AppName + " 的安装信息，可能已被卸载。",
                    AppName,
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
                return;
            }

            DialogResult confirm = MessageBox.Show(
                "确定要卸载 " + AppName + " 吗？\r\n\r\n安装位置：" + installDir
                    + "\r\n\r\n卸载后该目录下的程序文件将被删除。",
                AppName + " 卸载",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2);

            if (confirm != DialogResult.Yes)
            {
                return;
            }

            RemoveShortcut(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory));
            RemoveShortcut(Environment.GetFolderPath(Environment.SpecialFolder.Programs));
            RemoveRegistryEntry();

            // 卸载程序自身位于待删除目录中，必须交给独立的 cmd 在进程退出后再删除
            try
            {
                ProcessStartInfo startInfo = new ProcessStartInfo();
                startInfo.FileName = "cmd.exe";
                startInfo.Arguments = "/c ping -n 3 127.0.0.1 > nul & rmdir /s /q \"" + installDir + "\"";
                startInfo.UseShellExecute = false;
                startInfo.CreateNoWindow = true;
                startInfo.WorkingDirectory = Path.GetTempPath();
                Process.Start(startInfo);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "无法自动删除安装目录，请手动删除：\r\n" + installDir + "\r\n\r\n" + ex.Message,
                    AppName,
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
            }
        }

        private static string ResolveInstallDir()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(UninstallRegPath))
                {
                    if (key != null)
                    {
                        object value = key.GetValue("InstallLocation");
                        if (value != null && Directory.Exists(value.ToString()))
                        {
                            return value.ToString();
                        }
                    }
                }
            }
            catch
            {
                // 回退到卸载程序所在目录
            }

            try
            {
                string dir = Path.GetDirectoryName(Application.ExecutablePath);
                if (!string.IsNullOrEmpty(dir) && Directory.Exists(dir))
                {
                    return dir;
                }
            }
            catch
            {
                // 无法定位安装目录
            }

            return null;
        }

        private static void RemoveShortcut(string folder)
        {
            if (string.IsNullOrEmpty(folder))
            {
                return;
            }
            try
            {
                string path = Path.Combine(folder, ShortcutName + ".lnk");
                if (File.Exists(path))
                {
                    File.Delete(path);
                }
            }
            catch
            {
                // 快捷方式删除失败不影响卸载
            }
        }

        private static void RemoveRegistryEntry()
        {
            try
            {
                Registry.CurrentUser.DeleteSubKeyTree(UninstallRegPath, false);
            }
            catch
            {
                // 注册表项删除失败不影响卸载
            }
        }
    }
}