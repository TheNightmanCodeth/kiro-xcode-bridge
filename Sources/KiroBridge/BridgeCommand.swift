import ArgumentParser
import Foundation

/// The top-level CLI command. Launched from the executable target via `KiroBridgeCommand.main()`.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
@main
struct KiroBridgeCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "kiro-bridge",
    abstract: "Bridges Kiro into Xcode's Coding Intelligence as a native provider."
  )

  @Option(name: .long, help: "Port for Xcode to connect to.")
  var port: Int = KiroConfig.defaultPort

  @Option(name: .long, help: "AWS region for the Kiro backend.")
  var region: String = KiroConfig.defaultRegion

  @Option(name: .long, help: "Xcode project root (for .kiro/steering/ files).")
  var project: String = ""

  @Option(name: .long, help: "Kiro API key (Pro/Pro+/Power). Also reads KIRO_API_KEY env var.")
  var apiKey: String? = nil

  @Option(name: .long, help: "IAM Identity Center start URL for enterprise SSO login.")
  var startUrl: String? = nil

  @Flag(name: .long, help: "Force re-login even if cached credentials exist.")
  var login: Bool = false

  @Flag(name: .long, help: "Print auth and request details for debugging.")
  var verbose: Bool = false

  init() {}

  mutating func run() async throws {
    let projectPath = project.isEmpty ? FileManager.default.currentDirectoryPath : project
    let resolvedApiKey = apiKey ?? ProcessInfo.processInfo.environment["KIRO_API_KEY"]

    let resolver = CredentialResolver(
      apiKey: resolvedApiKey,
      startUrl: startUrl,
      region: region,
      forceLogin: login,
      verbose: verbose
    )

    print("kiro-bridge: Resolving credentials...")
    let tokenManager = try await resolver.resolve()

    let steeringLoader = SteeringLoader(projectPath: projectPath)
    let ruleCount =
      steeringLoader.rules.isEmpty
      ? 0 : steeringLoader.rules.components(separatedBy: "\n\n---\n\n").filter { !$0.isEmpty }.count

    let models: [OpenAIModel]
    if let cliModels = KiroCLIModels.fetch(verbose: verbose) {
      models = cliModels
    } else if let token = try? await tokenManager.getValidToken(),
      let apiModels = await ModelFetcher.fetch(
        token: token,
        profileArn: await tokenManager.profileArn,
        region: region
      )
    {
      models = apiModels
    } else {
      models = KiroConfig.models
    }

    print("kiro-bridge: Starting on http://127.0.0.1:\(port)")
    print("   Region:  \(region)")
    print("   Project: \(projectPath)")
    print("   Auth:    \(await tokenManager.method)")
    print("   Models:  \(models.map(\.id).joined(separator: ", "))")
    if ruleCount > 0 {
      print("   Steering: \(ruleCount) file(s) loaded")
    }
    print("")
    print("   Xcode setup: Settings → Intelligence → + → Locally Hosted")
    print("   Port: \(port)   Description: Kiro")
    print("")

    let app = buildApp(
      port: port,
      region: region,
      tokenManager: tokenManager,
      steeringLoader: steeringLoader,
      models: models,
      verbose: verbose
    )
    try await app.runService()
  }
}
