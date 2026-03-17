import "./styles.css";
import { FitAddon, Terminal, init } from "ghostty-web";
import ghosttyWasmUrl from "ghostty-web/ghostty-vt.wasm?url";

const statusElement = document.querySelector<HTMLSpanElement>("#session-status");
const cwdElement = document.querySelector<HTMLSpanElement>("#session-cwd");
const titleElement = document.querySelector<HTMLParagraphElement>("#session-title");
const debugElement = document.querySelector<HTMLSpanElement>("#session-debug");
const terminalElement = document.querySelector<HTMLDivElement>("#terminal");

function setStatus(message: string): void {
  if (statusElement) {
    statusElement.textContent = message;
  }
}

function focusTerminalSurface(terminal: Terminal, container: HTMLDivElement): void {
  container.focus();
  terminal.focus();

  const textInput = container.querySelector("textarea, [contenteditable='true']");
  if (textInput instanceof HTMLElement) {
    textInput.focus();
  }
}

function setDebug(message: string): void {
  if (debugElement) {
    debugElement.textContent = message;
  }
}

function setSessionChrome(cwd: string): void {
  if (cwdElement) {
    cwdElement.textContent = cwd;
  }

  if (!titleElement) {
    return;
  }

  const segments = cwd.split("/").filter(Boolean);
  const leaf = segments.at(-1) || "shell";
  titleElement.textContent = `${leaf} dev`;
}

