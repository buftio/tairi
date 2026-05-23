import Foundation

struct ProcessPipeOutput {
    let stdout: Data
    let stderr: Data
}

struct ProcessPipeDrain {
    private let group: DispatchGroup
    private let stdoutData: LockedProcessPipeData
    private let stderrData: LockedProcessPipeData

    static func start(stdout: Pipe, stderr: Pipe) -> ProcessPipeDrain {
        let group = DispatchGroup()
        let stdoutData = LockedProcessPipeData()
        let stderrData = LockedProcessPipeData()
        let stdoutHandle = stdout.fileHandleForReading
        let stderrHandle = stderr.fileHandleForReading

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData.set(stdoutHandle.readDataToEndOfFile())
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData.set(stderrHandle.readDataToEndOfFile())
            group.leave()
        }

        return ProcessPipeDrain(group: group, stdoutData: stdoutData, stderrData: stderrData)
    }

    func waitForOutput() -> ProcessPipeOutput {
        group.wait()
        return ProcessPipeOutput(stdout: stdoutData.value, stderr: stderrData.value)
    }
}

private final class LockedProcessPipeData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func set(_ data: Data) {
        lock.lock()
        self.data = data
        lock.unlock()
    }
}
