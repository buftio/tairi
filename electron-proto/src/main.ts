import { app, BrowserWindow, ipcMain } from "electron";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import * as path from "node:path";
import * as pty from "node-pty";
import { Writable } from "node:stream";

type TerminalSessionInfo = {
  id: string;
  cwd: string;
  shell: string;
  initialBuffer: string;
  backend: "pty" | "pty-bridge" | "pipe";
};

type SizePayload = {
  cols: number;
  rows: number;
};

class TerminalSession {
  readonly id = "primary";
  readonly cwd = path.resolve(__dirname, "../..");
  readonly shell = process.env.SHELL?.trim() || "/bin/zsh";
  readonly backend: "pty" | "pty-bridge" | "pipe";
  private buffer = "";
  private readonly ptyProcess: pty.IPty | null;
  private readonly childProcess: ChildProcessWithoutNullStreams | null;
  private readonly launchedCommand: string;
  private readonly controlStream: NodeJS.WritableStream | null;

  constructor(private readonly window: BrowserWindow) {
    const env = {
      ...process.env,
      COLORTERM: "truecolor",
      TERM: "xterm-256color",
    };

    try {
      this.ptyProcess = pty.spawn(this.shell, ["-i"], {
        name: "xterm-256color",
        cols: 120,
        rows: 32,
        cwd: this.cwd,
        env,
      });
      this.childProcess = null;
      this.controlStream = null;
      this.backend = "pty";
      this.launchedCommand = `${this.shell} -i`;

      this.ptyProcess.onData((data) => {
        this.pushOutput(data);
      });

      this.ptyProcess.onExit(({ exitCode }) => {
        this.window.webContents.send("terminal:exit", exitCode);
      });
      return;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.warn(`[tairi-electron-proto] node-pty unavailable, trying Python PTY bridge: ${message}`);
    }

    const fallbackShell = "/bin/bash";
    const fallbackArgs = ["--noprofile", "--norc", "-i"];
    const bridgeScript = path.resolve(__dirname, "../scripts/pty_bridge.py");
    const fallbackEnv = {
      ...env,
      BASH_SILENCE_DEPRECATION_WARNING: "1",
      CLICOLOR: "1",
      PS1: "\\[\\e[38;5;81m\\]\\u@tairi\\[\\e[0m\\]:\\[\\e[38;5;114m\\]\\w\\[\\e[0m\\]\\$ ",
      TAIRI_PTY_CWD: this.cwd,
    };

    this.childProcess = spawn("uv", ["run", "python3", bridgeScript, fallbackShell, ...fallbackArgs], {
      stdio: ["pipe", "pipe", "pipe", "pipe"],
      cwd: this.cwd,
      env: fallbackEnv,
    });
    this.ptyProcess = null;
    const maybeControlStream = this.childProcess.stdio[3];
    this.controlStream = maybeControlStream instanceof Writable ? maybeControlStream : null;
    this.backend = "pty-bridge";
    this.launchedCommand = `uv run python3 ${path.basename(bridgeScript)} ${fallbackShell} ${fallbackArgs.join(" ")}`;

    this.childProcess.stdout.on("data", (chunk) => {
      this.pushOutput(chunk.toString());
    });
    this.childProcess.stderr.on("data", (chunk) => {
      this.pushOutput(chunk.toString());
    });
    this.childProcess.on("exit", (exitCode) => {
      this.window.webContents.send("terminal:exit", exitCode ?? 0);
    });

    setTimeout(() => {
      this.write("\n");
    }, 80);
  }

  toInfo(): TerminalSessionInfo {
    return {
      id: this.id,
      cwd: this.cwd,
      shell: this.launchedCommand,
      initialBuffer: this.buffer,
      backend: this.backend,
    };
  }

  write(data: string): void {
    if (this.ptyProcess) {
      this.ptyProcess.write(data);
      return;
    }

    this.childProcess?.stdin.write(data);
  }

  resize({ cols, rows }: SizePayload): void {
    if (cols <= 0 || rows <= 0) {
      return;
    }

    if (this.ptyProcess) {
      this.ptyProcess.resize(cols, rows);
      return;
    }

    if (this.backend === "pty-bridge" && this.controlStream) {
      this.controlStream.write(`${JSON.stringify({ type: "resize", cols, rows })}\n`);
    }
  }

  dispose(): void {
    this.ptyProcess?.kill();
    this.childProcess?.kill();
  }

  private pushOutput(data: string): void {
    this.buffer = `${this.buffer}${data}`.slice(-200_000);
    this.window.webContents.send("terminal:output", data);
  }
}

let mainWindow: BrowserWindow | null = null;
let session: TerminalSession | null = null;

function createWindow(): BrowserWindow {
  const window = new BrowserWindow({
    width: 1540,
    height: 1080,
    minWidth: 1100,
    minHeight: 760,
    titleBarStyle: "hiddenInset",
    backgroundColor: "#0b1016",
    webPreferences: {
      contextIsolation: true,
      preload: path.join(__dirname, "preload.js"),
    },
  });

  const devServerUrl = process.env.VITE_DEV_SERVER_URL;
  if (devServerUrl) {
    void window.loadURL(devServerUrl);
  } else {
    void window.loadFile(path.join(__dirname, "../dist/index.html"));
  }

  window.on("closed", () => {
    if (session) {
      session.dispose();
      session = null;
    }
    if (mainWindow === window) {
      mainWindow = null;
    }
  });

  return window;
}

function ensureSession(): TerminalSession {
  if (!mainWindow) {
    throw new Error("Main window is not ready");
  }
  if (!session) {
    session = new TerminalSession(mainWindow);
  }
  return session;
}

app.whenReady().then(() => {
  ipcMain.handle("terminal:create-session", () => ensureSession().toInfo());
  ipcMain.on("terminal:input", (_event, data: string) => {
    ensureSession().write(data);
  });
  ipcMain.handle("terminal:resize", (_event, size: SizePayload) => {
    ensureSession().resize(size);
  });

  mainWindow = createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      mainWindow = createWindow();
    }
  });
});

app.on("before-quit", () => {
  if (session) {
    session.dispose();
    session = null;
  }
});

app.on("window-all-closed", () => {
  app.quit();
});
