import { spawn, type ChildProcess } from "node:child_process";

export type IndicatorStatus = "listening" | "transcribing";

const JXA_SCRIPT = `
ObjC.import("Cocoa");

function createWindow() {
  var width = 180;
  var height = 36;
  var screen = $.NSScreen.mainScreen;
  var sf = screen.frame;
  var x = (sf.size.width - width) / 2;
  var y = 48;

  var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(x, y, width, height),
    $.NSWindowStyleMaskBorderless | $.NSWindowStyleMaskNonactivatingPanel,
    $.NSBackingStoreBuffered,
    false
  );

  win.setLevel($.CGWindowLevelForKey($.kCGMaximumWindowLevelKey));
  win.setOpaque(false);
  win.setBackgroundColor($.NSColor.clearColor);
  win.setHasShadow(true);
  win.setIgnoresMouseEvents(true);
  win.setHidesOnDeactivate(false);
  win.setCollectionBehavior(
    $.NSWindowCollectionBehaviorCanJoinAllSpaces |
    $.NSWindowCollectionBehaviorStationary |
    $.NSWindowCollectionBehaviorFullScreenAuxiliary
  );

  var view = win.contentView;

  var bg = $.NSBox.alloc.initWithFrame($.NSMakeRect(0, 0, width, height));
  bg.setBoxType($.NSBoxCustom);
  bg.setFillColor($.NSColor.colorWithSRGBRedGreenBlueAlpha(0.12, 0.12, 0.14, 0.92));
  bg.setBorderWidth(0);
  bg.setCornerRadius(height / 2);
  view.addSubview(bg);

  var dotSize = 8;
  var dot = $.NSView.alloc.initWithFrame($.NSMakeRect(16, (height - dotSize) / 2, dotSize, dotSize));
  dot.setWantsLayer(true);
  dot.layer.setCornerRadius(dotSize / 2);
  dot.layer.setBackgroundColor($.CGColorCreateGenericRGB(1, 0.25, 0.25, 1));
  view.addSubview(dot);

  var labelHeight = 18;
  var label = $.NSTextField.labelWithString($("Listening..."));
  label.setFrame($.NSMakeRect(32, (height - labelHeight) / 2, width - 48, labelHeight));
  label.setTextColor($.NSColor.whiteColor);
  label.setFont($.NSFont.systemFontOfSizeWeight(13, 0.5));
  view.addSubview(label);

  win.orderFrontRegardless;

  return { win: win, dot: dot, label: label };
}

function applyStatus(ui, status) {
  if (status === "listening") {
    ui.dot.layer.setBackgroundColor($.CGColorCreateGenericRGB(1, 0.25, 0.25, 1));
    ui.label.setStringValue($("Listening..."));
  } else if (status === "transcribing") {
    ui.dot.layer.setBackgroundColor($.CGColorCreateGenericRGB(1, 0.6, 0.2, 1));
    ui.label.setStringValue($("Transcribing..."));
  }
}

function run() {
  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  var ui = createWindow();
  var rl = $.NSRunLoop.currentRunLoop;
  var stdin = $.NSFileHandle.fileHandleWithStandardInput;
  var buf = "";
  var done = false;
  var lastActivity = $.NSDate.date;
  var MAX_IDLE_SECONDS = 120;

  while (!done) {
    // Pump the run loop so AppKit renders the window
    rl.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));

    // Watchdog: auto-close if no stdin activity (parent likely dead)
    var elapsed = -lastActivity.timeIntervalSinceNow;
    if (elapsed > MAX_IDLE_SECONDS) { done = true; break; }

    var data = stdin.availableData;
    if (data.length === 0) { done = true; break; }

    lastActivity = $.NSDate.date;
    var str = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
    buf += str;
    var lines = buf.split("\\n");
    buf = lines.pop();

    for (var i = 0; i < lines.length; i++) {
      var cmd = lines[i].trim();
      if (cmd === "close") { done = true; break; }
      if (cmd === "listening" || cmd === "transcribing") {
        applyStatus(ui, cmd);
      }
    }
  }

  ui.win.close;
  rl.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.05));
}

run();
`;

export class StatusIndicator {
  private proc: ChildProcess | null = null;

  show(status: IndicatorStatus): void {
    try {
      this.proc = spawn("osascript", ["-l", "JavaScript", "-e", JXA_SCRIPT], {
        stdio: ["pipe", "ignore", "ignore"],
      });

      this.proc.on("error", () => {
        this.proc = null;
      });

      this.proc.on("exit", () => {
        this.proc = null;
      });

      this.proc.stdin?.write(status + "\n");
    } catch {
      this.proc = null;
    }
  }

  update(status: IndicatorStatus): void {
    try {
      this.proc?.stdin?.write(status + "\n");
    } catch {
      // silent no-op
    }
  }

  close(): void {
    const proc = this.proc;
    this.proc = null;

    if (!proc || proc.exitCode !== null) return;

    try {
      proc.stdin?.write("close\n");
      proc.stdin?.end();
    } catch {
      // silent no-op
    }

    // Safety timeout: force-kill if osascript didn't exit
    setTimeout(() => {
      try {
        if (proc.exitCode === null) proc.kill("SIGKILL");
      } catch {
        // silent no-op
      }
    }, 500);
  }
}
