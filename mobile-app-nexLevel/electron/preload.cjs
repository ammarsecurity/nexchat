const { contextBridge } = require('electron')

contextBridge.exposeInMainWorld('nexchat', {
  isElectron: true,
  platform: process.platform
})
