#include "pointer_capture.h"

#include <algorithm>
#include <cctype>
#include <cmath>

namespace lumina_mouse_capture {

namespace {

// The raw mouse report's absolute coordinates run 0..65535 across the frame.
constexpr double kAbsoluteRange = 65535.0;

// ShowCursor's counter can already be above zero (another caller showed it):
// hide until it is negative, but never loop without end.
constexpr int kMaxHideCalls = 8;

std::string Trimmed(std::string value) {
  auto not_space = [](unsigned char c) { return !std::isspace(c); };
  value.erase(value.begin(), std::find_if(value.begin(), value.end(), not_space));
  value.erase(std::find_if(value.rbegin(), value.rend(), not_space).base(),
              value.end());
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return value;
}

long Clamp(long value, long low, long high) {
  return value < low ? low : (value > high ? high : value);
}

}  // namespace

const char* KindName(Kind kind) {
  switch (kind) {
    case Kind::kWindows:
      return "windows";
    case Kind::kDisabled:
      return "disabled";
    case Kind::kUnsupported:
      break;
  }
  return "unsupported";
}

bool DisabledByEnvironment(PointerOs& os) {
  const std::string value = Trimmed(os.Environment("LUMINA_MOUSE_CAPTURE"));
  return value == "off" || value == "record";
}

PointerCapture::PointerCapture(PointerOs* os, HWND view,
                               CaptureCallbacks callbacks)
    : os_(os), view_(view), callbacks_(std::move(callbacks)) {}

PointerCapture::~PointerCapture() {
  // The plugin is going away (the engine shuts down, the window closed):
  // never leave the pointer clipped or hidden behind it.
  if (captured_) {
    captured_ = false;
    RestoreOs();
  }
}

Support PointerCapture::GetSupport() {
  Support support;
  if (DisabledByEnvironment(*os_)) {
    support.kind = Kind::kDisabled;
    support.detail =
        "LUMINA_MOUSE_CAPTURE is off: nothing captures the pointer";
  } else if (view_ == nullptr) {
    support.detail = "no Flutter view";
  } else {
    support.kind = Kind::kWindows;
    support.pointer_lock = true;
    support.relative_motion = true;
    support.detail =
        "raw input (WM_INPUT) with a hidden cursor clipped to the capture "
        "centre";
  }
  return support;
}

bool PointerCapture::ComputeClip(ScreenRect* clip, double* scale) {
  ScreenRect client;
  if (!os_->ViewClientRect(view_, &client) || client.width() <= 0 ||
      client.height() <= 0) {
    return false;
  }
  const double s = os_->ScaleOf(view_);
  *scale = s > 0 ? s : 1.0;
  long cx;
  long cy;
  if (has_centre_) {
    cx = client.left + std::lround(centre_x_ * *scale);
    cy = client.top + std::lround(centre_y_ * *scale);
  } else {
    cx = client.left + client.width() / 2;
    cy = client.top + client.height() / 2;
  }
  cx = Clamp(cx, client.left, client.right - 1);
  cy = Clamp(cy, client.top, client.bottom - 1);
  *clip = ScreenRect{cx, cy, cx + 1, cy + 1};
  return true;
}

bool PointerCapture::ApplyClip() {
  ScreenRect clip;
  double scale = 1.0;
  if (!ComputeClip(&clip, &scale)) return false;
  if (!os_->ClipCursorTo(&clip)) return false;
  clipped_ = true;
  scale_ = scale;
  return true;
}

bool PointerCapture::Capture(bool has_centre, double x, double y) {
  if (DisabledByEnvironment(*os_) || view_ == nullptr) return false;
  HWND top = os_->TopLevelOf(view_);
  if (top == nullptr || !os_->IsForeground(top)) return false;

  if (captured_) {
    // Already holding the pointer: only the centre moves.
    const bool old_has_centre = has_centre_;
    const double old_x = centre_x_;
    const double old_y = centre_y_;
    has_centre_ = has_centre;
    centre_x_ = x;
    centre_y_ = y;
    if (!ApplyClip()) {
      has_centre_ = old_has_centre;
      centre_x_ = old_x;
      centre_y_ = old_y;
      return false;
    }
    if (callbacks_.locked) callbacks_.locked();
    return true;
  }

  has_centre_ = has_centre;
  centre_x_ = x;
  centre_y_ = y;
  ScreenRect clip;
  double scale = 1.0;
  if (!ComputeClip(&clip, &scale)) return false;

  top_level_ = top;
  saved_position_valid_ = os_->GetCursorPosition(&saved_position_);
  if (!os_->RegisterRawMouse(top)) {
    saved_position_valid_ = false;
    top_level_ = nullptr;
    return false;
  }
  raw_registered_ = true;
  hide_calls_ = 0;
  while (hide_calls_ < kMaxHideCalls) {
    const int counter = os_->ShowCursorCounter(false);
    hide_calls_++;
    if (counter < 0) break;
  }
  if (!os_->ClipCursorTo(&clip)) {
    RestoreOs();
    top_level_ = nullptr;
    return false;
  }
  clipped_ = true;
  scale_ = scale;
  pending_dx_ = 0;
  pending_dy_ = 0;
  has_absolute_ = false;
  captured_ = true;
  if (callbacks_.locked) callbacks_.locked();
  return true;
}

void PointerCapture::Release() {
  if (!captured_) return;
  captured_ = false;
  RestoreOs();
}

void PointerCapture::RestoreOs() {
  if (clipped_) {
    os_->ClipCursorTo(nullptr);
    clipped_ = false;
  }
  for (; hide_calls_ > 0; hide_calls_--) os_->ShowCursorCounter(true);
  if (saved_position_valid_) {
    os_->SetCursorPosition(saved_position_);
    saved_position_valid_ = false;
  }
  if (raw_registered_) {
    os_->UnregisterRawMouse();
    raw_registered_ = false;
  }
  pending_dx_ = 0;
  pending_dy_ = 0;
  has_absolute_ = false;
  top_level_ = nullptr;
}

void PointerCapture::Lose(const char* reason) {
  if (!captured_) return;
  captured_ = false;
  RestoreOs();
  if (callbacks_.lost) callbacks_.lost(reason);
}

void PointerCapture::OnRawInput(LPARAM lparam) {
  RawMouseSample sample;
  if (!os_->ReadRawMouse(lparam, &sample)) return;
  double dx = 0;
  double dy = 0;
  if ((sample.flags & MOUSE_MOVE_ABSOLUTE) != 0) {
    // Remote desktop sessions, tablets and some virtual machines report
    // positions, not movement: difference them in screen pixels.
    const bool virtual_desktop = (sample.flags & MOUSE_VIRTUAL_DESKTOP) != 0;
    const ScreenRect frame =
        virtual_desktop ? os_->VirtualScreen() : os_->PrimaryMonitor();
    const double x = frame.left + sample.last_x / kAbsoluteRange * frame.width();
    const double y = frame.top + sample.last_y / kAbsoluteRange * frame.height();
    if (has_absolute_ && absolute_virtual_ == virtual_desktop) {
      dx = x - last_absolute_x_;
      dy = y - last_absolute_y_;
    }
    has_absolute_ = true;
    absolute_virtual_ = virtual_desktop;
    last_absolute_x_ = x;
    last_absolute_y_ = y;
  } else {
    has_absolute_ = false;
    dx = static_cast<double>(sample.last_x);
    dy = static_cast<double>(sample.last_y);
  }
  if (dx == 0 && dy == 0) return;
  pending_dx_ += dx;
  pending_dy_ += dy;
  if (!flush_posted_ && top_level_ != nullptr) {
    flush_posted_ = os_->PostFlush(top_level_);
  }
}

void PointerCapture::Flush() {
  flush_posted_ = false;
  if (!captured_ || (pending_dx_ == 0 && pending_dy_ == 0)) return;
  const double dx = pending_dx_ / scale_;
  const double dy = pending_dy_ / scale_;
  pending_dx_ = 0;
  pending_dy_ = 0;
  if (callbacks_.motion) callbacks_.motion(dx, dy);
}

void PointerCapture::HandleMessage(HWND hwnd, UINT message, WPARAM wparam,
                                   LPARAM lparam) {
  if (message == os_->FlushMessage()) {
    Flush();
    return;
  }
  if (!captured_ || hwnd != top_level_) return;
  switch (message) {
    case WM_INPUT:
      OnRawInput(lparam);
      break;
    case WM_ACTIVATE:
      if (LOWORD(wparam) == WA_INACTIVE) Lose(lost_reason::kFocus);
      break;
    case WM_ACTIVATEAPP:
      if (wparam == FALSE) Lose(lost_reason::kFocus);
      break;
    case WM_SIZE:
      if (wparam == SIZE_MINIMIZED) {
        Lose(lost_reason::kMinimized);
      } else {
        // Follow the view; a view with no area yet keeps the old clip.
        ApplyClip();
      }
      break;
    case WM_DISPLAYCHANGE:
    case WM_DPICHANGED:
      ApplyClip();
      break;
    case WM_DESTROY:
      Lose(lost_reason::kWindow);
      break;
    default:
      break;
  }
}

}  // namespace lumina_mouse_capture
