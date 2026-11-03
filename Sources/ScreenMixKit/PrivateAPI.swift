import Foundation
import CoreGraphics
import IOKit

/// Resolves the private IOKit / CoreDisplay symbols that are needed to talk DDC/CI to a
/// display on Apple Silicon Macs.
///
/// Everything is resolved lazily through `dlsym` instead of declaring the symbols at link
/// time. That has two advantages:
///   * the binary also starts on systems where a symbol does not exist (the display is then
///     reported as "no DDC" instead of crashing on launch)
///   * the very same binary works on Intel Macs, where `IOAVService*` does not exist at all.
final class PrivateAPI {
    static let shared = PrivateAPI()

    // All types below are plain C types on purpose: `@convention(c)` function types may only
    // contain C representable values.
    typealias CreateWithServiceFn = @convention(c) (UnsafeRawPointer?, io_service_t) -> UnsafeMutableRawPointer?
    typealias CreateFn = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias ReadI2CFn = @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt32, UnsafeMutableRawPointer?, UInt32) -> kern_return_t
    typealias WriteI2CFn = @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt32, UnsafeMutableRawPointer?, UInt32) -> kern_return_t
    typealias DisplayInfoFn = @convention(c) (CGDirectDisplayID) -> UnsafeMutableRawPointer?

    let createAVServiceWithService: CreateWithServiceFn?
    let createAVService: CreateFn?
    let readI2C: ReadI2CFn?
    let writeI2C: WriteI2CFn?
    let displayInfoDictionary: DisplayInfoFn?

    private init() {
        let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        let coreDisplay = dlopen("/System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)

        func resolve<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, _ type: T.Type) -> T? {
            guard let handle, let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: T.self)
        }

        createAVServiceWithService = resolve(iokit, "IOAVServiceCreateWithService", CreateWithServiceFn.self)
        createAVService = resolve(iokit, "IOAVServiceCreate", CreateFn.self)
        readI2C = resolve(iokit, "IOAVServiceReadI2C", ReadI2CFn.self)
        writeI2C = resolve(iokit, "IOAVServiceWriteI2C", WriteI2CFn.self)
        displayInfoDictionary = resolve(coreDisplay, "CoreDisplay_DisplayCreateInfoDictionary", DisplayInfoFn.self)
    }

    /// True when the Apple Silicon DDC backend can be used on this machine.
    var supportsIOAVService: Bool {
        readI2C != nil && writeI2C != nil && (createAVServiceWithService != nil || createAVService != nil)
    }

    /// Creates an `IOAVServiceRef` for a `DCPAVServiceProxy` IORegistry entry.
    ///
    /// The returned object is intentionally *not* released: the reference is cached for the
    /// whole lifetime of the process by the transport, leaking one tiny IOKit object per
    /// display at worst - far better than guessing the ownership convention wrong and
    /// over-releasing a kernel object.
    func avService(for entry: io_service_t) -> UnsafeMutableRawPointer? {
        if let createAVServiceWithService {
            return createAVServiceWithService(nil, entry)
        }
        if let createAVService {
            return createAVService(nil)
        }
        return nil
    }

    /// Dictionary that belongs to a `CGDirectDisplayID`, containing keys such as
    /// `IODisplayLocation` and `DisplayProductName`.
    func displayInfo(for displayID: CGDirectDisplayID) -> [String: Any]? {
        guard let displayInfoDictionary, let pointer = displayInfoDictionary(displayID) else { return nil }
        let dictionary = Unmanaged<NSDictionary>.fromOpaque(pointer).takeRetainedValue()
        return dictionary as? [String: Any]
    }
}
