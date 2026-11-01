# x86_64 applications bind these Swift imports to CoreGraphics.framework.
# A successful configuration must not silently ship a framework without them.
set(DARLING_COREGRAPHICS_SWIFTC "" CACHE FILEPATH "Darwin-capable Swift compiler")
set(DARLING_COREGRAPHICS_SWIFT_RESOURCE_DIR "" CACHE PATH "Source-built Darwin Swift resource directory")
set(DARLING_COREGRAPHICS_SWIFT_MODULES_DIR "" CACHE PATH "Matching source-built Darwin overlay modules")
if(BUILD_TARGET_64BIT AND APPLE_ARCH_64BIT STREQUAL "x86_64")
    foreach(input DARLING_COREGRAPHICS_SWIFTC DARLING_COREGRAPHICS_SWIFT_RESOURCE_DIR
                  DARLING_COREGRAPHICS_SWIFT_MODULES_DIR)
        if(NOT ${input} OR NOT EXISTS "${${input}}")
            message(FATAL_ERROR
                "CoreGraphics requires ${input}; see CoreGraphics/SWIFT-BUILD.md. Required Swift imports cannot be omitted.")
        endif()
    endforeach()
    foreach(module Swift _Concurrency _StringProcessing)
        if(NOT EXISTS "${DARLING_COREGRAPHICS_SWIFT_RESOURCE_DIR}/macosx/${module}.swiftmodule")
            message(FATAL_ERROR "CoreGraphics requires source-built Darwin ${module}.swiftmodule; see CoreGraphics/SWIFT-BUILD.md")
        endif()
    endforeach()
    foreach(module CoreFoundation Darwin ObjectiveC Dispatch)
        if(NOT EXISTS "${DARLING_COREGRAPHICS_SWIFT_MODULES_DIR}/${module}.swiftmodule")
            message(FATAL_ERROR "CoreGraphics requires matching ${module}.swiftmodule; see CoreGraphics/SWIFT-BUILD.md")
        endif()
    endforeach()
endif()
