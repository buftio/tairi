import { contextBridge, ipcRenderer } from "electron";

const api = {
  createSession: () => ipcRenderer.invoke("terminal:create-session"),
  sendInput: (data: string) => {
    ipcRenderer.send("terminal:input", data);
  },
  resize: (cols: number, rows: number) =>
    ipcRenderer.invoke("terminal:resize", { cols, rows }),
  onOutput: (listener: (data: string) => void) => {
    const wrapped = (_event: Electron.IpcRendererEvent, data: string) => {
      listener(data);
    };

    ipcRenderer.on("terminal:output", wrapped);
    return () => {
      ipcRenderer.removeListener("terminal:output", wrapped);
    };
  },
  onExit: (listener: (exitCode: number) => void) => {
    const wrapped = (_event: Electron.IpcRendererEvent, exitCode: number) => {
      listener(exitCode);
    };

    ipcRenderer.on("terminal:exit", wrapped);
    return () => {
      ipcRenderer.removeListener("terminal:exit", wrapped);
    };
  },
};

contextBridge.exposeInMainWorld("tairiTerminal", api);
