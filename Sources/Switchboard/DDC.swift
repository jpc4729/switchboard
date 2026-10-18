import CoreGraphics
import Foundation
import IOKit

// DDC/CI input switching (VCP 0x60) over the private Apple Silicon IOAVService API. Packet, checksum,
// timing and retries follow MonitorControl's Arm64DDC.swift
// (https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Support/Arm64DDC.swift);
// the display-to-service lookup follows m1ddc (https://github.com/waydabber/m1ddc/blob/main/sources/ioregistry.m).
// ponytail: Apple Silicon only; Intel Macs need the IOFramebuffer I2C path (IOFBCopyI2CInterfaceForBus), add it in a separate branch if Intel matters.
// ponytail: @_silgen_name calls C with the Swift calling convention, which matches for these plain
// arguments; move the private calls to a C target with a module map if one takes a struct or breaks.

@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ offset: UInt32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn
@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ dataAddress: UInt32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> IOReturn
// Looked up at runtime because the package does not link the private CoreDisplay framework.
private let createInfoDictionary = dlsym(dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY), "CoreDisplay_DisplayCreateInfoDictionary")
    .map { unsafeBitCast($0, to: (@convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?).self) }

/// Blocking calls (up to ~0.5 s); run them off the main thread.
enum DDC {
    private static let chip: UInt8 = 0x37, dataAddress: UInt8 = 0x51, inputCode: UInt8 = 0x60

    /// False in the x86_64 slice of the universal build: the IOAVService path is on Apple silicon only.
    static let isSupported: Bool = {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }()

    /// Current input source, or nil when the display has no DDC service or does not answer.
    // ponytail: returns the low byte only and ignores LG's alternate 0xF4/0x50 input path; read the full UInt16 if a monitor needs it.
    static func readInput(_ id: CGDirectDisplayID) -> UInt8? {
        guard let service = service(for: id) else { return nil }
        var reply = [UInt8](repeating: 0, count: 11)
        return communicate(service, send: [inputCode], reply: &reply) ? reply[9] : nil
    }

    /// Sends Set VCP 0x60; true when the I2C write went through (DDC has no write acknowledgement).
    static func writeInput(_ value: UInt8, to id: CGDirectDisplayID) -> Bool {
        guard let service = service(for: id) else { return false }
        var noReply: [UInt8] = []
        return communicate(service, send: [inputCode, 0, value], reply: &noReply)
    }

    /// MonitorControl's performDDCCommunication: 5 attempts, 2 writes 10 ms apart, read 50 ms later, 20 ms between attempts.
    private static func communicate(_ service: CFTypeRef, send: [UInt8], reply: inout [UInt8]) -> Bool {
        var packet = [0x80 | UInt8(send.count + 1), UInt8(send.count)] + send
        packet.append(packet.reduce(send.count == 1 ? chip << 1 : chip << 1 ^ dataAddress, ^))
        for _ in 0..<5 {
            var ok = false
            for _ in 0..<2 {
                usleep(10_000)
                ok = IOAVServiceWriteI2C(service, UInt32(chip), UInt32(dataAddress), &packet, UInt32(packet.count)) == kIOReturnSuccess
            }
            if !reply.isEmpty {
                usleep(50_000)
                ok = IOAVServiceReadI2C(service, UInt32(chip), 0, &reply, UInt32(reply.count)) == kIOReturnSuccess
                    && isReply(reply, to: send[0])
            }
            if ok { return true }
            usleep(20_000)
        }
        return false
    }

    /// A Get VCP reply that reports the value of `code`: a valid checksum, opcode 0x02, result 0 and the
    /// same VCP code. A busy monitor's null message (6E 80 BE 00…) also has a valid checksum.
    static func isReply(_ reply: [UInt8], to code: UInt8) -> Bool {
        reply.count == 11 && reply.dropLast().reduce(0x50, ^) == reply.last
            && reply[2] == 0x02 && reply[3] == 0 && reply[4] == code
    }

    /// After m1ddc: find the framebuffer (MonitorControl's class names) whose IOService path is the
    /// display's IODisplayLocation, then take the next external DCPAVServiceProxy after it in the registry.
    // ponytail: walks the IORegistry on every call and ignores MCDP29xx adapters (chip 0xB7); cache per display ID or add the chip check if needed.
    private static func service(for id: CGDirectDisplayID) -> CFTypeRef? {
        guard isSupported, let info = createInfoDictionary?(id)?.takeRetainedValue() as? [String: Any],
              let location = info["IODisplayLocation"] as? String else { return nil }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var matched = false
        var name = [CChar](repeating: 0, count: 128) // io_name_t
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { return nil }
            defer { IOObjectRelease(entry) }
            guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { continue }
            switch String(cString: name) {
            case "AppleCLCD2", "IOMobileFramebufferShim":
                var path = [CChar](repeating: 0, count: 512) // io_string_t
                matched = IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS && String(cString: path) == location
            case "DCPAVServiceProxy" where matched:
                let proxyLocation = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
                if proxyLocation == "External" {
                    return IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
                }
            default:
                break
            }
        }
    }
}
