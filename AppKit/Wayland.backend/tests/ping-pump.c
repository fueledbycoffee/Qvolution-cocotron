/* Native socketpair compositor: no desktop, GPU, guest, or Apple code. */
#include "WaylandEventPump.h"
#include <wayland-client-protocol.h>
#include <wayland-server-core.h>
#include "xdg-shell-server.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>

static double now(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}
static struct wl_display *server;
static struct wl_resource *wm;
static struct wl_event_source *timer;
static unsigned sent, received, wakes, callbacks;
static double sent_at[32], worst;
static pthread_t main_thread;
static int native_errno(void) { return errno; }
static void wake_main(void *info) { __atomic_add_fetch(&wakes, 1, __ATOMIC_RELAXED); }
static void pong(struct wl_client *client, struct wl_resource *resource, uint32_t serial) {
    assert(serial > 0 && serial <= sent);
    double elapsed = now() - sent_at[serial];
    if (elapsed > worst) worst = elapsed;
    assert(elapsed < 100);
    assert(serial == ++received);
}
static const struct xdg_wm_base_interface wm_impl = {.pong = pong};
static void bind_wm(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    wm = wl_resource_create(client, &xdg_wm_base_interface, 1, id);
    wl_resource_set_implementation(wm, &wm_impl, NULL, NULL);
}
static int tick(void *data) {
    if (wm && sent < 20) {
        ++sent; sent_at[sent] = now();
        xdg_wm_base_send_ping(wm, sent);
        wl_display_flush_clients(server);
    }
    wl_event_source_timer_update(timer, 20);
    return 0;
}
static void *serve(void *data) { wl_display_run(server); return NULL; }
static struct wl_proxy *base;
static WaylandEventPump pump;
static struct WaylandLibrary library;
static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    if (strcmp(interface, "xdg_wm_base")) return;
    base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
    wl_proxy_set_queue(base, pump.queue);
    wl_proxy_add_dispatcher(base, WaylandPingDispatch, &library, &pump);
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {global, removed};
static int callback(const void *impl, void *proxy, uint32_t opcode,
                    const struct wl_message *message, union wl_argument *args) {
    assert(pthread_equal(pthread_self(), main_thread));
    ++callbacks;
    wl_proxy_destroy(proxy);
    return 0;
}
int main(int argc, char **argv) {
    main_thread = pthread_self();
    int sockets[2]; assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    server = wl_display_create(); assert(server);
    assert(wl_client_create(server, sockets[0]));
    assert(wl_global_create(server, &xdg_wm_base_interface, 1, NULL, bind_wm));
    timer = wl_event_loop_add_timer(wl_display_get_event_loop(server), tick, NULL);
    wl_event_source_timer_update(timer, 20);
    pthread_t compositor; assert(pthread_create(&compositor, NULL, serve, NULL) == 0);
    struct wl_display *display = wl_display_connect_to_fd(sockets[1]); assert(display);
#define ASSIGN(name) library.name = name;
    WAYLAND_CLIENT_FUNCTIONS(ASSIGN)
#undef ASSIGN
    library.native_errno = native_errno;
    pump.library = &library; pump.display = display;
    pump.queue = wl_display_create_queue(display); assert(pump.queue);
    pump.wake = wake_main;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    assert(wl_display_roundtrip(display) >= 0 && base);

    // A factory on the ping queue must still produce default-queue callbacks.
    struct wl_proxy *factory = wl_proxy_create_wrapper(display);
    assert(factory); wl_proxy_set_queue(factory, pump.queue);
    union wl_argument args[] = {{.o = NULL}};
    struct wl_proxy *sync = WaylandMainQueueObject(&library,
            factory, WP_DISPLAY_SYNC, &wl_callback_interface, args);
    wl_proxy_wrapper_destroy(factory);
    assert(sync); wl_proxy_add_dispatcher(sync, callback, NULL, NULL);
    assert(wl_display_flush(display) >= 0);
    bool baseline = argc > 1 && !strcmp(argv[1], "--main-thread-reader");
    if (!baseline) assert(WaylandPumpStart(&pump));
    // Deliberately do no application/default-queue work for a full second.
    double until = now() + 1000;
    while (now() < until) {}
    assert(callbacks == 0);
    assert(wl_display_dispatch_pending(display) >= 0);
    if (!baseline) {
        assert(callbacks == 1 && __atomic_load_n(&wakes, __ATOMIC_RELAXED) > 0);
        WaylandPumpStop(&pump);
        assert(!__atomic_load_n(&pump.error, __ATOMIC_ACQUIRE));
    }
    wl_display_terminate(server);
    // Wake the server's event loop without signalling another process.
    wl_display_flush(display);
    pthread_join(compositor, NULL);
    printf("pings=%u pongs=%u max_rtt_ms=%.3f default_callbacks=%u\n",
           sent, received, worst, callbacks);
    assert(received == 20);
    wl_proxy_destroy(base); wl_registry_destroy(registry);
    wl_event_queue_destroy(pump.queue); wl_display_disconnect(display);
    wl_display_destroy_clients(server); wl_display_destroy(server);
    return 0;
}
