/* Socketpair protocol peer using public wayland.xml/xdg-shell.xml wire messages.
 * Avoids SO_PEERCRED, unavailable in restricted native test sandboxes. */
#include "WaylandEventPump.h"
#include <wayland-client-protocol.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>

static double now(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}
static int peer_fd, peer_stop[2];
static unsigned sent, received, wakes, callbacks;
static double sent_at[32], worst;
static pthread_t main_thread;
static struct WaylandLibrary library;
static WaylandEventPump pump;
static struct wl_proxy *base;
static int injected;
static int native_errno(void) { return injected ? 11 : errno; }
static int flush_with_backpressure(struct wl_display *display) {
    // Exercise the production POLLOUT/cancel-read retry path.
    if (injected < 3) { ++injected; return -1; }
    return wl_display_flush(display);
}
static void wake_main(void *info) { __atomic_add_fetch(&wakes, 1, __ATOMIC_RELAXED); }
static void exact_read(int fd, void *bytes, size_t length) {
    char *p = bytes;
    while (length) {
        ssize_t n = read(fd, p, length); assert(n > 0);
        p += n; length -= n;
    }
}
static void send_words(uint32_t object, uint16_t opcode, const uint32_t *body, unsigned words) {
    uint32_t frame[64] = {object, ((words + 2) * 4) << 16 | opcode};
    assert(words < 62); memcpy(frame + 2, body, words * 4);
    assert(write(peer_fd, frame, (words + 2) * 4) == (ssize_t)((words + 2) * 4));
}
static void *serve(void *unused) {
    uint32_t registry = 0, wm = 0;
    double next_ping = now() + 20;
    for (;;) {
        struct pollfd fds[] = {{peer_fd, POLLIN, 0}, {peer_stop[0], POLLIN, 0}};
        int r = poll(fds, 2, 5); assert(r >= 0);
        if (fds[1].revents) break;
        if (fds[0].revents & POLLIN) {
            uint32_t header[2], body[64];
            exact_read(peer_fd, header, 8);
            unsigned size = header[1] >> 16, opcode = header[1] & 0xffff;
            assert(size >= 8 && size <= sizeof(body) && size % 4 == 0);
            exact_read(peer_fd, body, size - 8);
            if (header[0] == 1 && opcode == WP_DISPLAY_GET_REGISTRY) {
                registry = body[0];
                uint32_t global[6] = {7, 12, 0, 0, 0, 1};
                memcpy(global + 2, "xdg_wm_base", 12);
                send_words(registry, WP_REGISTRY_EV_GLOBAL, global, 6);
            } else if (header[0] == 1 && opcode == WP_DISPLAY_SYNC) {
                uint32_t done = 0, id = body[0];
                send_words(id, 0, &done, 1);
                send_words(1, 1, &id, 1); // wl_display.delete_id
            } else if (header[0] == registry && opcode == WP_REGISTRY_BIND) {
                assert(body[0] == 7); wm = body[(size - 8) / 4 - 1];
            } else if (header[0] == wm && opcode == WP_WM_BASE_PONG) {
                uint32_t serial = body[0];
                assert(serial > 0 && serial <= sent && serial == ++received);
                double elapsed = now() - sent_at[serial];
                if (elapsed > worst) worst = elapsed;
                assert(elapsed < 100);
            } else assert(!"unexpected client request");
        }
        if (wm && sent < 20 && now() >= next_ping) {
            ++sent; sent_at[sent] = now();
            send_words(wm, WP_WM_BASE_EV_PING, &sent, 1);
            next_ping = now() + 20;
        }
    }
    return NULL;
}
static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    assert(!strcmp(interface, "xdg_wm_base"));
    base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
    wl_proxy_set_queue(base, pump.queue);
    wl_proxy_add_dispatcher(base, WaylandPingDispatch, &library, &pump);
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {global, removed};
static int callback(const void *impl, void *proxy, uint32_t opcode,
                    const struct wl_message *message, union wl_argument *args) {
    assert(pthread_equal(pthread_self(), main_thread));
    ++callbacks; wl_proxy_destroy(proxy); return 0;
}
int main(int argc, char **argv) {
    main_thread = pthread_self();
    int sockets[2]; assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    peer_fd = sockets[0]; assert(pipe(peer_stop) == 0);
    pthread_t peer; assert(pthread_create(&peer, NULL, serve, NULL) == 0);
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
    // A factory assigned to the ping queue must still create a default child.
    struct wl_proxy *factory = wl_proxy_create_wrapper(display);
    assert(factory); wl_proxy_set_queue(factory, pump.queue);
    union wl_argument args[] = {{.o = NULL}};
    struct wl_proxy *sync = WaylandMainQueueObject(&library,
            factory, WP_DISPLAY_SYNC, &wl_callback_interface, args);
    wl_proxy_wrapper_destroy(factory);
    assert(sync); wl_proxy_add_dispatcher(sync, callback, NULL, NULL);
    assert(wl_display_flush(display) >= 0);
    bool baseline = argc > 1 && !strcmp(argv[1], "--main-thread-reader");
    library.wl_display_flush = flush_with_backpressure;
    if (!baseline) assert(WaylandPumpStart(&pump));
    double until = now() + 1000;
    while (now() < until) {} // No main-thread dispatch for one second.
    assert(callbacks == 0);
    assert(wl_display_dispatch_pending(display) >= 0);
    if (!baseline) {
        assert(callbacks == 1 && __atomic_load_n(&wakes, __ATOMIC_RELAXED) > 0);
        WaylandPumpStop(&pump);
        assert(!__atomic_load_n(&pump.error, __ATOMIC_ACQUIRE));
    }
    assert(write(peer_stop[1], "x", 1) == 1); pthread_join(peer, NULL);
    printf("pings=%u pongs=%u max_rtt_ms=%.3f default_callbacks=%u backpressure_retries=%d\n",
           sent, received, worst, callbacks, injected);
    fflush(stdout); assert(received == 20);
    // A disconnected compositor must wake the main source and stop cleanly.
    assert(WaylandPumpStart(&pump)); close(peer_fd);
    until = now() + 1000;
    while (!__atomic_load_n(&pump.error, __ATOMIC_ACQUIRE) && now() < until) usleep(1000);
    assert(__atomic_load_n(&pump.error, __ATOMIC_ACQUIRE)); WaylandPumpStop(&pump);
    wl_proxy_destroy(base); wl_registry_destroy(registry);
    wl_event_queue_destroy(pump.queue); wl_display_disconnect(display);
    close(peer_stop[0]); close(peer_stop[1]);
    puts("disconnect_wake_and_join=true");
    return 0;
}
