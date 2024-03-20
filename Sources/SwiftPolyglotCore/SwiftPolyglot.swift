import Foundation

public struct SwiftPolyglot {
    private let arguments: [String]

    public init(arguments: [String]) {
        self.arguments = arguments
    }

    enum Main {
        enum PolyglotError: Error {
            case directoryIsEmpty(directoryPath: String)
            case fileCouldNotBeProcessed(filePath: String)
        }

        struct MissingTranslation {
            let filePath: String
            let originalString: String
            let missingLanguages: [String]

            var description: [String] {
                missingLanguages.map { missingLanguage in
                    "\"\(originalString)\" is missing or not translated in \(missingLanguage) in file \"\(filePath)\""
                }
            }
        }

        static func getMissingTranslationsForFile(_ fileURL: URL, for languages: [String]) throws -> [MissingTranslation] {
            guard
                let data = try? Data(contentsOf: fileURL),
                let jsonObject = try? JSONSerialization.jsonObject(with: data),
                let jsonDict = jsonObject as? [String: Any],
                let strings = jsonDict["strings"] as? [String: [String: Any]]
            else {
                throw PolyglotError.fileCouldNotBeProcessed(filePath: fileURL.path)
            }

            let missingTranslations: [MissingTranslation] = strings.flatMap { originalString, translations -> [MissingTranslation] in
                guard
                    let localizations = translations["localizations"] as? [String: [String: Any]]
                else {
                    return [
                        .init(
                            filePath: fileURL.path,
                            originalString: originalString,
                            missingLanguages: languages
                        )
                    ]
                }

                let missingTranslations = languages.compactMap { language -> MissingTranslation? in
                    guard
                        let langDict = localizations[language],
                        let stringUnit = langDict["stringUnit"] as? [String: Any],
                        let state = stringUnit["state"] as? String,
                        state == "translated"
                    else { return nil }

                    return .init(
                        filePath: fileURL.path,
                        originalString: originalString,
                        missingLanguages: [language]
                    )
                }

                return missingTranslations
            }

            return missingTranslations
        }

        static func getMissingTranslationsForDirectory(_ dirPath: String, using fileManager: FileManager, for languages: [String]) throws -> [MissingTranslation] {
            guard
                let directoryContents = try? fileManager.contentsOfDirectory(atPath: dirPath)
            else {
                throw PolyglotError.directoryIsEmpty(directoryPath: dirPath)
            }

            let stringFiles = directoryContents.filter { $0.hasSuffix(".xcstrings") }

            let stringFilesURL = stringFiles.map { URL(fileURLWithPath: dirPath).appendingPathComponent($0) }

            let missingTranslations: [MissingTranslation] = try stringFilesURL.flatMap {
                    try Main.getMissingTranslationsForFile($0, for: languages)
            }

            return missingTranslations
        }
    }

    public func run() throws {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: script.swift <language codes> [--errorOnMissing]")
            exit(1)
        }

        let fileManager: FileManager = .default

        let isRunningFromGitHubActions: Bool = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"

        let languages: [String] = CommandLine.arguments[1].split(separator: ",").map(String.init)
        let errorOnMissing: Bool = CommandLine.arguments.contains("--errorOnMissing")

        do {
            let missingTranslations: [Main.MissingTranslation] = try Main.getMissingTranslationsForDirectory(fileManager.currentDirectoryPath, using: fileManager, for: languages)

            if missingTranslations.isEmpty {
                print("All translations are present")
                exit(EXIT_SUCCESS)
            } else {
                let logMessages = missingTranslations.map { missingTranslation in
                    if isRunningFromGitHubActions {
                        let type: String = errorOnMissing ? "error" : "warning"

                        return missingTranslation.description.map { "::\(type) file=\(missingTranslation.filePath)::" + $0 }
                    } else {
                        return missingTranslation.description
                    }
                }

                print(logMessages)

                print("Completed with missing translations")

                if errorOnMissing {
                    exit(EXIT_FAILURE)
                }
            }
        } catch let Main.PolyglotError.directoryIsEmpty(directoryPath) {
            print("Error: directory \"\(directoryPath)\" is empty")

            exit(EXIT_FAILURE)
        } catch let Main.PolyglotError.fileCouldNotBeProcessed(filePath) {
            if isRunningFromGitHubActions {
                print("::error file=\(filePath)::Could not process file at path: \(filePath)")
            } else {
                print("Error: file \"\(filePath)\" could not be processed")
            }

            exit(EXIT_FAILURE)
        }
    }
}
