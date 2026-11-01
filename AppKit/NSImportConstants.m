/* Clean-room demand additions. Public names: local AppKit documentation index.
 * GUESS: the local index supplies no string values. About-panel and binding
 * spellings follow their public option/binding names; AXRequired follows the
 * accessibility attribute naming scheme. Toolbar/touch-bar identifiers use the
 * symbol spelling as a stable local identifier. No Apple binary was inspected.
 */
#import <AppKit/NSImportConstants.h>

NSString *const NSAboutPanelOptionApplicationIcon = @"ApplicationIcon";
NSString *const NSAboutPanelOptionApplicationName = @"ApplicationName";
NSString *const NSAboutPanelOptionApplicationVersion = @"ApplicationVersion";
NSString *const NSAccessibilityRequiredAttribute = @"AXRequired";
NSString *const NSFilterPredicateBinding = @"filterPredicate";
NSString *const NSPredicateBinding = @"predicate";
NSString *const NSMaxValueBinding = @"maxValue";
NSString *const NSTextContentTypeURL = @"URL";
// GUESS: Apple's public sentinel is unspecified in the local index. Negative
// dimensions cannot be mistaken for a requested positive thickness.
const CGFloat NSSplitViewItemUnspecifiedDimension = -1.0;
#define IDENTIFIER(name) NSString *const name = @#name
IDENTIFIER(NSTouchBarItemIdentifierCandidateList);
IDENTIFIER(NSToolbarInspectorTrackingSeparatorItemIdentifier);
IDENTIFIER(NSToolbarSidebarTrackingSeparatorItemIdentifier);
IDENTIFIER(NSToolbarToggleInspectorItemIdentifier);
IDENTIFIER(NSToolbarToggleSidebarItemIdentifier);
IDENTIFIER(NSToolbarWritingToolsItemIdentifier);
