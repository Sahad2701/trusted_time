#include "include/trusted_time/trusted_time_plugin.h"
#include <atomic>
#include <cstring>
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <poll.h>
#include <sys/timerfd.h>
#include <sys/utsname.h>
#include <thread>
#include <unistd.h>

#include "trusted_time_plugin_private.h"

#define TRUSTED_TIME_PLUGIN(obj)                                               \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), trusted_time_plugin_get_type(),           \
                              TrustedTimePlugin))

// PluginContext
// Owns the background thread and the timerfd. All members except event_channel
// are accessed only from the worker thread or from GLib main-loop callbacks —
// no mutex is needed beyond the atomic is_listening flag, which provides the
// visibility barrier required for the worker to see cancel_cb's writes.

struct PluginContext {
  std::thread worker_thread;
  int timer_fd = -1;
  std::atomic<bool> is_listening{false};
  FlEventChannel *event_channel = nullptr;
};

struct _TrustedTimePlugin {
  GObject parent_instance;
  PluginContext *context;
};

G_DEFINE_TYPE(TrustedTimePlugin, trusted_time_plugin, g_object_get_type())

// GLib idle callback — emits the clockJumped event on the main thread

static gboolean emit_clock_jumped_cb(gpointer user_data) {
  PluginContext *context = static_cast<PluginContext *>(user_data);
  // Double-check is_listening because cancel_cb may have run between the
  // g_idle_add call in the worker thread and this callback being dispatched.
  if (context->is_listening && context->event_channel != nullptr) {
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "type", fl_value_new_string("clockJumped"));
    fl_event_channel_send(context->event_channel, map, nullptr, nullptr);
  }
  return G_SOURCE_REMOVE;
}

// Helper: (re)arm the timerfd 100 years into the future
// The timer is set far in the future so it does not fire normally. Its only
// purpose is to be cancelled by a CLOCK_REALTIME change, which causes poll()
// to return and read() to fail with ECANCELED.
//
// IMPORTANT: TFD_TIMER_CANCEL_ON_SET is only effective when combined with
// TFD_TIMER_ABSTIME. Using a relative timer would silently ignore the flag.

static void arm_timer(int fd) {
  struct timespec now;
  clock_gettime(CLOCK_REALTIME, &now);
  struct itimerspec its;
  memset(&its, 0, sizeof(its));
  its.it_value.tv_sec = now.tv_sec + (100LL * 365 * 24 * 3600);
  its.it_value.tv_nsec = now.tv_nsec;
  timerfd_settime(fd, TFD_TIMER_ABSTIME | TFD_TIMER_CANCEL_ON_SET, &its,
                  nullptr);
}

// Background worker thread

static void background_worker(PluginContext *context) {
  while (context->is_listening) {
    struct pollfd pfd;
    pfd.fd = context->timer_fd;
    pfd.events = POLLIN;
    pfd.revents = 0;

    int ret = poll(&pfd, 1, -1);

    // Exit immediately if cancel_cb has run.
    if (!context->is_listening)
      break;

    if (ret > 0) {
      // FIX L1 + L3: check all relevant revents, not just POLLIN.
      //
      // When TFD_TIMER_CANCEL_ON_SET fires (clock changed), the kernel marks
      // the timerfd as readable but read() returns -1/ECANCELED. Depending on
      // the kernel version, poll() may set POLLERR instead of (or in addition
      // to) POLLIN. Checking only POLLIN misses the cancellation event
      // entirely, so clockJumped was never emitted in the original code.
      //
      // POLLNVAL is set when poll() is called on a file descriptor that has
      // already been closed (cancel_cb set timer_fd=-1 and closed it). The
      // original code did not handle this case, causing the loop to spin
      // forever on the closed fd instead of exiting.

      if (pfd.revents & POLLNVAL) {
        // FIX L3: fd was closed by cancel_cb; exit the thread cleanly.
        break;
      }

      if (pfd.revents & (POLLIN | POLLERR)) {
        // FIX L1/L2: attempt the read regardless of whether the event is
        // POLLIN or POLLERR. On cancellation read() returns -1/ECANCELED.
        uint64_t expirations = 0;
        ssize_t s = read(context->timer_fd, &expirations, sizeof(expirations));

        if (s < 0) {
          if (errno == ECANCELED) {
            // Clock was changed — emit the integrity event on the main thread.
            if (context->is_listening) {
              g_idle_add(emit_clock_jumped_cb, context);
            }
            // Rearm so we continue monitoring future changes.
            arm_timer(context->timer_fd);
          } else if (errno == EBADF) {
            // fd was closed by cancel_cb between poll() returning and read().
            break;
          } else if (errno == EAGAIN) {
            // Spurious wakeup on a non-blocking fd; continue polling.
            continue;
          }
          // Other errors: log or ignore and continue.
        }
        // s >= 0: the far-future timer actually expired (extremely unlikely
        // with a 100-year sentinel, but harmless — just rearm and continue).
      }

    } else if (ret < 0) {
      if (errno == EINTR)
        continue; // Signal interrupted poll; retry.
      break;      // Unexpected error; exit thread.
    }
    // ret == 0: poll() timed out (impossible with timeout=-1, but be safe).
  }
}

