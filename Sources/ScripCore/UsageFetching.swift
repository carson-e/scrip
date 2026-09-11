@MainActor
public protocol UsageFetching: AnyObject {
    func fetchSnapshot(allowNavigation: Bool) async -> PageSnapshot
    func signOut() async
}
