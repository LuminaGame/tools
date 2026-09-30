// The capture state machine against a fake OS layer: every pointer call is
// recorded, none reaches Windows. Built and run by test/windows_native_test.dart
// (or by hand: cmake -S windows/test -B <dir> && cmake --build <dir> and run
// pointer_capture_tests.exe).
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "../pointer_capture.h"

using lumina_mouse_capture::CaptureCallbacks;
using lumina_mouse_capture::Kind;
using lumina_mouse_capture::PointerCapture;
using lumina_mouse_capture::PointerOs;
using lumina_mouse_capture::RawMouseSample;
using lumina_mouse_capture::ScreenPoint;
using lumina_mouse_capture::ScreenRect;

namespace {

HWND const kView = reinterpret_cast<HWND>(0x1000);
HWND const kTop = reinterpret_cast<HWND>(0x2000);
HWND const kOther = reinterpret_cast<HWND>(0x3000);
UINT const kFlush = WM_APP + 7;

// Records every call; the pointer it "moves" is a pair of numbers.
class FakeOs : public PointerOs {
 public:
  std::string env_value;
  HWND top = kTop;
  bool foreground = true;
  ScreenRect client{100, 200, 100 + 1920, 200 + 1080};
  double scale = 1.5;
  ScreenRect virtual_screen{-1920, 0, 1920, 1080};
  ScreenRect primary{0, 0, 1920, 1080};
  ScreenPoint cursor{500, 600};
  int show_counter = 0;
  bool clip_active = false;
  ScreenRect clip;
  HWND raw_target = nullptr;
  bool raw_registered = false;
  std::vector<RawMouseSample> raw_queue;
  int posted_flushes = 0;
  std::vector<std::string> calls;

  // Calls that touch or read the pointer (everything but the environment and
  // window queries).
  int PointerCalls() const {
    int n = 0;
    for (const auto& c : calls) {
      if (c.rfind("query:", 0) != 0) n++;
    }
    return n;
  }
  int Count(const std::string& name) const {
    int n = 0;
    for (const auto& c : calls) {
      if (c == name) n++;
    }
    return n;
  }

