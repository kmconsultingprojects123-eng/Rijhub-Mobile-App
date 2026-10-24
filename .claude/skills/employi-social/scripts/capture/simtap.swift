import Cocoa

// simtap tap X Y | swipe X1 Y1 X2 Y2
//
// X/Y are device points on the Simulator's display. The display's frame on
// screen comes in through FX FY FW FH, and the device's size in points
// through DW DH (sim.sh measures both). Brings the Simulator forward, checks
// it is frontmost, sends real input events at the mapped point, then puts
// the cursor back where it was.
//
// Real input is needed: the Simulator ignores events posted to its process
// (CGEventPostToPid), with or without its window number on them.
let env = ProcessInfo.processInfo.environment
func num(_ k: String) -> Double { Double(env[k] ?? "") ?? { print("missing \(k)"); exit(1) }() }
let fx = num("FX"), fy = num("FY"), fw = num("FW"), fh = num("FH"), dw = num("DW"), dh = num("DH")
func screen(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: fx + x * fw / dw, y: fy + y * fh / dh) }

let front = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.iphonesimulator" }
var waited = 0
while !front() && waited < 40 { usleep(25_000); waited += 1 }
guard front() else { print("Simulator is not frontmost; nothing sent"); exit(2) }
usleep(120_000)

let home = CGEvent(source: nil)!.location
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
let a = CommandLine.arguments
let n = a.dropFirst(2).compactMap { Double($0) }
switch a.count > 1 ? a[1] : "" {
case "tap" where n.count == 2:
    let p = screen(n[0], n[1])
    post(.mouseMoved, p); usleep(30_000)
    post(.leftMouseDown, p); usleep(70_000); post(.leftMouseUp, p)
case "swipe" where n.count == 4:
    // Slow, then held still before release: iOS reads a quick drag as a
    // fling and keeps scrolling after the finger lifts.
    let p0 = screen(n[0], n[1]), p1 = screen(n[2], n[3]), steps = 70
    post(.mouseMoved, p0); usleep(30_000)
    post(.leftMouseDown, p0); usleep(80_000)
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        post(.leftMouseDragged, CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t)); usleep(16_000)
    }
    post(.leftMouseDragged, p1); usleep(350_000)
    post(.leftMouseUp, p1)
default:
    print("usage: simtap tap X Y | swipe X1 Y1 X2 Y2"); exit(64)
}
usleep(40_000)
CGWarpMouseCursorPosition(home)
