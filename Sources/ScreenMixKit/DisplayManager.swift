import Foundation
import CoreGraphics
import IOKit

/// Finds all connected displays and attaches a DDC/CI transport to the external ones.
///
/// Transports are cached per `CGDirectDisplayID`, because creating an `IOAVService` is
/// relatively expensive and because polled reads (slider preview, hotkeys) must stay fast.
public enum DisplayManager {
    private static var transportCache: [CGDirectDisplayID: DDCTransport] = [:]
    private static let cacheLock = NSLock()

    // MARK: - Public API

    public static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 24)
        let result = CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
        guard result == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Re-enumerates all displays. Call this after a monitor was plugged in or removed.
    public static func refresh() -> [PhysicalDisplay] {
        let displayIDs = onlineDisplayIDs()

        #if arch(arm64)
        let candidates = avCandidates()
        let assignment = match(displayIDs: displayIDs, candidates: candidates)
        #elseif arch(x86_64)
        let assignment: [CGDirectDisplayID: AVCandidate] = [:]
        #else
        let assignment: [CGDirectDisplayID: AVCandidate] = [:]
        #endif

        var result: [PhysicalDisplay] = []
        for (index, displayID) in displayIDs.enumerated() {
            let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
            let info = PrivateAPI.shared.displayInfo(for: displayID)
            let candidate = assignment[displayID]
            let name = resolveName(displayID: displayID, info: info, candidate: candidate, index: index)
            let transport = transport(for: displayID, candidate: candidate, isBuiltin: isBuiltin)
            let uuid = displayUUID(displayID)

            result.append(PhysicalDisplay(
                id: uuid ?? "display-\(displayID)",
                displayID: displayID,
                name: name,
                vendor: CGDisplayVendorNumber(displayID),
                model: CGDisplayModelNumber(displayID),
                serial: CGDisplaySerialNumber(displayID),
                isBuiltin: isBuiltin,
                transport: transport
            ))
        }
        return result
    }

    /// Drops the cached transports, e.g. after the display configuration changed.
    public static func invalidateCache() {
        cacheLock.lock()
        transportCache.removeAll()
        cacheLock.unlock()
    }

    // MARK: - Transport creation

    private static func transport(for displayID: CGDirectDisplayID,
                                  candidate: AVCandidate?,
                                  isBuiltin: Bool) -> DDCTransport? {
        guard !isBuiltin else { return nil }

        cacheLock.lock()
        if let cached = transportCache[displayID] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var newTransport: DDCTransport?

        #if arch(arm64)
        if let service = candidate?.service, PrivateAPI.shared.supportsIOAVService {
            newTransport = Arm64Transport(service: service, chipAddress: candidate?.chipAddress ?? DDCConstants.chipAddress)
        } else if PrivateAPI.shared.supportsIOAVService,
                  onlineDisplayIDs().filter({ CGDisplayIsBuiltin($0) == 0 }).count == 1,
                  let service = PrivateAPI.shared.avService(for: 0) {
            // Single external display but no proxy matched: fall back to the default service.
            newTransport = Arm64Transport(service: service, chipAddress: DDCConstants.chipAddress)
        }
        #elseif arch(x86_64)
        newTransport = IntelTransport(displayID: displayID)
        #endif

        if let newTransport {
            cacheLock.lock()
            transportCache[displayID] = newTransport
            cacheLock.unlock()
        }
        return newTransport
    }

    private static func displayUUID(_ displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        let text: String = CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
        return text
    }

    private static func resolveName(displayID: CGDirectDisplayID,
                                    info: [String: Any]?,
                                    candidate: AVCandidate?,
                                    index: Int) -> String {
        if let names = info?["DisplayProductName"] as? [String: String] {
            if let preferred = names["en_US"] ?? names.values.first, !preferred.isEmpty {
                return preferred
            }
        }
        if let productName = candidate?.productName, !productName.isEmpty {
            return productName
        }
        return CGDisplayIsBuiltin(displayID) != 0 ? "Integrierter Bildschirm" : "Bildschirm \(index + 1)"
    }

    // MARK: - Apple Silicon IORegistry matching

    struct AVCandidate {
        var framebufferPath: String = ""
        var proxyPath: String = ""
        var edidUUID: String = ""
        var productName: String = ""
        var manufacturer: String = ""
        var serial: Int64 = 0
        var chipAddress: UInt32 = DDCConstants.chipAddress
        var service: UnsafeMutableRawPointer?
    }

    #if arch(arm64)
    private static func avCandidates() -> [AVCandidate] {
        guard PrivateAPI.shared.supportsIOAVService else { return [] }

        var result: [AVCandidate] = []
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return [] }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(root, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var current = AVCandidate()

        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }

            var nameBuffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &nameBuffer) == KERN_SUCCESS else {
                IOObjectRelease(entry)
                continue
            }
            let name = String(cString: nameBuffer)

            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebuffer") {
                current = AVCandidate()
                current.framebufferPath = registryPath(entry)
                current.edidUUID = stringProperty(entry, "EDID UUID") ?? ""
                if let attributes = dictionaryProperty(entry, "DisplayAttributes"),
                   let product = attributes["ProductAttributes"] as? [String: Any] {
                    current.productName = product["ProductName"] as? String ?? ""
                    current.manufacturer = product["ManufacturerID"] as? String ?? ""
                    current.serial = (product["SerialNumber"] as? NSNumber)?.int64Value ?? 0
                }
                IOObjectRelease(entry)
                continue
            }

            if name.contains("DCPAVServiceProxy") {
                let location = stringProperty(entry, "Location") ?? ""
                if location == "External", let service = PrivateAPI.shared.avService(for: entry) {
                    var candidate = current
                    candidate.proxyPath = registryPath(entry)
                    candidate.service = service
                    candidate.chipAddress = hasMCDP29XXParent(entry) ? DDCConstants.mcdpChipAddress : DDCConstants.chipAddress
                    result.append(candidate)
                }
            }
            IOObjectRelease(entry)
        }
        return result
    }

    private static func match(displayIDs: [CGDirectDisplayID], candidates: [AVCandidate]) -> [CGDirectDisplayID: AVCandidate] {
        var remaining = candidates
        var assignment: [CGDirectDisplayID: AVCandidate] = [:]

        // 1. exact match on the IORegistry path reported by CoreDisplay
        for displayID in displayIDs {
            guard let location = PrivateAPI.shared.displayInfo(for: displayID)?["IODisplayLocation"] as? String else { continue }
            if let index = remaining.firstIndex(where: {
                !location.isEmpty && ($0.proxyPath == location || $0.framebufferPath == location)
            }) {
                assignment[displayID] = remaining.remove(at: index)
            }
        }

        // 2. match by product name and serial number
        for displayID in displayIDs where assignment[displayID] == nil {
            let name = resolveName(displayID: displayID, info: PrivateAPI.shared.displayInfo(for: displayID), candidate: nil, index: 0)
            if let index = remaining.firstIndex(where: { $0.productName == name && !name.isEmpty }) {
                assignment[displayID] = remaining.remove(at: index)
            }
        }

        // 3. match by serial number
        for displayID in displayIDs where assignment[displayID] == nil {
            let serial = Int64(CGDisplaySerialNumber(displayID))
            if serial != 0, let index = remaining.firstIndex(where: { $0.serial == serial }) {
                assignment[displayID] = remaining.remove(at: index)
            }
        }

        // 4. assign the leftovers in order to displays that still have no transport
        for displayID in displayIDs where assignment[displayID] == nil {
            guard CGDisplayIsBuiltin(displayID) == 0, !remaining.isEmpty else { continue }
            assignment[displayID] = remaining.removeFirst()
        }

        return assignment
    }
    #else
    private static func match(displayIDs: [CGDirectDisplayID], candidates: [AVCandidate]) -> [CGDirectDisplayID: AVCandidate] {
        [:]
    }
    #endif

    private static func registryPath(_ entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard IORegistryEntryGetPath(entry, "IOService", &buffer) == KERN_SUCCESS else { return "" }
        return String(cString: buffer)
    }

    private static func stringProperty(_ entry: io_registry_entry_t, _ key: String) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return value.takeRetainedValue() as? String
    }

    private static func dictionaryProperty(_ entry: io_registry_entry_t, _ key: String) -> [String: Any]? {
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) else {
            return nil
        }
        return value.takeRetainedValue() as? [String: Any]
    }

    private static func hasMCDP29XXParent(_ entry: io_registry_entry_t) -> Bool {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, "IOService", &parent) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(parent) }
        return stringProperty(parent, "EPICProviderClass") == "AppleDCPMCDP29XX"
    }
}
