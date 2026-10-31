# Online display membership

CGDisplayIsOnline now reports membership in one owned snapshot of the existing
supported online-display list. It does not return constant true or alias the
active-display predicate. Apple's public API distinguishes connection/online
state from drawing availability; an online hardware mirror need not be active.
The online list can include outputs that are mirrored or asleep.

The current X11/Wayland abstraction supplies NSScreen objects rather than a
separate physical connector, mirroring or power inventory. Therefore this mapping
uses exactly the supported reported screen set, including an empty-frame screen
when one is supplied. It cannot discover extra connected displays that a backend
does not report, nor independently verify hardware hotplug, power or mirror state.
The already-existing virtual Display1 fallback is retained when the backend has
no screens. That is explicit project compatibility policy, not physical hardware
evidence. Null and absent IDs return false; changes are observed on later calls.

CGGetOnlineDisplayList and the predicate share the owned ID snapshot. This is a per-query backend snapshot, not an atomic physical inventory or a
consistency promise across separate API calls. The main
output is selected from that same retained screen array, avoiding multiple backend
queries and a count-then-buffer allocation race. Existing numeric IDs, main-first
ordering, virtual fallback and caller-visible full-count/truncated-array policy
are preserved. This change does not claim to repair the older enumeration count
contract or active/asleep/mirroring APIs. CGMainDisplayID uses the same main-ID
selection logic, with unchanged fallback behavior.

The original public `coregraphics-display-online.m` first confirms the existing
online list, then checks the new symbol through dlsym and verifies every reported
ID plus null/absent negatives. Parent failed the symbol check: exit 1 in 1.720s,
exact-prefix shutdown 0. The original `coregraphics-display-online-topology.m`
invokes the actual CoreGraphics functions with a controlled own-backend screens
method. Only that owned method is temporarily replaced, and restored afterward;
CoreGraphics functions are never interposed. It checks an online/non-active
empty-frame screen, noncontiguous/high-bit IDs, changed topology, one backend
read even when the producer would change after the first call, and the explicit
empty-topology virtual fallback. No host topology, physical names, desktop input,
wire proxies or vendor code are changed/inspected. This is a boundary fixture,
not an actual physical hotplug acceptance test.

Actual production object and both original fixture executables compile using
copied real recipes. Candidate runtime and official KeePassXC retake remain
coordinator-owned staging gates. No application qualification is implied.

Provenance: repository CGGetOnlineDisplayList, CGGetActiveDisplayList and backend
NSScreen/ID topology (rung 2); Apple's public API documentation (rung 3):
https://developer.apple.com/documentation/coregraphics/cgdisplayisonline(_:)
https://developer.apple.com/documentation/coregraphics/cggetonlinedisplaylist(_:_:_:)
https://developer.apple.com/documentation/coregraphics/cgdisplayisactive(_:)
Original fixtures are rung 4 after coordinator execution. No Apple binaries,
local SDK internals, disassembly or imported vendor implementations were used.
