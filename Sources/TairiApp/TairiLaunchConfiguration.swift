import Foundation

struct TairiLaunchConfiguration: Equatable {
    struct Strip: Equatable {
        let tileWidthFactors: [Double]

        static let `default` = Strip(tileWidthFactors: [1])
    }

    static let defaultStrips = [Strip.default]

    let initialStrips: [Strip]
    let ghosttyArguments: [String]
    let parseError: String?

    var resolvedInitialStrips: [Strip] {
        initialStrips.isEmpty ? Self.defaultStrips : initialStrips
    }

    var layoutSummary: String {
        resolvedInitialStrips
            .map { strip in
                strip.tileWidthFactors
                    .map(Self.formatFactor)
                    .joined(separator: ",")
            }
            .joined(separator: " | ")
    }

    static func fromProcessArguments(_ arguments: [String] = CommandLine.arguments) -> Self {
        let executable = arguments.first ?? "tairi"
        var ghosttyArguments = [executable]
        var initialStrips: [Strip] = []
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]

            if argument == "--strip" {
                guard index + 1 < arguments.count else {
                    return Self(
                        initialStrips: [],
                        ghosttyArguments: [executable],
                        parseError: "Missing value for --strip. Use --strip 1,1,1 or --strip 0.5,1."
                    )
                }

                do {
                    initialStrips.append(try parseStrip(arguments[index + 1]))
                } catch let error as LaunchConfigurationError {
                    return Self(
                        initialStrips: [],
                        ghosttyArguments: [executable],
                        parseError: error.message
                    )
                } catch {
                    return Self(
                        initialStrips: [],
                        ghosttyArguments: [executable],
                        parseError: "Invalid --strip value."
                    )
                }
                index += 2
                continue
            }

            if argument.hasPrefix("--strip=") {
                let value = String(argument.dropFirst("--strip=".count))
                do {
                    initialStrips.append(try parseStrip(value))
                } catch let error as LaunchConfigurationError {
                    return Self(
                        initialStrips: [],
                        ghosttyArguments: [executable],
                        parseError: error.message
                    )
                } catch {
                    return Self(
                        initialStrips: [],
                        ghosttyArguments: [executable],
                        parseError: "Invalid --strip value."
                    )
                }
                index += 1
                continue
            }

            ghosttyArguments.append(argument)
            index += 1
        }

        return Self(initialStrips: initialStrips, ghosttyArguments: ghosttyArguments, parseError: nil)
    }

    func withGhosttyArguments<Result>(
        _ body: (UInt, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Result
    ) -> Result {
        var cArguments = ghosttyArguments.map { strdup($0) }
        defer {
            for argument in cArguments {
                free(argument)
            }
        }

        return cArguments.withUnsafeMutableBufferPointer { buffer in
            body(UInt(buffer.count), buffer.baseAddress)
        }
    }

    private static func parseStrip(_ value: String) throws -> Strip {
        let components = value.split(separator: ",", omittingEmptySubsequences: false)
        guard !components.isEmpty else {
            throw LaunchConfigurationError.invalidStrip(value)
        }

        let factors = try components.map { component -> Double in
            let raw = String(component)
            guard let factor = Double(raw), factor.isFinite, factor > 0 else {
                throw LaunchConfigurationError.invalidSize(raw, strip: value)
            }
            return factor
        }

        return Strip(tileWidthFactors: factors)
    }

    private static func formatFactor(_ factor: Double) -> String {
        if factor.rounded() == factor {
            return String(Int(factor))
        }
        return String(format: "%.3g", factor)
    }
}

private enum LaunchConfigurationError: Error {
    case invalidStrip(String)
    case invalidSize(String, strip: String)

    var message: String {
        switch self {
        case .invalidStrip(let strip):
            return "Invalid --strip value \"\(strip)\". Use a comma-separated list of positive numbers."
        case .invalidSize(let size, let strip):
            return "Invalid size \"\(size)\" in --strip \"\(strip)\". Use positive numbers like 1 or 0.5."
        }
    }
}
