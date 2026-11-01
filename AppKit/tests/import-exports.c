/* Own-build export/load regression. Never use this on Apple images. */
#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    void *image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!image) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
    const char *symbols[] = { "NSAboutPanelOptionApplicationIcon",
        "NSAboutPanelOptionApplicationName",
        "NSAboutPanelOptionApplicationVersion",
        "NSAccessibilityRequiredAttribute",
        "NSFilterPredicateBinding",
        "NSPredicateBinding",
        "NSMaxValueBinding",
        "NSTextContentTypeURL",
        "NSSplitViewItemUnspecifiedDimension",
        "NSTouchBarItemIdentifierCandidateList",
        "NSToolbarInspectorTrackingSeparatorItemIdentifier",
        "NSToolbarSidebarTrackingSeparatorItemIdentifier",
        "NSToolbarToggleInspectorItemIdentifier",
        "NSToolbarToggleSidebarItemIdentifier",
        "NSToolbarWritingToolsItemIdentifier",
        "OBJC_CLASS_$_NSMenuToolbarItem",
        "OBJC_METACLASS_$_NSMenuToolbarItem",
        "OBJC_CLASS_$_NSMenuItemBadge",
        "OBJC_METACLASS_$_NSMenuItemBadge",
        "OBJC_CLASS_$_NSGlassEffectContainerView",
        "OBJC_METACLASS_$_NSGlassEffectContainerView",
        "OBJC_CLASS_$_NSSplitViewItemAccessoryViewController",
        "OBJC_METACLASS_$_NSSplitViewItemAccessoryViewController",
        "OBJC_CLASS_$_NSWritingToolsCoordinator",
        "OBJC_METACLASS_$_NSWritingToolsCoordinator",
        "OBJC_CLASS_$_NSSharingServicePickerToolbarItem",
        "OBJC_METACLASS_$_NSSharingServicePickerToolbarItem",
        "OBJC_CLASS_$_NSTextInsertionIndicator",
        "OBJC_METACLASS_$_NSTextInsertionIndicator" };
    int failed = 0;
    for (unsigned i = 0; i < sizeof(symbols)/sizeof(*symbols); ++i) {
        dlerror();
        void *address = dlsym(image, symbols[i]);
        const char *error = dlerror();
        if (!address || error) { fprintf(stderr, "missing %s: %s\n", symbols[i], error ? error : "null"); failed = 1; }
    }
    // Keep Objective-C image metadata alive until process exit.
    if (!failed) puts("PASS dlopen and every added public export");
    return failed;
}