  std::string Environment(const char*) override { return env_value; }
  HWND TopLevelOf(HWND) override {
    calls.push_back("query:top");
    return top;
  }
  bool IsForeground(HWND hwnd) override {
    calls.push_back("query:foreground");
    return foreground && hwnd == top;
  }
  bool ViewClientRect(HWND, ScreenRect* rect) override {
    calls.push_back("query:client");
    *rect = client;
    return true;
  }
  double ScaleOf(HWND) override {
    calls.push_back("query:scale");
    return scale;
  }
  ScreenRect VirtualScreen() override {
    calls.push_back("query:virtual");
    return virtual_screen;
  }
  ScreenRect PrimaryMonitor() override {
    calls.push_back("query:primary");
    return primary;
  }
  bool GetCursorPosition(ScreenPoint* point) override {
    calls.push_back("get_cursor");
    *point = cursor;
    return true;
  }
  bool SetCursorPosition(ScreenPoint point) override {
    calls.push_back("set_cursor");
    cursor = point;
    return true;
  }
  bool ClipCursorTo(const ScreenRect* rect) override {
    calls.push_back(rect ? "clip" : "unclip");
    clip_active = rect != nullptr;
    if (rect) {
      clip = *rect;
      if (cursor.x < rect->left) cursor.x = rect->left;
      if (cursor.x >= rect->right) cursor.x = rect->right - 1;
      if (cursor.y < rect->top) cursor.y = rect->top;
      if (cursor.y >= rect->bottom) cursor.y = rect->bottom - 1;
    }
    return true;
  }
  int ShowCursorCounter(bool show) override {
    calls.push_back(show ? "show" : "hide");
    show_counter += show ? 1 : -1;
    return show_counter;
  }
  bool RegisterRawMouse(HWND target) override {
    calls.push_back("register_raw");
    raw_target = target;
    raw_registered = true;
    return true;
  }
  bool UnregisterRawMouse() override {
    calls.push_back("unregister_raw");
    raw_registered = false;
    raw_target = nullptr;
    return true;
  }
  bool ReadRawMouse(LPARAM lparam, RawMouseSample* sample) override {
    calls.push_back("read_raw");
    const auto index = static_cast<size_t>(lparam);
    if (index >= raw_queue.size()) return false;
    *sample = raw_queue[index];
    return true;
  }
  UINT FlushMessage() override { return kFlush; }
  bool PostFlush(HWND) override {
    calls.push_back("post_flush");
    posted_flushes++;
    return true;
  }
};

struct Events {
  std::vector<std::string> log;
  std::vector<std::pair<double, double>> motion;
  CaptureCallbacks Callbacks() {
    CaptureCallbacks c;
    c.motion = [this](double dx, double dy) {
      motion.emplace_back(dx, dy);
      log.push_back("motion");
    };
    c.locked = [this]() { log.push_back("locked"); };
    c.lost = [this](const char* reason) {
      log.push_back(std::string("lost:") + reason);
    };
    return c;
  }
};

int g_failures = 0;
int g_checks = 0;
std::string g_current;

void Check(bool ok, const char* expr, const char* file, int line) {
  g_checks++;
  if (!ok) {
    g_failures++;
    std::printf("  FAILED %s:%d  %s  (in %s)\n", file, line, expr,
                g_current.c_str());
  }
}
#define CHECK(expr) Check((expr), #expr, __FILE__, __LINE__)
#define CHECK_NEAR(a, b) Check(std::fabs((a) - (b)) < 1e-6, #a " ~= " #b, __FILE__, __LINE__)

// A WM_INPUT for the fake's raw queue entry.
void SendRaw(PointerCapture& capture, FakeOs& os, unsigned short flags,
             long x, long y) {
  os.raw_queue.push_back(RawMouseSample{flags, x, y});
  capture.HandleMessage(kTop, WM_INPUT, RIM_INPUT,
                        static_cast<LPARAM>(os.raw_queue.size() - 1));
}

void CaptureLocks() {
  FakeOs os;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  CHECK(capture.GetSupport().kind == Kind::kWindows);
  CHECK(capture.GetSupport().pointer_lock);
  CHECK(capture.GetSupport().relative_motion);

  CHECK(capture.Capture(true, 640, 360));
  CHECK(capture.captured());
  CHECK(os.Count("get_cursor") == 1);
  CHECK(os.raw_registered && os.raw_target == kTop);
  CHECK(os.Count("hide") == 1 && os.show_counter == -1);
  CHECK(os.clip_active);
  // (640, 360) logical × 1.5 + the view's origin (100, 200).
  CHECK((os.clip == ScreenRect{1060, 740, 1061, 741}));
  CHECK(ev.log == std::vector<std::string>{"locked"});
  CHECK(os.Count("set_cursor") == 0);
}

void CaptureWithoutCentreUsesTheViewCentre() {
  FakeOs os;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  CHECK(capture.Capture(false, 0, 0));
  CHECK((os.clip == ScreenRect{1060, 740, 1061, 741}));
}

void CentreOutsideTheViewIsClamped() {
  FakeOs os;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  CHECK(capture.Capture(true, -50, 99999));
  CHECK((os.clip == ScreenRect{100, 1279, 101, 1280}));
}

void RelativeSamplesBecomeOneMotionPerFlush() {
  FakeOs os;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  capture.Capture(true, 640, 360);
  SendRaw(capture, os, MOUSE_MOVE_RELATIVE, 3, -2);
  SendRaw(capture, os, MOUSE_MOVE_RELATIVE, 5, 4);
  CHECK(os.posted_flushes == 1);
  CHECK(ev.motion.empty());
  capture.HandleMessage(kTop, kFlush, 0, 0);
  CHECK(ev.motion.size() == 1);
  if (ev.motion.size() == 1) {
    CHECK_NEAR(ev.motion[0].first, 8 / 1.5);
    CHECK_NEAR(ev.motion[0].second, 2 / 1.5);
  }
  // A flush with nothing pending sends nothing; the next sample posts again.
  capture.HandleMessage(kTop, kFlush, 0, 0);
  CHECK(ev.motion.size() == 1);
  SendRaw(capture, os, MOUSE_MOVE_RELATIVE, 1, 0);
  CHECK(os.posted_flushes == 2);
}

void NoMotionWithoutCapture() {
  FakeOs os;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  SendRaw(capture, os, MOUSE_MOVE_RELATIVE, 3, -2);
  capture.HandleMessage(kTop, kFlush, 0, 0);
  CHECK(ev.motion.empty());
  CHECK(os.posted_flushes == 0);
  CHECK(os.PointerCalls() == 0);
}

void AbsoluteSamplesBecomeDeltas() {
  FakeOs os;
  os.scale = 1.0;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  capture.Capture(true, 640, 360);
  const unsigned short flags = MOUSE_MOVE_ABSOLUTE | MOUSE_VIRTUAL_DESKTOP;
  SendRaw(capture, os, flags, 32768, 16384);
  capture.HandleMessage(kTop, kFlush, 0, 0);
  CHECK(ev.motion.empty());  // The first report is only the baseline.
  SendRaw(capture, os, flags, 49151, 32768);
  capture.HandleMessage(kTop, kFlush, 0, 0);
  CHECK(ev.motion.size() == 1);
  if (ev.motion.size() == 1) {
    // The virtual desktop is 3840 × 1080 pixels.
    CHECK_NEAR(ev.motion[0].first, (49151 - 32768) / 65535.0 * 3840);
    CHECK_NEAR(ev.motion[0].second, (32768 - 16384) / 65535.0 * 1080);
  }
  // Without MOUSE_VIRTUAL_DESKTOP the frame is the primary monitor, and a
  // change of frame starts a new baseline.
  SendRaw(capture, os, MOUSE_MOVE_ABSOLUTE, 0, 0);
  SendRaw(capture, os, MOUSE_MOVE_ABSOLUTE, 65535, 0);
  capture.HandleMessage(kTop, kFlush, 0, 0);
  CHECK(ev.motion.size() == 2);
  if (ev.motion.size() == 2) {
    CHECK_NEAR(ev.motion[1].first, 1920.0);
    CHECK_NEAR(ev.motion[1].second, 0.0);
  }
}

void AbsoluteBaselineResetsOnRecapture() {
  FakeOs os;
  os.scale = 1.0;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  capture.Capture(true, 640, 360);
  SendRaw(capture, os, MOUSE_MOVE_ABSOLUTE, 0, 0);
  capture.Release();
  capture.Capture(true, 640, 360);
  SendRaw(capture, os, MOUSE_MOVE_ABSOLUTE, 65535, 65535);
  capture.HandleMessage(kTop, kFlush, 0, 0);
  CHECK(ev.motion.empty());
}

void CheckRestored(FakeOs& os) {
  CHECK(!os.clip_active);
  CHECK(os.show_counter == 0);
  CHECK((os.cursor == ScreenPoint{500, 600}));
  CHECK(!os.raw_registered);
}

void FocusLossLosesAndRestores() {
  FakeOs os;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  capture.Capture(true, 640, 360);
  CHECK(!(os.cursor == ScreenPoint{500, 600}));  // Held at the clip.
  capture.HandleMessage(kTop, WM_ACTIVATE, MAKEWPARAM(WA_INACTIVE, 0), 0);
  CHECK(!capture.captured());
  CHECK((ev.log == std::vector<std::string>{"locked", "lost:focus"}));
  CheckRestored(os);
  // Already given back: a deactivated application reports nothing more.
  capture.HandleMessage(kTop, WM_ACTIVATEAPP, FALSE, 0);
  CHECK(ev.log.size() == 2);
}

void ActivateAppFalseLoses() {
  FakeOs os;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  capture.Capture(true, 640, 360);
  capture.HandleMessage(kTop, WM_ACTIVATE, MAKEWPARAM(WA_ACTIVE, 0), 0);
  CHECK(capture.captured());
  capture.HandleMessage(kTop, WM_ACTIVATEAPP, FALSE, 0);
  CHECK((ev.log == std::vector<std::string>{"locked", "lost:focus"}));
  CheckRestored(os);
}

void MinimiseAndDestroyLose() {
  {
    FakeOs os;
    Events ev;
    PointerCapture capture(&os, kView, ev.Callbacks());
    capture.Capture(true, 640, 360);
    capture.HandleMessage(kTop, WM_SIZE, SIZE_MINIMIZED, 0);
    CHECK((ev.log == std::vector<std::string>{"locked", "lost:minimized"}));
    CheckRestored(os);
  }
  {
    FakeOs os;
    Events ev;
    PointerCapture capture(&os, kView, ev.Callbacks());
    capture.Capture(true, 640, 360);
    capture.HandleMessage(kTop, WM_DESTROY, 0, 0);
    CHECK((ev.log == std::vector<std::string>{"locked", "lost:window"}));
    CheckRestored(os);
  }
}

void MessagesOfOtherWindowsAreIgnored() {
  FakeOs os;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  capture.Capture(true, 640, 360);
  capture.HandleMessage(kOther, WM_ACTIVATE, MAKEWPARAM(WA_INACTIVE, 0), 0);
  CHECK(capture.captured());
}

void KillFocusIsNotALoss() {
  // The top-level hands its keyboard focus to the Flutter view.
  FakeOs os;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  capture.Capture(true, 640, 360);
  capture.HandleMessage(kTop, WM_KILLFOCUS, reinterpret_cast<WPARAM>(kView), 0);
  CHECK(capture.captured());
}

void ReleaseIsIdempotent() {
  FakeOs os;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  capture.Release();
  CHECK(os.PointerCalls() == 0);  // Nothing captured: nothing touched.

  capture.Capture(true, 640, 360);
  capture.Release();
  capture.Release();
  CHECK(os.Count("unclip") == 1);
  CHECK(os.Count("show") == 1);
  CHECK(os.Count("set_cursor") == 1);
  CHECK(os.Count("unregister_raw") == 1);
  CheckRestored(os);
  CHECK(ev.log == std::vector<std::string>{"locked"});  // Asked: not lost.
}

void TeardownReleases() {
  FakeOs os;
  Events ev;
  {
    PointerCapture capture(&os, kView, ev.Callbacks());
    capture.Capture(true, 640, 360);
  }
  CheckRestored(os);
  CHECK(ev.log == std::vector<std::string>{"locked"});
}

void RecaptureMovesTheClip() {
  FakeOs os;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  capture.Capture(true, 640, 360);
  CHECK(capture.Capture(true, 0, 0));
  CHECK((os.clip == ScreenRect{100, 200, 101, 201}));
  CHECK(os.Count("register_raw") == 1);
  CHECK(os.Count("hide") == 1);
  CHECK(os.Count("get_cursor") == 1);
  capture.Release();
  CheckRestored(os);
}

void RefusedCapturesTouchNothing() {
  for (const char* value : {"off", "record", " OFF "}) {
    FakeOs os;
    os.env_value = value;
    Events ev;
    PointerCapture capture(&os, kView, ev.Callbacks());
    CHECK(capture.GetSupport().kind == Kind::kDisabled);
    CHECK(!capture.Capture(true, 640, 360));
    CHECK(os.PointerCalls() == 0);
    CHECK(ev.log.empty());
  }
  {
    FakeOs os;
    os.foreground = false;
    Events ev;
    PointerCapture capture(&os, kView, ev.Callbacks());
    CHECK(!capture.Capture(true, 640, 360));
    CHECK(os.PointerCalls() == 0);
  }
  {
    FakeOs os;
    os.top = nullptr;
    Events ev;
    PointerCapture capture(&os, kView, ev.Callbacks());
    CHECK(!capture.Capture(true, 640, 360));
    CHECK(os.PointerCalls() == 0);
  }
  {
    FakeOs os;
    Events ev;
    PointerCapture capture(&os, nullptr, ev.Callbacks());
    CHECK(capture.GetSupport().kind == Kind::kUnsupported);
    CHECK(!capture.Capture(true, 640, 360));
    CHECK(os.PointerCalls() == 0);
  }
}

void DisplayChangeReclips() {
  FakeOs os;
  Events ev;
  PointerCapture capture(&os, kView, ev.Callbacks());
  capture.Capture(true, 640, 360);
  os.client = ScreenRect{-1920, 0, 0, 1080};
  os.scale = 1.0;
  capture.HandleMessage(kTop, WM_DISPLAYCHANGE, 32, MAKELPARAM(1920, 1080));
  CHECK((os.clip == ScreenRect{-1280, 360, -1279, 361}));
  CHECK(capture.captured());
  // A DPI change also rescales motion.
  os.scale = 2.0;
  capture.HandleMessage(kTop, WM_DPICHANGED, MAKEWPARAM(192, 192), 0);
  CHECK((os.clip == ScreenRect{-1920 + 1280, 720, -1920 + 1281, 721}));
  SendRaw(capture, os, MOUSE_MOVE_RELATIVE, 4, 4);
  capture.HandleMessage(kTop, kFlush, 0, 0);
  CHECK(ev.motion.size() == 1);
  if (ev.motion.size() == 1) CHECK_NEAR(ev.motion[0].first, 2.0);
  capture.Release();
  CheckRestored(os);
}

}  // namespace

