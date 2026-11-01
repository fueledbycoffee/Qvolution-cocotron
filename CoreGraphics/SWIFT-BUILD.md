# Required x86_64 Swift imports

The ordinary x86_64 CMake build requires the CoreGraphics Swift supplement.
Configuration fails with an actionable error if any input is missing; there is
no opt-out that produces a successful but incomplete framework. Other target
architectures retain their existing overlay path.

Supply these three cache variables to the normal superproject configure:

```
cmake -S <darling-source> -B <build> -G Ninja \
  -DDARLING_COREGRAPHICS_SWIFTC=<swift-toolchain>/usr/bin/swiftc \
  -DDARLING_COREGRAPHICS_SWIFT_RESOURCE_DIR=<darwin-resources>/lib/swift \
  -DDARLING_COREGRAPHICS_SWIFT_MODULES_DIR=<matching-overlay-modules> \
  -DENABLE_TESTS=ON
ninja -C <build> -j6 CoreGraphics imp_graphics_layer_test imp_graphics_swift_test
ninja -C <build> -n CoreGraphics imp_graphics_layer_test imp_graphics_swift_test
```

On the fleet host wrap build/install commands with `dashboard/qv-slot build`.
Use a Darwin-capable compiler and Darwin stdlib modules built from the same
published Swift source release, together with source-built Darwin, ObjectiveC,
Dispatch and CoreFoundation modules from Darling's Swift overlays. The reviewed
integration uses Swift 6.3.3, target x86_64-apple-macosx26.0 and Swift 5 language
mode. Do not substitute Linux stdlib modules, Apple binary SDK resources, or
handwritten Swift ABI metadata. Resource/module existence is checked at
configure time; compiler compatibility is checked by actually compiling.

CMake builds the supplement, reexports it from CoreGraphics, and installs it
under `libexec/darling/usr/lib/swift/libswiftCoreGraphicsImports.dylib`.
Preserve that install rule when combining overlays. The generated
`CoreGraphics/SwiftImports/CoreGraphics.swiftmodule` in the build tree is the
module used by the separate regression client; it is a build artifact, not
checked-in metadata. Run that linked client and the export-load test under
Darling with the matching Swift runtime before accepting the runtime gate.
