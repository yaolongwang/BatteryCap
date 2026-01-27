import Foundation
import Security
import ServiceManagement

/// SMC 特权安装管理
final class SMCPrivilegeManager {
    func installHelper() throws {
        guard SMCHelperLocator.isRunningFromAppBundle else {
            throw BatteryError.unknown("请从已打包的应用运行以启用授权写入。")
        }
        guard SMCHelperLocator.helperFilesExist else {
            throw BatteryError.unknown("缺少特权写入组件，请重新打包应用。")
        }

        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &authRef)
        guard status == errAuthorizationSuccess, let authRef else {
            throw BatteryError.permissionDenied
        }
        defer {
            AuthorizationFree(authRef, [])
        }

        var error: Unmanaged<CFError>?
        let blessed = SMJobBless(
            kSMDomainSystemLaunchd,
            SMCHelperClient.machServiceName as CFString,
            authRef,
            &error
        )

        if blessed {
            return
        }

        if let error = error?.takeRetainedValue() {
            throw BatteryError.unknown(error.localizedDescription)
        }

        throw BatteryError.permissionDenied
    }
}