int main() {
  const std::vector<std::pair<const char*, std::function<void()>>> tests = {
      {"capture locks: position saved, raw input, cursor hidden, clipped", CaptureLocks},
      {"capture without a centre uses the view centre", CaptureWithoutCentreUsesTheViewCentre},
      {"a centre outside the view is clamped into it", CentreOutsideTheViewIsClamped},
      {"relative samples become one motion per flush", RelativeSamplesBecomeOneMotionPerFlush},
      {"no motion without a capture", NoMotionWithoutCapture},
      {"absolute samples become deltas", AbsoluteSamplesBecomeDeltas},
      {"the absolute baseline resets on recapture", AbsoluteBaselineResetsOnRecapture},
      {"focus loss reports lost and restores the cursor", FocusLossLosesAndRestores},
      {"WM_ACTIVATEAPP(FALSE) reports lost", ActivateAppFalseLoses},
      {"minimise and destroy report lost", MinimiseAndDestroyLose},
      {"messages of other windows are ignored", MessagesOfOtherWindowsAreIgnored},
      {"WM_KILLFOCUS is not a loss", KillFocusIsNotALoss},
      {"release is idempotent", ReleaseIsIdempotent},
      {"teardown releases", TeardownReleases},
      {"a second capture moves the clip", RecaptureMovesTheClip},
      {"refused captures touch nothing", RefusedCapturesTouchNothing},
      {"display and DPI changes re-clip", DisplayChangeReclips},
  };
  int failed_tests = 0;
  for (const auto& [name, fn] : tests) {
    g_current = name;
    const int before = g_failures;
    fn();
    const bool ok = g_failures == before;
    if (!ok) failed_tests++;
    std::printf("%s %s\n", ok ? "PASS" : "FAIL", name);
  }
  std::printf("%zu tests, %d failed, %d checks\n", tests.size(), failed_tests,
              g_checks);
  return failed_tests == 0 ? 0 : 1;
}
