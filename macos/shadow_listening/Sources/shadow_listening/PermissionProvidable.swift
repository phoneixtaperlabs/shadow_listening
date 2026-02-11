import Foundation

protocol PermissionProvidable {
    var permissionType: String { get }
    func checkStatus() -> Bool
    func requestAccess(completion: @escaping (Bool) -> Void)
}
