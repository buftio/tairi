interface TerminalSessionInfo {
  id: string;
  cwd: string;
  shell: string;
  initialBuffer: string;
  backend: "pty" | "pty-bridge" | "pipe";
}

interface TairiTerminalAPI {
  createSession(): Promise<TerminalSessionInfo>;
  sendInput(data: string): void;
  resize(cols: number, rows: number): Promise<void>;
  onOutput(listener: (data: string) => void): () => void;
  onExit(listener: (exitCode: number) => void): () => void;
}

declare global {
  interface Window {
    tairiTerminal: TairiTerminalAPI;
  }
}

export {};
