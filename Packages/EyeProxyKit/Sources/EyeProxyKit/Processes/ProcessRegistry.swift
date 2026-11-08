import EyeProxyCore
import Foundation
import Observation

@Observable @MainActor
public final class ProcessRegistry {
    public private(set) var attribution: [FlowID: ProcessIdentity] = [:]

    public init() {}

    public func set(_ identity: ProcessIdentity, for id: FlowID) { attribution[id] = identity }
    public func remove(_ id: FlowID) { attribution[id] = nil }
    public func replace(_ all: [FlowID: ProcessIdentity]) { attribution = all }
    public func clear() { attribution = [:] }
}
