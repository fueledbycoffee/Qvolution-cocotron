# Screen color-space API bridge

Apple documents [NSScreen.colorSpace](https://developer.apple.com/documentation/appkit/nsscreen/colorspace) as an optional NSColorSpace property (clean-room rung3). Existing CGDisplayCopyColorSpace and NSColorSpace.initWithCGColorSpace supply the mapping (rung2). The current CoreGraphics implementation returns DeviceRGB; this change exposes that provider without claiming a physical ICC profile, DisplayP3 or color-managed display output.

Build appkit-screen-colorspace.m linked to AppKit and CoreGraphics. Run against an actual backend with displays. It checks selector availability, display-provider model/component agreement, current backend RGB availability and retained ownership past an autorelease pool. It does not prove profile identity or color accuracy.

The unchanged vendor KeePassXC distribution reached Qt's Wayland setup and raised an unrecognized colorSpace selector on WaylandScreen. The original public API fixture fails on the parent runtime at selector availability, with exact-prefix shutdown succeeding. Candidate and unchanged-app retakes must be recorded separately after staging.
