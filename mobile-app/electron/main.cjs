const { app, BrowserWindow, shell, Menu } = require('electron')
const path = require('path')

const isDev = process.env.ELECTRON_DEV === 'true'

// Fixed phone-like portrait frame; change FIXED_* if you want another size.
const FIXED_WIDTH = 390
const FIXED_HEIGHT = 844

function createWindow() {
  const win = new BrowserWindow({
    // width/height = content (viewport) size, not including frame — stable CSS layout
    useContentSize: true,
    width: FIXED_WIDTH,
    height: FIXED_HEIGHT,
    minWidth: FIXED_WIDTH,
    maxWidth: FIXED_WIDTH,
    minHeight: FIXED_HEIGHT,
    maxHeight: FIXED_HEIGHT,
    resizable: false,
    maximizable: false,
    fullscreenable: false,
    show: false,
    backgroundColor: '#0D0D1A',
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      zoomFactor: 1
    }
  })

  const wc = win.webContents
  function lockPageZoom() {
    wc.setZoomFactor(1)
    wc.setZoomLevel(0)
  }
  wc.on('did-finish-load', lockPageZoom)
  wc.on('did-navigate-in-page', lockPageZoom)
  wc.on('before-input-event', (event, input) => {
    if (input.type !== 'keyDown') return
    if (!(input.control || input.meta)) return
    const k = input.key
    if (k === '+' || k === '-' || k === '=' || k === '_') event.preventDefault()
  })

  win.on('maximize', () => win.unmaximize())
  win.on('enter-full-screen', () => win.setFullScreen(false))

  win.once('ready-to-show', () => {
    lockPageZoom()
    win.show()
  })

  if (isDev) {
    const url = process.env.ELECTRON_START_URL || 'http://127.0.0.1:5174'
    win.loadURL(url)
    win.webContents.openDevTools({ mode: 'detach' })
  } else {
    const indexHtml = path.join(__dirname, '..', 'dist', 'index.html')
    win.loadFile(indexHtml)
  }

  wc.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url)
    return { action: 'deny' }
  })
}

app.whenReady().then(() => {
  // Remove default File/Edit/View menu bar on Windows and Linux (macOS keeps the system menu bar).
  if (process.platform !== 'darwin') {
    Menu.setApplicationMenu(null)
  }
  createWindow()
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})
