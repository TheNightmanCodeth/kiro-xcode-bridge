// Thin executable entry point — all logic lives in KiroBridgeCore.
// We must call the *async* main() from an async context; top-level Swift
// code is synchronous, so we use a Task + RunLoop.main.run() to bridge.
import Foundation
import KiroBridgeCore

Task {
    await KiroBridgeCommand.main()
    // ArgumentParser's async main() returns after run() completes.
    // Call exit so the RunLoop below doesn't spin forever.
    exit(0)
}
RunLoop.main.run()
