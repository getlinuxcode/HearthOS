// Hôte Electron du shell sur la distribution (lancé dans gamescope par hearth-inner).
const { app, BrowserWindow } = require('electron');

app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required'); // sons dès le boot
app.commandLine.appendSwitch('enable-features', 'WebRTCPipeWireCapturer');

app.whenReady().then(() => {
  const win = new BrowserWindow({
    fullscreen: true,
    frame: false,
    backgroundColor: '#05070d',
    autoHideMenuBar: true,
    webPreferences: { backgroundThrottling: false },
  });
  win.loadURL(process.env.HEARTH_URL || 'http://127.0.0.1:7300/');
});

app.on('window-all-closed', () => app.quit());