// EventChannel stream handlers

static FlMethodErrorResponse *listen_cb(FlEventChannel *channel, FlValue *args,
                                        gpointer user_data) {
  TrustedTimePlugin *plugin = TRUSTED_TIME_PLUGIN(user_data);
  PluginContext *context = plugin->context;

  // Idempotency guard — ignore a second listen while already subscribed.
  if (context->is_listening) {
    return nullptr;
  }

  context->timer_fd =
      timerfd_create(CLOCK_REALTIME, TFD_NONBLOCK | TFD_CLOEXEC);
  if (context->timer_fd < 0) {
    return fl_method_error_response_new("TIMERFD_CREATE_FAILED",
                                        "timerfd_create() failed", nullptr);
  }

  arm_timer(context->timer_fd);

  context->is_listening = true;
  context->worker_thread = std::thread(background_worker, context);

  return nullptr;
}

static FlMethodErrorResponse *cancel_cb(FlEventChannel *channel, FlValue *args,
                                        gpointer user_data) {
  TrustedTimePlugin *plugin = TRUSTED_TIME_PLUGIN(user_data);
  PluginContext *context = plugin->context;

  if (!context->is_listening) {
    return nullptr;
  }

  // Signal the worker to stop, then close the fd.
  // Closing the fd unblocks poll() — it will return with POLLNVAL (FIX L3),
  // the worker checks is_listening (false) and also checks POLLNVAL, then
  // exits. We can then safely join.
  context->is_listening = false;

  if (context->timer_fd != -1) {
    close(context->timer_fd);
    context->timer_fd = -1;
  }

  if (context->worker_thread.joinable()) {
    context->worker_thread.join();
  }

  return nullptr;
}

// GObject lifecycle

static void trusted_time_plugin_dispose(GObject *object) {
  TrustedTimePlugin *self = TRUSTED_TIME_PLUGIN(object);
  if (self->context) {
    // Reuse the same teardown logic as cancel_cb.
    if (self->context->is_listening) {
      self->context->is_listening = false;
      if (self->context->timer_fd != -1) {
        close(self->context->timer_fd);
        self->context->timer_fd = -1;
      }
      if (self->context->worker_thread.joinable()) {
        self->context->worker_thread.join();
      }
    }
    if (self->context->event_channel) {
      g_clear_object(&self->context->event_channel);
    }
    delete self->context;
    self->context = nullptr;
  }
  G_OBJECT_CLASS(trusted_time_plugin_parent_class)->dispose(object);
}

static void trusted_time_plugin_class_init(TrustedTimePluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = trusted_time_plugin_dispose;
}

static void trusted_time_plugin_init(TrustedTimePlugin *self) {
  self->context = new PluginContext();
}

// Method channel handler

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar *method = fl_method_call_get_name(method_call);

  if (strcmp(method, "getPlatformVersion") == 0) {
    struct utsname uname_data = {};
    uname(&uname_data);
    g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
    g_autoptr(FlValue) result = fl_value_new_string(version);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "getUptimeMs") == 0) {
    // CLOCK_BOOTTIME is identical to CLOCK_MONOTONIC but also counts time
    // during which the system was suspended — essential for accurate uptime
    // tracking on laptops and embedded devices. Available since kernel 2.6.39,
    // which predates all supported Ubuntu LTS, Fedora, and Debian stable
    // releases.
    struct timespec ts;
    clock_gettime(CLOCK_BOOTTIME, &ts);
    int64_t uptimeMs =
        static_cast<int64_t>(ts.tv_sec) * 1000 + ts.tv_nsec / 1000000;
    g_autoptr(FlValue) result = fl_value_new_int(uptimeMs);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "enableBackgroundSync") == 0) {
    // Stubbed: Dart Timer.periodic handles scheduling on desktop where the
    // app process runs persistently. Native OS schedulers (systemd timers)
    // would require privileges this plugin does not hold.
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// Exposed for unit testing (see trusted_time_plugin_private.h).
FlMethodResponse *get_platform_version() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// Plugin registration

void trusted_time_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  TrustedTimePlugin *plugin = TRUSTED_TIME_PLUGIN(
      g_object_new(trusted_time_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  // Monotonic clock channel.
  g_autoptr(FlMethodChannel) monotonic_channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "trusted_time/monotonic", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      monotonic_channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  // Background sync channel (stub).
  g_autoptr(FlMethodChannel) bg_channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "trusted_time/background", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      bg_channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  // Integrity event channel.
  plugin->context->event_channel =
      fl_event_channel_new(fl_plugin_registrar_get_messenger(registrar),
                           "trusted_time/integrity", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->context->event_channel,
                                       listen_cb, cancel_cb,
                                       g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}