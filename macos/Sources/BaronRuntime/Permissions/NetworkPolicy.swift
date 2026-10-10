import BaronCore
import Foundation

/// Decides whether a plugin may reach a URL: its granted network permissions, checked on the first URL and on
/// every redirect hop. Design: 04-permissions-and-security.md#network-patterns
public struct NetworkPolicy: Sendable {
    public typealias Resolver = @Sendable (String) async -> [String]

    public let grants: GrantStore
    private let resolve: Resolver

    /// `resolve` turns a host name into addresses; tests replace it.
    public init(grants: GrantStore, resolve: @escaping Resolver = NetworkPolicy.systemResolve) {
        self.grants = grants
        self.resolve = resolve
    }

    /// Nil when allowed; otherwise the error the plugin sees.
    public func check(_ url: URL, for plugin: RuntimePlugin) async -> HostError? {
        guard let target = NetworkTarget(url) else { return .invalidArgument("Only http and https URLs can be fetched") }
        let set = await grants.grantedSet(for: plugin)
        if set.networkPermission(covering: url) != nil {
            return await privateAddressRefusal(target)
        }
        let name = target.permissionName
        let requestable = PluginPermission(name).map(set.mayRequest) == true && !set.recentlyDenied.contains(name)
        return PermissionGate.denied(name, requestable: requestable)
    }
}

extension NetworkPolicy {
    /// A public name must not lead to a private, link-local or loopback address. Names that are themselves local
    /// (`localhost`) and IP literals are left to the matcher, which needs an exact entry for them.
    func privateAddressRefusal(_ target: NetworkTarget) async -> HostError? {
        let host = target.host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !NetworkAddress.isRestricted(target.host), !Self.isIPLiteral(host) else { return nil }
        let addresses = await resolve(host)
        guard let restricted = addresses.first(where: NetworkAddress.isRestricted) else { return nil }
        return HostError("permission_denied", "\(host) leads to a private address (\(restricted)), which plugins can't reach through a public name",
                         data: .object(["permission": .string(target.permissionName), "requestable": .bool(false), "reason": .string("private_address")]))
    }

    static func isIPLiteral(_ host: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1
    }

    /// The system's resolver (getaddrinfo), off the caller's thread.
    public static let systemResolve: Resolver = { host in
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
                var list: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return continuation.resume(returning: []) }
                defer { freeaddrinfo(first) }
                var addresses: [String] = []
                var node: UnsafeMutablePointer<addrinfo>? = first
                while let current = node {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        addresses.append(text.contains(":") ? "[\(text)]" : text)
                    }
                    node = current.pointee.ai_next
                }
                continuation.resume(returning: addresses)
            }
        }
    }
}
