import { spawn, type ChildProcess } from "node:child_process";

export type IndicatorStatus = "listening" | "transcribing";

const JXA_SCRIPT = `
ObjC.import("Cocoa");

function createWindow() {
  var width = 420;
  var height = 60;
  var screen = $.NSScreen.mainScreen;
  var sf = screen.frame;
  var x = (sf.size.width - width) / 2;
  var y = 48;

  var win = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(x, y, width, height),
    $.NSWindowStyleMaskBorderless | $.NSWindowStyleMaskNonactivatingPanel,
    $.NSBackingStoreBuffered,
    false
  );

  win.setLevel($.CGWindowLevelForKey($.kCGMaximumWindowLevelKey));
  win.setFloatingPanel(true);
  win.setOpaque(false);
  win.setBackgroundColor($.NSColor.clearColor);
  win.setHasShadow(true);
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
  bg.setCornerRadius(20);
  view.addSubview(bg);

  var dotSize = 8;
  var dot = $.NSView.alloc.initWithFrame($.NSMakeRect(16, height - 22, dotSize, dotSize));
  dot.setWantsLayer(true);
  dot.layer.setCornerRadius(dotSize / 2);
  dot.layer.setBackgroundColor($.CGColorCreateGenericRGB(1, 0.25, 0.25, 1));
  view.addSubview(dot);

  var labelHeight = 18;
  var label = $.NSTextField.labelWithString($("Listening..."));
  label.setFrame($.NSMakeRect(32, height - 26, width - 72, labelHeight));
  label.setTextColor($.NSColor.whiteColor);
  label.setFont($.NSFont.systemFontOfSizeWeight(13, 0.5));
  view.addSubview(label);

  var btnSize = 24;
  var stopBtn = $.NSButton.alloc.initWithFrame(
    $.NSMakeRect(width - btnSize - 12, height - 26, btnSize, btnSize)
  );
  stopBtn.setBezelStyle($.NSBezelStyleInline);
  stopBtn.setBordered(false);
  stopBtn.setTitle($("\\u25A0"));
  stopBtn.setFont($.NSFont.systemFontOfSizeWeight(14, 0.4));
  stopBtn.setContentTintColor($.NSColor.colorWithSRGBRedGreenBlueAlpha(0.85, 0.85, 0.85, 1.0));
  view.addSubview(stopBtn);

  var textLabel = $.NSTextField.labelWithString($(""));
  textLabel.setFrame($.NSMakeRect(16, 6, width - 32, 18));
  textLabel.setTextColor($.NSColor.colorWithSRGBRedGreenBlueAlpha(0.8, 0.8, 0.8, 1.0));
  textLabel.setFont($.NSFont.systemFontOfSizeWeight(11, 0.3));
  textLabel.setLineBreakMode($.NSLineBreakByTruncatingHead);
  view.addSubview(textLabel);

  win.orderFrontRegardless;

  return { win: win, dot: dot, label: label, textLabel: textLabel, stopBtn: stopBtn };
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

function writeStdout(str) {
  var data = $.NSString.alloc.initWithUTF8String(str).dataUsingEncoding($.NSUTF8StringEncoding);
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
}

// Shared state
var _ui = null;
var _buf = "";
var _lastActivity = null;
var _MAX_IDLE_SECONDS = 120;
var _app = null;

function shutdown() {
  if (_ui) { _ui.win.close; }
  _app.stop($.nil);
}

function processStdinData(data) {
  if (data.length === 0) { shutdown(); return; }

  _lastActivity = $.NSDate.date;
  var str = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
  _buf += str;
  var lines = _buf.split("\\n");
  _buf = lines.pop();

  for (var i = 0; i < lines.length; i++) {
    var cmd = lines[i].trim();
    if (cmd === "close") { shutdown(); return; }
    if (cmd === "listening" || cmd === "transcribing") {
      applyStatus(_ui, cmd);
    } else if (cmd.indexOf("text:") === 0) {
      var content = cmd.substring(5);
      if (content.length > 50) {
        content = "\\u2026" + content.substring(content.length - 50);
      }
      _ui.textLabel.setStringValue($(content));
    }
  }

  // Re-register for next data notification
  $.NSFileHandle.fileHandleWithStandardInput.waitForDataInBackgroundAndNotify;
}

ObjC.registerSubclass({
  name: "StopHandler",
  methods: {
    "stopClicked:": {
      types: ["void", ["id"]],
      implementation: function(sender) {
        writeStdout("stopped\\n");
        shutdown();
      }
    },
    "stdinDataAvailable:": {
      types: ["void", ["id"]],
      implementation: function(notification) {
        var fh = notification.object;
        var data = fh.availableData;
        processStdinData(data);
      }
    },
    "watchdog:": {
      types: ["void", ["id"]],
      implementation: function(timer) {
        var elapsed = -_lastActivity.timeIntervalSinceNow;
        if (elapsed > _MAX_IDLE_SECONDS) { shutdown(); }
      }
    }
  }
});

function run() {
  _app = $.NSApplication.sharedApplication;
  _app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  _ui = createWindow();
  _lastActivity = $.NSDate.date;

  var handler = $.StopHandler.alloc.init;

  // Wire stop button
  _ui.stopBtn.target = handler;
  _ui.stopBtn.action = "stopClicked:";

  // Async stdin reading — does not block the event loop
  var stdin = $.NSFileHandle.fileHandleWithStandardInput;
  $.NSNotificationCenter.defaultCenter.addObserverSelectorNameObject(
    handler, "stdinDataAvailable:", $.NSFileHandleDataAvailableNotification, stdin
  );
  stdin.waitForDataInBackgroundAndNotify;

  // Watchdog timer for idle timeout
  $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
    5.0, handler, "watchdog:", $.nil, true
  );

  // app.run properly processes UI events (button clicks)
  _app.run;
}

run();
`;

export class StatusIndicator {
  private proc: ChildProcess | null = null;
  private stopCallbacks: Array<() => void> = [];

  show(status: IndicatorStatus): void {
    try {
      this.proc = spawn("osascript", ["-l", "JavaScript", "-e", JXA_SCRIPT], {
        stdio: ["pipe", "pipe", "ignore"],
      });

      this.proc.on("error", () => {
        this.proc = null;
      });

      this.proc.on("exit", () => {
        this.proc = null;
      });

      // Listen for "stopped" from JXA stdout (stop button clicked)
      let stdoutBuf = "";
      this.proc.stdout?.on("data", (data: Buffer) => {
        stdoutBuf += data.toString();
        const lines = stdoutBuf.split("\n");
        stdoutBuf = lines.pop() ?? "";
        for (const line of lines) {
          if (line.trim() === "stopped") {
            for (const cb of this.stopCallbacks) {
              try { cb(); } catch { /* ignore */ }
            }
          }
        }
      });

      this.proc.stdin?.write(status + "\n");
    } catch {
      this.proc = null;
    }
  }

  onStop(callback: () => void): void {
    this.stopCallbacks.push(callback);
  }

  update(status: IndicatorStatus): void {
    try {
      this.proc?.stdin?.write(status + "\n");
    } catch {
      // silent no-op
    }
  }

  sendText(text: string): void {
    try {
      // Replace newlines with spaces to keep it on one line
      const clean = text.replace(/[\r\n]+/g, " ");
      this.proc?.stdin?.write("text:" + clean + "\n");
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
