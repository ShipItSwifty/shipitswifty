#if os(macOS)
// Re-export XcodeGenKit so consumers of ShipItKit get access to
// XcodeGen, XcodeGenOption, etc.
@_exported import XcodeGenKit
#endif
