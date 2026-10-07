// 享联 ShareLink 安装向导
//
// 编译方式（Windows 自带 csc，无需安装 Inno Setup / NSIS）：
//   csc /nologo /target:winexe /codepage:65001 /out:ShareLink-Setup.exe
//       /win32icon:assets\app_icon.ico
//       /resource:payload.7z,PAYLOAD
//       /resource:7zr.exe,SEVENZR
//       /resource:Uninstall.exe,UNINSTALLER
//       /resource:app_icon.png,APPICONPNG
//       /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll
//       windows\installer\ShareLinkSetup.cs
//
// 说明：使用 csc v4.0.30319（C# 5.0），请勿使用字符串插值 / ?. 等新语法。

using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace ShareLinkSetup
{
    internal static class Program
    {
        internal const string AppName = "享联 ShareLink";
        internal const string AppVersion = "1.0.0";
        internal const string ExeName = "share_link.exe";
        internal const string ShortcutName = "享联 ShareLink";
        internal const string UninstallExeName = "Uninstall.exe";
        internal const string UninstallRegPath =
            @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ShareLink";

        /// <summary>解压后大致占用空间，用于安装前提示与磁盘校验。</summary>
        internal const long RequiredDiskBytes = 130L * 1024L * 1024L;

        internal static readonly Color Brand = Color.FromArgb(3, 92, 251);
        internal static readonly Color BrandHover = Color.FromArgb(2, 74, 208);
        internal static readonly Color TextPrimary = Color.FromArgb(17, 24, 39);
        internal static readonly Color TextSecondary = Color.FromArgb(110, 118, 132);
        internal static readonly Color PageBack = Color.White;
        internal static readonly Color BarBack = Color.FromArgb(249, 250, 251);
        internal static readonly Color BorderColor = Color.FromArgb(228, 231, 236);

        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            if (args != null)
            {
                foreach (string arg in args)
                {
                    if (string.Equals(arg, "--uninstall", StringComparison.OrdinalIgnoreCase))
                    {
                        UninstallMode.Run();
                        return;
                    }
                }
            }

            try
            {
                Application.Run(new SetupForm());
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "安装向导发生错误：\r\n\r\n" + ex.Message,
                    AppName,
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }

        /// <summary>从自身程序集读取嵌入资源。</summary>
        internal static Stream OpenResource(string name)
        {
            return Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
        }

        internal static void ExtractResourceToFile(string name, string path)
        {
            using (Stream input = OpenResource(name))
            {
                if (input == null)
                {
                    throw new InvalidOperationException("安装包缺少内置资源：" + name);
                }
                using (FileStream output = new FileStream(path, FileMode.Create, FileAccess.Write))
                {
                    input.CopyTo(output);
                }
            }
        }

        internal static Font MakeFont(float size, FontStyle style)
        {
            return new Font("Microsoft YaHei UI", size, style, GraphicsUnit.Point);
        }

        /// <summary>默认安装目录：当前用户目录下，无需管理员权限。</summary>
        internal static string DefaultInstallDir()
        {
            string baseDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(Path.Combine(baseDir, "Programs"), "ShareLink");
        }

        /// <summary>读取注册表中记录的安装位置（用于覆盖安装/升级）。</summary>
        internal static string RegisteredInstallDir()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(UninstallRegPath))
                {
                    if (key != null)
                    {
                        object value = key.GetValue("InstallLocation");
                        if (value != null)
                        {
                            string dir = value.ToString();
                            if (!string.IsNullOrEmpty(dir))
                            {
                                return dir;
                            }
                        }
                    }
                }
            }
            catch
            {
                // 忽略读取失败，回退到默认目录
            }
            return null;
        }
    }

    /// <summary>安装向导主窗口。</summary>
    internal sealed class SetupForm : Form
    {
        private enum Stage
        {
            Options,
            Installing,
            Finished
        }

        private readonly string _iconExe;

        private Panel _banner;
        private Panel _pageOptions;
        private Panel _pageProgress;
        private Panel _pageFinish;
        private Panel _bottomBar;

        private TextBox _txtPath;
        private CheckBox _chkDesktop;
        private CheckBox _chkStartMenu;
        private CheckBox _chkRun;
        private Label _lblProgress;
        private ProgressBar _progressBar;
        private Label _lblFinishDetail;
        private Label _lblError;

        private Button _btnPrimary;
        private Button _btnSecondary;

        private Stage _stage = Stage.Options;
        private string _installDir;

        internal SetupForm()
        {
            _iconExe = Application.ExecutablePath;

            SuspendLayout();

            Text = Program.AppName + " 安装向导";
            Font = Program.MakeFont(9F, FontStyle.Regular);
            BackColor = Program.PageBack;
            ForeColor = Program.TextPrimary;
            ClientSize = new Size(604, 402);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ShowInTaskbar = true;
            DoubleBuffered = true;

            try
            {
                Icon appIcon = Icon.ExtractAssociatedIcon(_iconExe);
                if (appIcon != null)
                {
                    Icon = appIcon;
                }
            }
            catch
            {
                // 图标提取失败不影响安装流程
            }

            BuildBanner();
            BuildBottomBar();
            BuildOptionsPage();
            BuildProgressPage();
            BuildFinishPage();

            Controls.Add(_pageOptions);
            Controls.Add(_pageProgress);
            Controls.Add(_pageFinish);
            Controls.Add(_banner);
            Controls.Add(_bottomBar);

            FormClosing += OnFormClosing;
            ResumeLayout(false);
        }

        #region 界面构建

        private void BuildBanner()
        {
            _banner = new Panel();
            _banner.SetBounds(0, 0, 604, 92);
            _banner.BackColor = Program.Brand;

            PictureBox logo = new PictureBox();
            logo.SetBounds(26, 20, 52, 52);
            logo.SizeMode = PictureBoxSizeMode.Zoom;
            logo.BackColor = Color.Transparent;
            using (Stream stream = Program.OpenResource("APPICONPNG"))
            {
                if (stream != null)
                {
                    using (Image image = Image.FromStream(stream))
                    {
                        logo.Image = new Bitmap(image);
                    }
                }
            }
            _banner.Controls.Add(logo);

            Label title = new Label();
            title.Text = Program.AppName;
            title.Font = Program.MakeFont(16F, FontStyle.Bold);
            title.ForeColor = Color.White;
            title.BackColor = Color.Transparent;
            title.AutoSize = true;
            title.Location = new Point(92, 22);
            _banner.Controls.Add(title);

            Label subtitle = new Label();
            subtitle.Text = "版本 " + Program.AppVersion + "    ·    跨设备无缝互联，文件即取即用";
            subtitle.Font = Program.MakeFont(9F, FontStyle.Regular);
            subtitle.ForeColor = Color.FromArgb(214, 230, 255);
            subtitle.BackColor = Color.Transparent;
            subtitle.AutoSize = true;
            subtitle.Location = new Point(94, 54);
            _banner.Controls.Add(subtitle);
        }

        private void BuildBottomBar()
        {
            _bottomBar = new Panel();
            _bottomBar.SetBounds(0, 338, 604, 64);
            _bottomBar.BackColor = Program.BarBack;

            Panel line = new Panel();
            line.SetBounds(0, 0, 604, 1);
            line.BackColor = Program.BorderColor;
            _bottomBar.Controls.Add(line);

            _btnSecondary = MakeButton("取消", false);
            _btnSecondary.SetBounds(378, 16, 100, 34);
            _btnSecondary.Click += OnSecondaryClick;
            _bottomBar.Controls.Add(_btnSecondary);

            _btnPrimary = MakeButton("安装", true);
            _btnPrimary.SetBounds(486, 16, 100, 34);
            _btnPrimary.Click += OnPrimaryClick;
            _bottomBar.Controls.Add(_btnPrimary);
        }

        private Button MakeButton(string text, bool primary)
        {
            Button button = new Button();
            button.Text = text;
            button.Font = Program.MakeFont(9.5F, FontStyle.Regular);
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderSize = primary ? 0 : 1;
            button.FlatAppearance.BorderColor = Program.BorderColor;
            button.BackColor = primary ? Program.Brand : Color.White;
            button.ForeColor = primary ? Color.White : Program.TextPrimary;
            button.UseVisualStyleBackColor = false;
            button.Cursor = Cursors.Hand;
            if (primary)
            {
                button.FlatAppearance.MouseOverBackColor = Program.BrandHover;
                button.FlatAppearance.MouseDownBackColor = Program.BrandHover;
            }
            else
            {
                button.FlatAppearance.MouseOverBackColor = Color.FromArgb(243, 244, 246);
                button.FlatAppearance.MouseDownBackColor = Color.FromArgb(236, 238, 241);
            }
            return button;
        }

        private void BuildOptionsPage()
        {
            _pageOptions = new Panel();
            _pageOptions.SetBounds(0, 92, 604, 246);
            _pageOptions.BackColor = Program.PageBack;

            _pageOptions.Controls.Add(MakeLabel("安装位置", 30, 22, Program.MakeFont(9F, FontStyle.Bold), Program.TextPrimary));

            _txtPath = new TextBox();
            _txtPath.SetBounds(30, 48, 428, 26);
            _txtPath.Font = Program.MakeFont(9.5F, FontStyle.Regular);
            _txtPath.BorderStyle = BorderStyle.FixedSingle;
            _txtPath.Text = Program.RegisteredInstallDir() ?? Program.DefaultInstallDir();
            _pageOptions.Controls.Add(_txtPath);

            Button browse = MakeButton("浏览...", false);
            browse.SetBounds(466, 47, 108, 28);
            browse.Click += OnBrowseClick;
            _pageOptions.Controls.Add(browse);

            _chkDesktop = MakeCheckBox("创建桌面快捷方式", 30, 92, true);
            _pageOptions.Controls.Add(_chkDesktop);

            _chkStartMenu = MakeCheckBox("创建开始菜单快捷方式", 30, 120, true);
            _pageOptions.Controls.Add(_chkStartMenu);

            _chkRun = MakeCheckBox("安装完成后运行 " + Program.AppName, 30, 148, true);
            _pageOptions.Controls.Add(_chkRun);

            Label hint = MakeLabel(
                "为当前用户安装，无需管理员权限。安装后将占用约 78 MB 磁盘空间。",
                30, 190, Program.MakeFont(8.5F, FontStyle.Regular), Program.TextSecondary);
            hint.MaximumSize = new Size(544, 0);
            hint.AutoSize = true;
            _pageOptions.Controls.Add(hint);

            _lblError = MakeLabel(string.Empty, 30, 214, Program.MakeFont(8.5F, FontStyle.Regular), Color.FromArgb(220, 38, 38));
            _lblError.AutoSize = true;
            _lblError.Visible = false;
            _pageOptions.Controls.Add(_lblError);
        }

        private void BuildProgressPage()
        {
            _pageProgress = new Panel();
            _pageProgress.SetBounds(0, 92, 604, 246);
            _pageProgress.BackColor = Program.PageBack;
            _pageProgress.Visible = false;

            _pageProgress.Controls.Add(MakeLabel("正在安装，请稍候…", 30, 62, Program.MakeFont(11F, FontStyle.Bold), Program.TextPrimary));

            _progressBar = new ProgressBar();
            _progressBar.SetBounds(30, 100, 544, 18);
            _progressBar.Minimum = 0;
            _progressBar.Maximum = 100;
            _progressBar.Style = ProgressBarStyle.Continuous;
            _pageProgress.Controls.Add(_progressBar);

            _lblProgress = MakeLabel("准备中…", 30, 128, Program.MakeFont(8.5F, FontStyle.Regular), Program.TextSecondary);
            _lblProgress.AutoSize = true;
            _pageProgress.Controls.Add(_lblProgress);

            Label tip = MakeLabel(
                "安装期间请勿关闭本窗口。",
                30, 196, Program.MakeFont(8.5F, FontStyle.Regular), Program.TextSecondary);
            tip.AutoSize = true;
            _pageProgress.Controls.Add(tip);
        }

        private void BuildFinishPage()
        {
            _pageFinish = new Panel();
            _pageFinish.SetBounds(0, 92, 604, 246);
            _pageFinish.BackColor = Program.PageBack;
            _pageFinish.Visible = false;

            _pageFinish.Controls.Add(MakeLabel("安装完成", 30, 40, Program.MakeFont(14F, FontStyle.Bold), Program.TextPrimary));

            _lblFinishDetail = MakeLabel(string.Empty, 30, 84, Program.MakeFont(9F, FontStyle.Regular), Program.TextSecondary);
            _lblFinishDetail.MaximumSize = new Size(544, 0);
            _lblFinishDetail.AutoSize = true;
            _pageFinish.Controls.Add(_lblFinishDetail);

            Label tip = MakeLabel(
                "你可以通过桌面快捷方式、开始菜单，或直接运行安装目录中的 "
                    + Program.ExeName + " 启动 " + Program.AppName + "。",
                30, 150, Program.MakeFont(8.5F, FontStyle.Regular), Program.TextSecondary);
            tip.MaximumSize = new Size(544, 0);
            tip.AutoSize = true;
            _pageFinish.Controls.Add(tip);
        }

        private static Label MakeLabel(string text, int x, int y, Font font, Color color)
        {
            Label label = new Label();
            label.Text = text;
            label.Font = font;
            label.ForeColor = color;
            label.BackColor = Color.Transparent;
            label.Location = new Point(x, y);
            label.AutoSize = true;
            return label;
        }

        private CheckBox MakeCheckBox(string text, int x, int y, bool isChecked)
        {
            CheckBox box = new CheckBox();
            box.Text = text;
            box.Font = Program.MakeFont(9.5F, FontStyle.Regular);
            box.ForeColor = Program.TextPrimary;
            box.BackColor = Color.Transparent;
            box.AutoSize = true;
            box.Checked = isChecked;
            box.Location = new Point(x, y);
            box.Cursor = Cursors.Hand;
            return box;
        }

        #endregion

        #region 交互

        private void OnBrowseClick(object sender, EventArgs e)
        {
            using (FolderBrowserDialog dialog = new FolderBrowserDialog())
            {
                dialog.Description = "请选择 " + Program.AppName + " 的安装位置";
                dialog.ShowNewFolderButton = true;
                string current = _txtPath.Text.Trim();
                if (current.Length > 0 && Directory.Exists(current))
                {
                    dialog.SelectedPath = current;
                }
                if (dialog.ShowDialog(this) == DialogResult.OK)
                {
                    // 用户可能只选了父目录，自动补一级子目录，避免污染所选目录
                    string chosen = dialog.SelectedPath;
                    if (!string.Equals(
                            Path.GetFileName(chosen.TrimEnd(Path.DirectorySeparatorChar)),
                            "ShareLink",
                            StringComparison.OrdinalIgnoreCase))
                    {
                        chosen = Path.Combine(chosen, "ShareLink");
                    }
                    _txtPath.Text = chosen;
                }
            }
        }

        private void OnPrimaryClick(object sender, EventArgs e)
        {
            if (_stage == Stage.Finished)
            {
                Close();
                return;
            }
            StartInstall();
        }

        private void OnSecondaryClick(object sender, EventArgs e)
        {
            if (_stage == Stage.Finished)
            {
                LaunchApp();
                Close();
                return;
            }
            Close();
        }

        private void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            if (_stage == Stage.Installing)
            {
                e.Cancel = true;
            }
        }

        private void ShowError(string message)
        {
            _lblError.Text = message;
            _lblError.Visible = true;
        }

        private void StartInstall()
        {
            string raw = _txtPath.Text.Trim();
            if (raw.Length == 0)
            {
                ShowError("请填写安装位置。");
                return;
            }

            string target;
            try
            {
                target = Path.GetFullPath(raw);
            }
            catch
            {
                ShowError("安装位置不是有效的路径。");
                return;
            }

            try
            {
                string root = Path.GetPathRoot(target);
                if (!string.IsNullOrEmpty(root))
                {
                    DriveInfo drive = new DriveInfo(root);
                    if (drive.IsReady && drive.AvailableFreeSpace < Program.RequiredDiskBytes)
                    {
                        ShowError("磁盘可用空间不足，至少需要 130 MB。");
                        return;
                    }
                }
            }
            catch
            {
                // 无法读取磁盘信息时不做阻断
            }

            _installDir = target;
            _lblError.Visible = false;

            _stage = Stage.Installing;
            _pageOptions.Visible = false;
            _pageFinish.Visible = false;
            _pageProgress.Visible = true;
            _btnSecondary.Visible = false;
            _btnPrimary.Enabled = false;
            _btnPrimary.Text = "安装中…";
            _progressBar.Value = 0;
            _lblProgress.Text = "准备中…";

            Thread worker = new Thread(InstallWorker);
            worker.IsBackground = true;
            worker.Start();
        }

        #endregion

        #region 安装流程

        private void InstallWorker()
        {
            string tempDir = Path.Combine(
                Path.GetTempPath(),
                "ShareLinkSetup_" + Guid.NewGuid().ToString("N"));

            try
            {
                Directory.CreateDirectory(tempDir);

                Report(1, "正在准备安装文件…");
                string sevenZip = Path.Combine(tempDir, "7zr.exe");
                Program.ExtractResourceToFile("SEVENZR", sevenZip);

                string payload = Path.Combine(tempDir, "payload.7z");
                Program.ExtractResourceToFile("PAYLOAD", payload);

                string uninstaller = Path.Combine(tempDir, Program.UninstallExeName);
                Program.ExtractResourceToFile("UNINSTALLER", uninstaller);

                Report(4, "正在创建安装目录…");
                Directory.CreateDirectory(_installDir);

                Report(6, "正在解压应用文件…");
                string output = Path.Combine(_installDir, Program.ExeName);
                RunExtraction(sevenZip, payload);

                if (!File.Exists(output))
                {
                    throw new InvalidOperationException(
                        "解压完成后未找到主程序 " + Program.ExeName + "，安装已中止。");
                }

                Report(96, "正在写入卸载程序…");
                File.Copy(uninstaller, Path.Combine(_installDir, Program.UninstallExeName), true);

                Report(97, "正在创建快捷方式…");
                CreateShortcuts(output);

                Report(99, "正在登记安装信息…");
                RegisterUninstallEntry(output);

                Report(100, "安装完成");
                BeginInvoke(new MethodInvoker(FinishInstall));
            }
            catch (Exception ex)
            {
                string message = ex.Message;
                BeginInvoke(new MethodInvoker(delegate { FailInstall(message); }));
            }
            finally
            {
                try
                {
                    if (Directory.Exists(tempDir))
                    {
                        Directory.Delete(tempDir, true);
                    }
                }
                catch
                {
                    // 临时目录清理失败不影响安装结果
                }
            }
        }

        private void RunExtraction(string sevenZip, string payload)
        {
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = sevenZip;
            startInfo.Arguments = "x \"" + payload + "\" -o\"" + _installDir + "\" -y -bsp1";
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.RedirectStandardOutput = true;

            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                {
                    throw new InvalidOperationException("无法启动解压程序。");
                }

                // 7zr 用 \r 刷新进度，需要逐字符读取再按行解析百分比
                StringBuilder line = new StringBuilder();
                int ch;
                while ((ch = process.StandardOutput.Read()) >= 0)
                {
                    if (ch == '\r' || ch == '\n')
                    {
                        ReportFromProgressLine(line.ToString());
                        line.Length = 0;
                    }
                    else
                    {
                        line.Append((char)ch);
                    }
                }

                process.WaitForExit();
                if (process.ExitCode != 0)
                {
                    throw new InvalidOperationException(
                        "解压失败（错误码 " + process.ExitCode.ToString(CultureInfo.InvariantCulture)
                            + "），请确认安装位置可写后重试。");
                }
            }
        }

        private void ReportFromProgressLine(string line)
        {
            int percentIndex = line.IndexOf('%');
            if (percentIndex <= 0)
            {
                return;
            }

            int end = percentIndex - 1;
            while (end >= 0 && line[end] == ' ')
            {
                end--;
            }
            int start = end;
            while (start >= 0 && char.IsDigit(line[start]))
            {
                start--;
            }
            if (end <= start)
            {
                return;
            }

            int percent;
            if (int.TryParse(
                    line.Substring(start + 1, end - start),
                    NumberStyles.Integer,
                    CultureInfo.InvariantCulture,
                    out percent))
            {
                // 解压阶段映射到 6% - 95% 区间
                Report(6 + (int)(percent * 0.89), "正在解压应用文件… " + percent + "%");
            }
        }

        private void Report(int percent, string text)
        {
            if (percent < 0)
            {
                percent = 0;
            }
            if (percent > 100)
            {
                percent = 100;
            }
            BeginInvoke(new MethodInvoker(delegate
            {
                _progressBar.Value = percent;
                _lblProgress.Text = text;
            }));
        }

        private void CreateShortcuts(string targetExe)
        {
            if (_chkDesktop.Checked)
            {
                string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                if (!string.IsNullOrEmpty(desktop))
                {
                    CreateShortcut(Path.Combine(desktop, Program.ShortcutName + ".lnk"), targetExe, false);
                }
            }

            if (_chkStartMenu.Checked)
            {
                string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
                if (!string.IsNullOrEmpty(programs))
                {
                    CreateShortcut(Path.Combine(programs, Program.ShortcutName + ".lnk"), targetExe, false);
                }
            }
        }

        /// <summary>用 WScript.Shell 创建 .lnk，无需额外依赖。</summary>
        internal static void CreateShortcut(string linkPath, string targetExe, bool uninstall)
        {
            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType == null)
            {
                return;
            }

            object shell = Activator.CreateInstance(shellType);
            object shortcut = shellType.InvokeMember(
                "CreateShortcut",
                BindingFlags.InvokeMethod,
                null,
                shell,
                new object[] { linkPath });

            Type shortcutType = shortcut.GetType();
            shortcutType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, shortcut, new object[] { targetExe });
            shortcutType.InvokeMember(
                "WorkingDirectory",
                BindingFlags.SetProperty,
                null,
                shortcut,
                new object[] { Path.GetDirectoryName(targetExe) });
            shortcutType.InvokeMember("IconLocation", BindingFlags.SetProperty, null, shortcut, new object[] { targetExe + ",0" });
            shortcutType.InvokeMember(
                "Description",
                BindingFlags.SetProperty,
                null,
                shortcut,
                new object[] { Program.AppName + " - 跨设备无缝互联" });
            shortcutType.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
        }

        private void RegisterUninstallEntry(string targetExe)
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(Program.UninstallRegPath))
            {
                if (key == null)
                {
                    return;
                }

                string installDir = Path.GetDirectoryName(targetExe);
                string uninstaller = Path.Combine(installDir, Program.UninstallExeName);

                key.SetValue("DisplayName", Program.AppName, RegistryValueKind.String);
                key.SetValue("DisplayVersion", Program.AppVersion, RegistryValueKind.String);
                key.SetValue("Publisher", "ShareLink", RegistryValueKind.String);
                key.SetValue("DisplayIcon", targetExe, RegistryValueKind.String);
                key.SetValue("InstallLocation", installDir, RegistryValueKind.String);
                key.SetValue("UninstallString", "\"" + uninstaller + "\"", RegistryValueKind.String);
                key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            }
        }

        private void FinishInstall()
        {
            _stage = Stage.Finished;
            _pageProgress.Visible = false;
            _pageFinish.Visible = true;
            _lblFinishDetail.Text = Program.AppName + " " + Program.AppVersion
                + " 已安装到：\r\n" + _installDir;

            _btnPrimary.Enabled = true;
            _btnPrimary.Text = "完成";
            _btnSecondary.Text = "立即运行";
            _btnSecondary.Visible = true;

            if (_chkRun.Checked)
            {
                LaunchApp();
            }
        }

        private void FailInstall(string message)
        {
            _stage = Stage.Options;
            _pageProgress.Visible = false;
            _pageFinish.Visible = false;
            _pageOptions.Visible = true;
            _btnSecondary.Visible = true;
            _btnSecondary.Text = "取消";
            _btnPrimary.Enabled = true;
            _btnPrimary.Text = "安装";
            ShowError("安装失败：" + message);
        }

        private void LaunchApp()
        {
            try
            {
                string exe = Path.Combine(_installDir ?? string.Empty, Program.ExeName);
                if (File.Exists(exe))
                {
                    ProcessStartInfo startInfo = new ProcessStartInfo();
                    startInfo.FileName = exe;
                    startInfo.WorkingDirectory = _installDir;
                    startInfo.UseShellExecute = true;
                    Process.Start(startInfo);
                }
            }
            catch
            {
                // 启动失败不阻断向导关闭
            }
        }

        #endregion
    }
}