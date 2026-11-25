// לוח הקומה — תוכנת מסך מלא ל-Windows.
// חלון בלי מסגרת שמכסה את כל המסך (גם את שורת המשימות) ומציג את הלוח ב-WebView2.
// אין לו מצב "יציאה ממסך מלא": החלון תמיד בגודל המסך, ושומר על זה כל כמה שניות.
//
// איזו כתובת נפתחת (הראשון שקיים):
//   1. כתובת שהועברה בשורת הפקודה:      LuachScreen.exe http://...
//   2. שורה שמתחילה ב-http בקובץ luach-screen.txt שליד התוכנה
//   3. השרת המקומי, אם מותקן מצב בלי אינטרנט (C:\luach\app\local\luach-local.js)
//   4. האתר: https://shdydaniel.github.io/luach/
//
// קיצורי מקשים:  Ctrl+Shift+Q סגירה · Ctrl+Shift+R רענון
using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace LuachScreen
{
    static class Program
    {
        const string SiteUrl = "https://shdydaniel.github.io/luach/";
        const string LocalUrl = "http://localhost:8770/";
        const string LocalServerFile = @"C:\luach\app\local\luach-local.js";

        [STAThread]
        static void Main(string[] args)
        {
            using (var mutex = new Mutex(true, "LuachScreen.SingleInstance", out bool first))
            {
                if (!first) return; // כבר פתוח
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new ScreenForm(ResolveUrl(args)));
            }
        }

        static string ResolveUrl(string[] args)
        {
            foreach (var a in args)
                if (IsHttp(a)) return a.Trim();
            try
            {
                var cfg = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "luach-screen.txt");
                if (File.Exists(cfg))
                    foreach (var line in File.ReadAllLines(cfg))
                        if (IsHttp(line)) return line.Trim();
            }
            catch { /* קובץ לא קריא — ממשיכים לברירת המחדל */ }
            return File.Exists(LocalServerFile) ? LocalUrl : SiteUrl;
        }

        static bool IsHttp(string s) =>
            Uri.TryCreate((s ?? "").Trim(), UriKind.Absolute, out var u) && (u.Scheme == "http" || u.Scheme == "https");
    }

    sealed class ScreenForm : Form
    {
        readonly string url;
        readonly WebView2 web = new WebView2 { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.Black };
        readonly Label status = new Label
        {
            Dock = DockStyle.Fill, ForeColor = Color.FromArgb(200, 200, 210), BackColor = Color.Black,
            TextAlign = ContentAlignment.MiddleCenter, RightToLeft = RightToLeft.Yes,
            Font = new Font("Segoe UI", 28f), Text = "טוען את לוח הקומה…"
        };
        readonly System.Windows.Forms.Timer guard = new System.Windows.Forms.Timer { Interval = 3000 };
        readonly System.Windows.Forms.Timer retry = new System.Windows.Forms.Timer { Interval = 10000 };

        const int HotkeyQuit = 1, HotkeyReload = 2;

        public ScreenForm(string url)
        {
            this.url = url;
            Text = "לוח הקומה";
            BackColor = Color.Black;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            TopMost = true;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            FitToScreen();

            web.Visible = false;
            Controls.Add(web);
            Controls.Add(status);

            guard.Tick += (s, e) => FitToScreen();
            retry.Tick += (s, e) => { retry.Stop(); Go(); };
            Microsoft.Win32.SystemEvents.DisplaySettingsChanged += (s, e) => BeginInvoke(new Action(FitToScreen));
        }

        /// <summary>מכסה את כל המסך הראשי, בלי שוליים, מעל שורת המשימות.</summary>
        void FitToScreen()
        {
            var b = Screen.PrimaryScreen.Bounds;
            if (WindowState != FormWindowState.Normal) WindowState = FormWindowState.Normal;
            if (Bounds != b) Bounds = b;
            if (!TopMost) TopMost = true;
        }

        protected override async void OnShown(EventArgs e)
        {
            base.OnShown(e);
            guard.Start();
            Native.KeepDisplayOn();
            Native.RegisterHotKey(Handle, HotkeyQuit, Native.MOD_CONTROL | Native.MOD_SHIFT | Native.MOD_NOREPEAT, (uint)Keys.Q);
            Native.RegisterHotKey(Handle, HotkeyReload, Native.MOD_CONTROL | Native.MOD_SHIFT | Native.MOD_NOREPEAT, (uint)Keys.R);
            await InitWebView();
        }

        async Task InitWebView()
        {
            try
            {
                var data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LuachScreen", "WebView2");
                var options = new CoreWebView2EnvironmentOptions(
                    "--autoplay-policy=no-user-gesture-required --overscroll-history-navigation=0 " +
                    "--disable-features=Translate,msSmartScreenProtection --disable-pinch");
                var env = await CoreWebView2Environment.CreateAsync(null, data, options);
                await web.EnsureCoreWebView2Async(env);
            }
            catch (WebView2RuntimeNotFoundException)
            {
                status.Text = "חסר במחשב הרכיב Microsoft Edge WebView2 Runtime.\n" +
                              "הוא נפתח עכשיו להורדה — מתקינים, ואז מפעילים את התוכנה מחדש.";
                try { System.Diagnostics.Process.Start("https://go.microsoft.com/fwlink/p/?LinkId=2124703"); } catch { }
                return;
            }
            catch (Exception ex)
            {
                status.Text = "שגיאה בהפעלת התצוגה:\n" + ex.Message;
                return;
            }

            var core = web.CoreWebView2;
            var st = core.Settings;
            st.AreDefaultContextMenusEnabled = false;
            st.AreDevToolsEnabled = false;
            st.IsZoomControlEnabled = false;
            st.IsPinchZoomEnabled = false;
            st.IsSwipeNavigationEnabled = false;
            st.IsStatusBarEnabled = false;
            st.AreBrowserAcceleratorKeysEnabled = false; // בלי F5/F12/Ctrl+P וכו'
            st.IsGeneralAutofillEnabled = false;
            st.IsPasswordAutosaveEnabled = false;
            // הלוח מזהה שהוא רץ בתוכנה ומסתיר את כפתור "מסך מלא" (אין מה לצאת ממנו).
            st.UserAgent = st.UserAgent + " LuachScreen/1.0";

            core.NewWindowRequested += (s, e) => e.Handled = true; // אף פעם לא פותחים חלון נוסף
            core.NavigationCompleted += (s, e) =>
            {
                if (e.IsSuccess) { web.Visible = true; status.Visible = false; return; }
                if (e.WebErrorStatus == CoreWebView2WebErrorStatus.OperationCanceled) return;
                ShowStatus("אין חיבור ללוח כרגע — מנסה שוב בעוד כמה שניות…");
                retry.Start();
            };
            core.ProcessFailed += (s, e) =>
            {
                if (e.ProcessFailedKind == CoreWebView2ProcessFailedKind.BrowserProcessExited)
                {
                    // מנוע הדפדפן קרס לגמרי — פותחים את התוכנה מחדש.
                    Application.Restart();
                    Environment.Exit(0);
                }
                else
                {
                    ShowStatus("התצוגה נטענת מחדש…");
                    retry.Start();
                }
            };
            Go();
        }

        void ShowStatus(string text) { status.Text = text; status.Visible = true; web.Visible = false; }

        void Go()
        {
            try { web.CoreWebView2?.Navigate(url); }
            catch { retry.Start(); }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Native.WM_HOTKEY)
            {
                var id = m.WParam.ToInt32();
                if (id == HotkeyQuit) { Close(); return; }
                if (id == HotkeyReload) { Go(); return; }
            }
            base.WndProc(ref m);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            Native.UnregisterHotKey(Handle, HotkeyQuit);
            Native.UnregisterHotKey(Handle, HotkeyReload);
            Native.AllowDisplayOff();
            base.OnFormClosed(e);
        }
    }

    static class Native
    {
        public const int WM_HOTKEY = 0x0312;
        public const uint MOD_SHIFT = 0x4, MOD_CONTROL = 0x2, MOD_NOREPEAT = 0x4000;
        const uint ES_CONTINUOUS = 0x80000000, ES_SYSTEM_REQUIRED = 0x1, ES_DISPLAY_REQUIRED = 0x2;

        [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
        [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);

        /// <summary>לא לתת למסך להיכבות או למחשב להירדם בזמן שהלוח פתוח.</summary>
        public static void KeepDisplayOn() => SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED);
        public static void AllowDisplayOff() => SetThreadExecutionState(ES_CONTINUOUS);
    }
}
