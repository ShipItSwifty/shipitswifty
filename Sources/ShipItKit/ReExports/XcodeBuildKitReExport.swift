#if os(macOS)
// Re-export XcodeBuildKit so consumers of ShipItKit get access to
// XcodeBuild, XcodeBuildOption, XcodeSelect, DestinationDiscovery, etc.
@_exported import XcodeBuildKit
#endif
