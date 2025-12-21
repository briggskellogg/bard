import LocalAuthentication
import Foundation

// Read the reason from command line arguments
let reason = CommandLine.arguments.count > 1 
    ? CommandLine.arguments[1] 
    : "access your Bard vault"

let context = LAContext()
var error: NSError?

// Check if biometrics or password available
guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
    fputs("ERROR: Authentication not available\n", stderr)
    exit(1)
}

let semaphore = DispatchSemaphore(value: 0)
var authSuccess = false

context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authError in
    authSuccess = success
    if !success {
        if let err = authError as? LAError {
            switch err.code {
            case .userCancel:
                fputs("CANCELLED\n", stdout)
            case .userFallback:
                fputs("FALLBACK\n", stdout)
            default:
                fputs("ERROR: \(err.localizedDescription)\n", stderr)
            }
        }
    }
    semaphore.signal()
}

semaphore.wait()

if authSuccess {
    print("SUCCESS")
    exit(0)
} else {
    exit(1)
}