async function boot(): Promise<void> {
  if (!terminalElement) {
    throw new Error("Missing terminal mount point");
  }

  terminalElement.tabIndex = 0;

  const pendingOutput: string[] = [];
  let activeTerminal: Terminal | null = null;
  let outputChunks = 0;
  let outputBytes = 0;
  let sentKeys = 0;
  let rawKeydowns = 0;
  let focused = false;
  const updateDebug = () => {
    setDebug(
      `focus:${focused ? "yes" : "no"} keys:${rawKeydowns} sent:${sentKeys} out:${outputChunks}/${outputBytes}b`
    );
  };

  const disposeOutput = window.tairiTerminal.onOutput((data) => {
    outputChunks += 1;
    outputBytes += data.length;
    updateDebug();
    if (activeTerminal) {
      activeTerminal.write(data);
      return;
    }

    pendingOutput.push(data);
  });

  setStatus("Starting shell session…");
  const session = await window.tairiTerminal.createSession();
  setSessionChrome(session.cwd);

  setStatus("Loading ghostty-web…");
  await init(ghosttyWasmUrl);

  const terminal = new Terminal({
    fontFamily: '"Iosevka Term", "SF Mono", Menlo, Monaco, monospace',
    fontSize: 16,
    cursorBlink: true,
    theme: {
      background: "#000000",
      foreground: "#f3f3f0",
    },
  });
  const fitAddon = new FitAddon();

  activeTerminal = terminal;
  terminal.loadAddon(fitAddon);
  terminal.open(terminalElement);
  fitAddon.fit();

  if (session.initialBuffer) {
    terminal.write(session.initialBuffer);
  }
  for (const chunk of pendingOutput) {
    terminal.write(chunk);
  }
  pendingOutput.length = 0;

  const proposed = fitAddon.proposeDimensions();
  if (proposed) {
    await window.tairiTerminal.resize(proposed.cols, proposed.rows);
    terminal.resize(proposed.cols, proposed.rows);
  }

  focusTerminalSurface(terminal, terminalElement);
  const modeLabel =
    session.backend === "pty"
      ? "node-pty"
      : session.backend === "pty-bridge"
        ? "python PTY bridge"
        : "pipe fallback";
  setStatus(`Running ${session.shell} via ${modeLabel}`);
  focused = true;
  updateDebug();

  const disposeExit = window.tairiTerminal.onExit((exitCode) => {
    setStatus(`Shell exited with code ${exitCode}`);
    terminal.write(`\r\n[process exited with code ${exitCode}]\r\n`);
  });

  const disposeTerminalData =
    session.backend !== "pipe"
      ? terminal.onData((data: string) => {
          window.tairiTerminal.sendInput(data);
        })
      : null;

  const clickToFocus = () => {
    focusTerminalSurface(terminal, terminalElement);
  };
  const focusOnWindowActivate = () => {
    window.requestAnimationFrame(() => {
      focusTerminalSurface(terminal, terminalElement);
    });
  };
  const markFocused = () => {
    focused = true;
    updateDebug();
  };
  const markBlurred = () => {
    focused = false;
    updateDebug();
  };

  terminalElement.addEventListener("mousedown", clickToFocus);
  window.addEventListener("focus", focusOnWindowActivate);
  terminalElement.addEventListener("focus", markFocused);
  terminalElement.addEventListener("blur", markBlurred);

  let focusAttempts = 0;
  const maxFocusAttempts = 30;
  const sustainInitialFocus = () => {
    focusTerminalSurface(terminal, terminalElement);
    focusAttempts += 1;
    if (focusAttempts < maxFocusAttempts) {
      window.requestAnimationFrame(sustainInitialFocus);
    }
  };
  window.requestAnimationFrame(sustainInitialFocus);

  const handlePipeFallbackKeydown = (event: KeyboardEvent) => {
    if (session.backend !== "pipe") {
      return;
    }

    rawKeydowns += 1;
    updateDebug();

    if (event.metaKey) {
      return;
    }

    let payload: string | null = null;

    if (event.ctrlKey && !event.altKey && !event.shiftKey) {
      if (event.key.length === 1) {
        const upper = event.key.toUpperCase();
        const code = upper.charCodeAt(0);
        if (code >= 64 && code <= 95) {
          payload = String.fromCharCode(code - 64);
        }
      }
    } else {
      switch (event.key) {
        case "Enter":
          payload = "\n";
          break;
        case "Backspace":
          payload = "\u007f";
          break;
        case "Tab":
          payload = "\t";
          break;
        case "Escape":
          payload = "\u001b";
          break;
        case "ArrowUp":
          payload = "\u001b[A";
          break;
        case "ArrowDown":
          payload = "\u001b[B";
          break;
        case "ArrowRight":
          payload = "\u001b[C";
          break;
        case "ArrowLeft":
          payload = "\u001b[D";
          break;
        default:
          if (!event.ctrlKey && !event.altKey && event.key.length === 1) {
            payload = event.key;
          }
          break;
      }
    }

    if (payload == null) {
      return;
    }

    event.preventDefault();
    sentKeys += 1;
    updateDebug();
    window.tairiTerminal.sendInput(payload);
  };

  terminalElement.addEventListener("keydown", handlePipeFallbackKeydown, true);
  window.addEventListener("keydown", handlePipeFallbackKeydown, true);

  const resizeObserver = new ResizeObserver(async () => {
    const next = fitAddon.proposeDimensions();
    if (!next) {
      return;
    }

    await window.tairiTerminal.resize(next.cols, next.rows);
    terminal.resize(next.cols, next.rows);
  });
  resizeObserver.observe(terminalElement);

  window.addEventListener("beforeunload", () => {
    resizeObserver.disconnect();
    terminalElement.removeEventListener("mousedown", clickToFocus);
    window.removeEventListener("focus", focusOnWindowActivate);
    terminalElement.removeEventListener("focus", markFocused);
    terminalElement.removeEventListener("blur", markBlurred);
    terminalElement.removeEventListener("keydown", handlePipeFallbackKeydown, true);
    window.removeEventListener("keydown", handlePipeFallbackKeydown, true);
    disposeTerminalData?.dispose();
    disposeOutput();
    disposeExit();
    activeTerminal = null;
    terminal.dispose();
  });
}

void boot().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  setStatus(`Failed to boot terminal: ${message}`);
});
