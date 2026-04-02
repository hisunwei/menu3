import Foundation

// MARK: - MultitouchSupport.framework private API bindings

typealias MTDeviceRef = UnsafeMutableRawPointer

// Callback receives raw touch data — we only need the count
typealias MTContactCallbackFunction = @convention(c) (
    MTDeviceRef,             // device
    UnsafeRawPointer,        // touches (array of touch structs)
    Int32,                   // touchCount
    Double,                  // timestamp
    Int32                    // frame
) -> Void

// Each touch struct is ~128 bytes. The phase field is at offset 12 (after frame:i32 + timestamp:f64 + identifier:i32)
// Layout: frame(4) + timestamp(8) + identifier(4) + phase(4) ...
let kMTTouchPhaseOffset = 16  // bytes from start of each touch
let kMTTouchStructSize = 128  // approximate size, may vary

func mtTouchPhase(at index: Int, in touches: UnsafeRawPointer) -> Int32 {
    touches.advanced(by: index * kMTTouchStructSize + kMTTouchPhaseOffset)
        .assumingMemoryBound(to: Int32.self).pointee
}

@_silgen_name("MTDeviceCreateList")
func MTDeviceCreateList() -> CFArray

@_silgen_name("MTRegisterContactFrameCallback")
func MTRegisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactCallbackFunction)

@_silgen_name("MTDeviceStart")
func MTDeviceStart(_ device: MTDeviceRef, _ mode: Int32)

@_silgen_name("MTDeviceStop")
func MTDeviceStop(_ device: MTDeviceRef)
