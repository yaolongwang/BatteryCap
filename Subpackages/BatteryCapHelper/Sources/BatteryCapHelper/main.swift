import Foundation

let listener = NSXPCListener(machServiceName: SMCHelperConstants.machServiceName)
let delegate = SMCHelper()
listener.delegate = delegate
listener.resume()

RunLoop.current.run()
