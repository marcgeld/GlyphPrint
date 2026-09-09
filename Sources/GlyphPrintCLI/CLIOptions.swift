import Foundation
import GlyphPrint

struct CLIOptions {
    enum Action: Equatable { case printQR, image(String), scan, connect(String?), status, setDefault(String), showDefault, clearDefault, help }
    var action: Action = .printQR
    var printer: String?
    var seconds: Double = 5
    var printersOnly = false
    var name: String?
    var verify = false
    var trace: String?
    var brightness: Float = 0
    var contrast: Float = 1
    var dither = false
    var text: [String] = []

    init(_ args: [String]) throws {
        var index = 0
        var hasAction = false
        var hasImageOptions = false
        func invalid(_ message: String) -> GlyphPrintError { .invalidArgument(message) }
        func value(_ option: String) throws -> String {
            guard index + 1 < args.count, !args[index + 1].isEmpty, !args[index + 1].hasPrefix("--") else { throw invalid("Missing value for \(option).") }
            index += 1
            return args[index]
        }
        func choose(_ action: Action) throws {
            guard !hasAction else { throw invalid("Choose only one action.") }
            self.action = action
            hasAction = true
        }
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--": text += args.dropFirst(index + 1); index = args.count; continue
            case "--help", "-h": try choose(.help)
            case "--scan": try choose(.scan)
            case "scan" where index == 0: try choose(.scan)
            case "--image": try choose(.image(try value(arg)))
            case "--connect": try choose(.connect(try value(arg)))
            case "connect" where index == 0: try choose(.connect(try value(arg)))
            case "--status": try choose(.status)
            case "--set-default": try choose(.setDefault(try value(arg)))
            case "--show-default": try choose(.showDefault)
            case "--clear-default": try choose(.clearDefault)
            case "--printer": printer = try value(arg)
            case "--printers": printersOnly = true
            case "--verify": verify = true
            case "--name": name = try value(arg)
            case "--trace": trace = try value(arg)
            case "--dither": dither = true; hasImageOptions = true
            case "--seconds":
                guard let number = Double(try value(arg)), number.isFinite, number > 0, number <= 60 else {
                    throw invalid("--seconds must be greater than 0 and at most 60.")
                }
                seconds = number
            case "--brightness":
                hasImageOptions = true
                guard let number = Float(try value(arg)), number.isFinite, (-1...1).contains(number) else {
                    throw invalid("--brightness must be between -1 and 1.")
                }
                brightness = number
            case "--contrast":
                hasImageOptions = true
                guard let number = Float(try value(arg)), number.isFinite, (0...4).contains(number) else {
                    throw invalid("--contrast must be between 0 and 4.")
                }
                contrast = number
            default:
                guard !arg.hasPrefix("-") else { throw invalid("Unknown option: \(arg)") }
                text.append(arg)
            }
            index += 1
        }
        if hasImageOptions {
            guard case .image = action else { throw invalid("Image adjustments require --image.") }
        }
        switch action {
        case .scan, .setDefault, .showDefault, .clearDefault, .help:
            if printer != nil || trace != nil { throw invalid("--printer and --trace require printing, --connect or --status.") }
        case .connect:
            if printer != nil { throw invalid("--connect already specifies the printer.") }
        default: break
        }
        if action != .printQR, !text.isEmpty { throw invalid("Unexpected positional arguments.") }
        if action != .scan, printersOnly || verify || name != nil { throw invalid("--printers, --verify and --name require --scan.") }
    }
}
