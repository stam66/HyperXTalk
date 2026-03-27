# org.openxtalk.windowanimation

Smooth animated window resizing for macOS LiveCode stacks, using native
Cocoa `NSAnimationContext` and the `NSWindow` animator proxy.

## Requirements

- macOS only
- OpenXTalk 1.14 or later / LiveCode 9.6 or later (LCB foreign handler support)
- Xcode command-line tools (to build the glue dylib)

## How it works

LiveCode Builder cannot marshal `CGRect` / `NSRect` structs across its
foreign function interface, so all Cocoa calls live in a small ObjC glue
dylib (`windowanimation_glue.dylib`). The LCB library binds to that dylib
using only primitive types (`CDouble`, `CLong`, `Pointer`) and handles the
LiveCode → Cocoa coordinate flip (top-left vs bottom-left origin) itself.

Animation is driven by `NSAnimationContext` with `[[window animator] setFrame:display:]`
— the animator proxy is required to respect the context duration. The
older `setFrame:display:animate:YES` API ignores `NSAnimationContext`
entirely and uses its own fixed timing.

The glue also compensates for the window title bar height: LiveCode reports
content-area dimensions, while Cocoa's frame rect includes the title bar,
so the glue measures the live title bar height from the window and adds it
back before building the `NSRect`.

## Building the glue dylib

```bash
cd /path/to/source
./build_glue.sh /path/to/org.openxtalk.windowanimation
```

This produces a universal (arm64 + x86_64) `windowanimation_glue.dylib` and
copies it into both:

```
org.openxtalk.windowanimation/code/arm64-mac/windowanimation_glue.dylib
org.openxtalk.windowanimation/code/x86_64-mac/windowanimation_glue.dylib
```

## Extension folder layout

```
org.openxtalk.windowanimation/
├── org_openxtalk_windowanimation.lcb
├── code/
│   ├── arm64-mac/
│   │   └── windowanimation_glue.dylib
│   └── x86_64-mac/
│       └── windowanimation_glue.dylib
└── api.lcdoc
```

## API

### `windowAnimateResize`

```
windowAnimateResize(pWindowID, pLeft, pTop, pWidth, pHeight, pDuration)
```

Smoothly resizes and repositions a stack window.

| Parameter   | Type    | Description                                                                 |
|-------------|---------|-----------------------------------------------------------------------------|
| pWindowID   | Integer | The window ID — always `the windowId of stack "StackName"` by explicit name |
| pLeft       | Integer | New left edge in LiveCode screen coordinates                                |
| pTop        | Integer | New top edge in LiveCode screen coordinates                                 |
| pWidth      | Integer | New width in points                                                         |
| pHeight     | Integer | New content-area height in points (title bar excluded)                      |
| pDuration   | Real    | Animation duration in seconds (e.g. `0.3`)                                  |

**Example:**
```livecode
-- Always use the explicit stack name, never `this stack`
windowAnimateResize(the windowId of stack "Untitled 1", \
   the left of stack "Untitled 1", the top of stack "Untitled 1", \
   800, 600, 0.3)
```

---

## Notes

- Always pass the window ID using `the windowId of stack "StackName"` with the explicit stack name. Never use `this stack` from within a toolbar callback — in that context it resolves unreliably and may target the wrong window, particularly when multiple windows are open.
- The handler silently returns on non-Mac platforms, so it is safe to
  call in cross-platform stacks.
- The handler throws a runtime error if the window ID cannot be resolved
  to an `NSWindow`. Always call after the stack has been opened.
- Duration is passed directly to `NSAnimationContext`. Values below `0.1`
  may not produce a visible animation on all hardware.
- The system respects the user's "Reduce motion" accessibility setting;
  on those systems the resize will complete instantly regardless of duration.

## Files

| File                      | Purpose                                        |
|---------------------------|------------------------------------------------|
| `org_openxtalk_windowanimation.lcb` | LCB library — foreign bindings and public API |
| `LCWindowAnimation.h`     | C header for the glue dylib                    |
| `LCWindowAnimation.m`     | ObjC glue implementation                       |
| `build_glue.sh`           | Build script — produces universal dylib        |
| `api.lcdoc`               | LiveCode API documentation                     |
