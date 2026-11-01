project(CoreGraphics)

include(darling_framework)

remove_sdk_framework(CoreGraphics)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} \
	-include math.h \
	-include stdlib.h \
	-include CoreFoundation/CoreFoundation.h \
	-Wno-nonportable-include-path \
	-mmacosx-version-min=10.10"
)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PC_CAIRO cairo)

set_property(SOURCE 
	CGAffineTransform.m
	CGBitmapContext.m
	CGColor.m
	CGColorSpace.m
	CGContext.m
	CGDataConsumer.m
	CGDataProvider.m
	CGDirectDisplay.m
	CGDisplayConfiguration.m
	CGFont.m
	CGFunction.m
	CGGeometry.m
	CGGradient.m
	CGImageDestination.m
	CGImage.m
	CGImageProperties.m
	CGImageSource.m
	CGLayer.m
	CGLPixelSurface.m
	CGPath.m
	CGPattern.m
	CGPDFContext.m
	CGPDFDictionary.m
	CGPDFDocument.m
	CGPDFPage.m
	CGPDFString.m
	CGPSConverter.m
	CGRemoteOperation.m
	CGShading.m
	CGWindow.m
	CGWindowLevel.m
	CGSubWindow.m
	CGS.m
	CGSConnection.m
	CGSWindow.m
	CGSSurface.m
	CGSRegion.m

	APPEND PROPERTY COMPILE_FLAGS "-include Foundation/Foundation.h"
)

include_directories(
	${CMAKE_SOURCE_DIR}/src/external/icu/icuSources/i18n
	${CMAKE_SOURCE_DIR}/src/external/icu/icuSources/common

	${CMAKE_CURRENT_SOURCE_DIR}
	${CMAKE_CURRENT_SOURCE_DIR}/..
	${CMAKE_CURRENT_SOURCE_DIR}/../CoreText

	${PC_CAIRO_INCLUDE_DIRS}
)

set(CoreGraphics_sources
	CGImportSupport.m
	CGAffineTransform.m
	CGBitmapContext.m
	CGColor.m
	CGColorSpace.m
	CGContext.m
	CGDataConsumer.m
	CGDataProvider.m
	CGDirectDisplay.m
	CGDisplayConfiguration.m
	CGDisplayStream.m
	src/CGEvent.c
	src/CGColorMatching.c
	src/stubs.c
	CGFont.m
	CGFunction.m
	CGGeometry.m
	CGGradient.m
	CGImage.m
	CGLayer.m
	CGLPixelSurface.m
	CGPath.m
	CGPattern.m
	CGPDFContext.m
	CGPDFDictionary.m
	CGPDFDocument.m
	CGPDFPage.m
	CGPDFString.m
	CGShading.m
	CGWindow.m
	CGWindowLevel.m
	CGSubWindow.m
	CGDisplayFade.m
	CGS.m
	CGSConnection.m
	CGSWindow.m
	CGSSurface.m
	CGSKeyboardLayout.m
	CGSRegion.m
	CGSScreen.m
	CGEvent.m
	CGEventSource.m
	CGEventTap.m
	CGEventObjC.m
	# KTFont+PDF.m 'KGPDFArray.h' file not found
)

set_source_files_properties(${CoreGraphics_sources} LANGUAGE C)

set(DYLIB_COMPAT_VERSION "64.0.0")
set(DYLIB_CURRENT_VERSION "1070.22.0")

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(CoreGraphics
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/CoreGraphics"
)

add_framework(CoreGraphics
	FAT
	CURRENT_VERSION
	SOURCES
		${CoreGraphics_sources}
	VERSION ${FRAMEWORK_VERSION}
	DEPENDENCIES
		objc
		system
		CoreFoundation
		Foundation
		Onyx2D
		GL
		IOKit
)

