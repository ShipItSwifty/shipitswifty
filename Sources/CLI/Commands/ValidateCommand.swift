import ArgumentParser
import ShipItKit

struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate the selected Shipfile against schema and workflow semantics"
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let report = await ShipfileValidator().validate(
            shipfilePath: configuredShipfilePath(from: global),
            actionDescriptors: builtInActionDescriptors()
        )

        switch global.output {
        case .json:
            let reporter = JSONReporter()
            let status = report.isValid ? "success" : "failure"
            print(try reporter.encode(ActionResultEnvelope(action: "validate", status: status, payload: validationReportJSON(report))))
        case .human:
            let formatter = makeHumanFormatter(global: global)
            formatter.printHeader("Validation")
            formatter.printKV("Shipfile", report.shipfilePath)
            if report.issues.isEmpty {
                formatter.printSuccess("No validation issues found")
            } else {
                for issue in report.issues {
                    let line = "\(issue.path): \(issue.message)"
                    switch issue.severity {
                    case .error:
                        formatter.printError(line)
                    case .warning:
                        formatter.printWarning(line)
                    }
                }
            }
        }

        if !report.isValid {
            throw ExitCode(2)
        }
    }
}