# Since macOS 14 the CoreGraphics Swift overlay is part of CoreGraphics.framework, so apps bind symbols such as
# $sSo12CGContextRefa12CoreGraphicsE7addLine2toySo7CGPointV_tF to CoreGraphics. Re-export the overlay from
# src/external/swift (installed as /usr/lib/swift/libswiftCoreGraphics.dylib) so those binds resolve.
set_property(TARGET CoreGraphics APPEND_STRING PROPERTY
	LINK_FLAGS " -Wl,-reexport_library,${CMAKE_SOURCE_DIR}/src/external/swift/libswiftCoreGraphics.dylib -Wl,-rpath,/usr/lib/swift ")

# The x86_64 import supplement is required, with compiler-generated Swift ABI.
include("${CMAKE_CURRENT_SOURCE_DIR}/SwiftToolchain.cmake")
if(BUILD_TARGET_64BIT AND APPLE_ARCH_64BIT STREQUAL "x86_64")
    set(import_object "${CMAKE_CURRENT_BINARY_DIR}/SwiftImports/CoreGraphicsImports.o")
    set(import_module "${CMAKE_CURRENT_BINARY_DIR}/SwiftImports/CoreGraphics.swiftmodule")
    file(GLOB_RECURSE import_headers "${CMAKE_CURRENT_SOURCE_DIR}/include/CoreGraphics/*.h")
    add_custom_command(OUTPUT "${import_object}" "${import_module}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/SwiftImports"
        COMMAND "${DARLING_COREGRAPHICS_SWIFTC}" -frontend -c
            "${CMAKE_CURRENT_SOURCE_DIR}/SwiftImportSupport.swift"
            -target x86_64-apple-macosx26.0
            -sdk "${CMAKE_SOURCE_DIR}/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
            -resource-dir "${DARLING_COREGRAPHICS_SWIFT_RESOURCE_DIR}"
            -module-cache-path "${CMAKE_CURRENT_BINARY_DIR}/SwiftImports/module-cache"
            -module-name CoreGraphics -enable-library-evolution -parse-as-library -swift-version 5 -O
            -I "${DARLING_COREGRAPHICS_SWIFT_MODULES_DIR}"
            -I "${CMAKE_CURRENT_SOURCE_DIR}/include"
            -Xcc "-fmodule-map-file=${CMAKE_SOURCE_DIR}/src/external/swift/overlays/shims/overlay-shims.modulemap"
            -Xcc "-I${CMAKE_SOURCE_DIR}/src/frameworks/CoreServices/include"
            -emit-module-path "${import_module}"
            -o "${import_object}"
        DEPENDS SwiftImportSupport.swift ${import_headers}
        VERBATIM)
    set_source_files_properties("${import_object}" PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
    set(DARLING_LIB_64BIT_ONLY TRUE)
    set(DYLIB_INSTALL_NAME "/usr/lib/swift/libswiftCoreGraphicsImports.dylib")
    add_darling_library(swiftCoreGraphicsImports SHARED "${import_object}")
    unset(DARLING_LIB_64BIT_ONLY)
    unset(DYLIB_INSTALL_NAME)
    set_target_properties(swiftCoreGraphicsImports PROPERTIES LINKER_LANGUAGE C)
    # CoreGraphics C calls resolve in the reexporting parent framework. Linking
    # to that target here would introduce a build dependency cycle.
    foreach(entry CGAffineTransformIdentity CGContextFillPath CGContextEOFillPath
        CGContextShowGlyphsAtPositions CGPathMoveToPoint CGPathAddLineToPoint
        CGPathAddCurveToPoint CGPathAddArc CGPathAddPath CGPathAddLines
        CGPathCreateCopyByStrokingPath CGRectIsNull CGRectEqualToRect CGRectStandardize)
        set_property(TARGET swiftCoreGraphicsImports APPEND_STRING PROPERTY LINK_FLAGS " -Wl,-U,_${entry}")
    endforeach()
    target_link_directories(swiftCoreGraphicsImports PRIVATE "${CMAKE_SOURCE_DIR}/src/external/swift")
    target_link_libraries(swiftCoreGraphicsImports PRIVATE system CoreFoundation
        "${CMAKE_SOURCE_DIR}/src/external/swift/libswiftCoreGraphics.dylib"
        "${CMAKE_SOURCE_DIR}/src/external/swift/libswiftObjectiveC.dylib"
        "${CMAKE_SOURCE_DIR}/src/external/swift/libswiftDispatch.dylib"
        "${CMAKE_SOURCE_DIR}/src/external/swift/libswiftCore.dylib"
        "${CMAKE_SOURCE_DIR}/src/external/swift/libswiftCoreFoundation.dylib"
        "${CMAKE_SOURCE_DIR}/src/external/swift/libswiftDarwin.dylib")
    add_dependencies(CoreGraphics swiftCoreGraphicsImports)
    set_property(TARGET CoreGraphics APPEND_STRING PROPERTY LINK_FLAGS
        " -Wl,-reexport_library,${CMAKE_CURRENT_BINARY_DIR}/libswiftCoreGraphicsImports.dylib")
    # ld64 must resolve the reexport while linking clients in the build tree.
    set_property(TARGET CoreGraphics APPEND PROPERTY INTERFACE_LINK_OPTIONS
        "-Wl,-dylib_file,/usr/lib/swift/libswiftCoreGraphicsImports.dylib:${CMAKE_CURRENT_BINARY_DIR}/libswiftCoreGraphicsImports.dylib")
    install(TARGETS swiftCoreGraphicsImports DESTINATION libexec/darling/usr/lib/swift)
endif()

# NSBundle finds the backends through the framework's Resources link.
InstallSymlink("Versions/Current/Resources" "${CMAKE_INSTALL_PREFIX}/libexec/darling/System/Library/Frameworks/CoreGraphics.framework/Resources")

function(add_backend name)
	cmake_parse_arguments(BACKEND "" "INFO_PLIST" "SOURCES;DEPENDENCIES;RESOURCES" ${ARGN})
	set(path "/System/Library/Frameworks/CoreGraphics.framework/Versions/${FRAMEWORK_VERSION}/Resources/Backends/${name}.backend/Contents")
	set(DYLIB_INSTALL_NAME "${path}/MacOS/${name}")

	add_darling_library(${name}_cgbackend SHARED ${BACKEND_SOURCES})
	set_target_properties(${name}_cgbackend PROPERTIES OUTPUT_NAME "${name}" SUFFIX "" PREFIX "")
	make_fat(${name}_cgbackend)

	if (BACKEND_DEPENDENCIES)
		target_link_libraries(${name}_cgbackend PRIVATE ${BACKEND_DEPENDENCIES})
	endif (BACKEND_DEPENDENCIES)

	install(TARGETS ${name}_cgbackend DESTINATION "libexec/darling${path}/MacOS")
	install(FILES ${BACKEND_INFO_PLIST} DESTINATION "libexec/darling${path}" RENAME Info.plist)

	if (BACKEND_RESOURCES)
		while (BACKEND_RESOURCES)
			list(GET BACKEND_RESOURCES 0 res_install_path)
			list(GET BACKEND_RESOURCES 1 res_source_path)
			get_filename_component(res_install_dir ${res_install_path} DIRECTORY)
			get_filename_component(res_install_name ${res_install_path} NAME)
			install(FILES ${res_source_path}
				DESTINATION libexec/darling${path}/Resources/${res_install_dir}
				RENAME ${res_install_name})
			list(REMOVE_AT BACKEND_RESOURCES 0 1)
		endwhile (BACKEND_RESOURCES)
	endif (BACKEND_RESOURCES)
endfunction(add_backend)

add_subdirectory(X11.backend)
add_subdirectory(Wayland.backend)

# HIServices already depends on CoreGraphics. Resolve this one public sibling
# dynamically from ApplicationServices' loaded HIServices image rather than
# introducing a circular build dependency. SPEC.md Round 3 supplies its ABI.
set_property(TARGET CoreGraphics APPEND_STRING PROPERTY
    LINK_FLAGS " -Wl,-U,_GetCurrentProcess ")
if(ENABLE_TESTS)
    add_darling_executable(imp_graphics_layer_test ../tests/graphics-imports/layer-clip.m)
    target_link_libraries(imp_graphics_layer_test CoreGraphics Foundation)
endif()
