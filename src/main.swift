#!/usr/bin/env swift
import Cocoa
import AppKit

typealias WinPos = (Int32, CGRect)  // win-num, bounds
typealias WinConf = [Int32: [WinPos]]  // app-pid, window-list

class AppDelegate: NSObject, NSApplicationDelegate {
	private var statusItem: NSStatusItem!
	private var numScreens: Int = NSScreen.screens.count
	private var state: [Int: WinConf] = [:]  // [screencount: [pid: [windows]]]
	
	func applicationDidFinishLaunching(_ aNotification: Notification) {
		UserDefaults.standard.register(defaults: ["icon": 2])
		let icon = UserDefaults.standard.integer(forKey: "icon")
		if icon == 0 { return }
		self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		if let button = self.statusItem.button {
			switch icon {
			case 1: button.image = NSImage.statusIconDots
			case 2: button.image = NSImage.statusIconMonitor
			default: button.image = NSImage.statusIconMonitor
			}
		}
		self.statusItem.menu = NSMenu(title: "")
		self.statusItem.menu!.addItem(withTitle: "Memmon (v1.1)", action: nil, keyEquivalent: "")
		self.statusItem.menu!.addItem(withTitle: "Hide Status Icon", action: #selector(self.enableInvisbleMode), keyEquivalent: "")
		self.statusItem.menu!.addItem(withTitle: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q")
	}

	@objc func enableInvisbleMode() {
		self.statusItem = nil
	}

	func applicationDidChangeScreenParameters(_ notification: Notification) {
		if numScreens != NSScreen.screens.count {
			self.saveState()
			numScreens = NSScreen.screens.count
			if let previous = self.state[numScreens] {
				self.restoreState(previous)
			}
		}
	}
	
	private func saveState() {
		let newState = self.getState()
		self.state[numScreens] = newState
		// update existing
		let dummy: WinPos = (0, CGRect.zero)
		for kNum in self.state.keys {
			if kNum == numScreens { continue }  // current state, already set above
			var tmp_state: WinConf = [:]
			for (n_app, new_val) in newState {
				if let old_val = self.state[kNum]![n_app] {
					tmp_state[n_app] = []
					for (n_win, _) in new_val {
						let old_pos = old_val.first { $0.0 == n_win }
						tmp_state[n_app]!.append(old_pos ?? dummy)
					}
				}
			}
			self.state[kNum] = tmp_state
		}
	}
	
	private func restoreState(_ state: WinConf) {
		for (pid, bounds) in state {
			self.setWindowSizes(pid, bounds)
		}
	}
	
	private func getState() -> WinConf {
		var allWinNums: [Int32] = []
		for winNum in NSWindow.windowNumbers(options: [.allApplications, .allSpaces]) ?? [] {
			allWinNums.append(winNum.int32Value)
		}
		var state: WinConf = [:]
		let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as NSArray? as? [[String: AnyObject]]
		
		for entry in windowList! {
			// let owner = entry[kCGWindowOwnerName as String] as! String
			if entry[kCGWindowLayer as String] as! CGWindowLevel != kCGNormalWindowLevel {
				continue
			}
			let winNum = entry[kCGWindowNumber as String] as! Int32
			guard let insIdx = allWinNums.firstIndex(of: winNum) else {
				continue
			}
			let pid = entry[kCGWindowOwnerPID as String] as! Int32
			let b = entry[kCGWindowBounds as String] as! [String: Int]
			let bounds = CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!)
			if (state[pid] == nil) {
				state[pid] = [(winNum, bounds)]
			} else {
				// allWinNums is sorted by recent activity, windowList is not. Keep order while appending.
				if let idx = state[pid]!.firstIndex(where: { insIdx < allWinNums.firstIndex(of: $0.0)! }) {
					state[pid]!.insert((winNum, bounds), at: idx)
				} else {
					state[pid]!.append((winNum, bounds))
				}
			}
		}
		return state
	}
	
	private func setWindowSizes(_ pid: Int32, _ sizes: [WinPos]) {
		let win = self.axWinList(pid)
		guard win.count > 0, win.count == sizes.count else {
			return
		}
		for i in 0 ..< win.count {
			var pt = sizes[i].1
			if pt.isEmpty { continue }  // filter dummy elements
			AXUIElementSetAttributeValue(win[i], kAXPositionAttribute as CFString,
										 AXValueCreate(AXValueType(rawValue: kAXValueCGPointType)!, &pt.origin)!);
			AXUIElementSetAttributeValue(win[i], kAXSizeAttribute as CFString,
										 AXValueCreate(AXValueType(rawValue: kAXValueCGSizeType)!, &pt.size)!);
		}
	}
	
	private func axWinList(_ pid: Int32) -> [AXUIElement] {
		let appRef = AXUIElementCreateApplication(pid)
		var value: AnyObject?
		AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)
		if let windowList = value as? [AXUIElement] {
			var tmp: [AXUIElement] = []
			for win in windowList {
				var role: CFTypeRef?
				AXUIElementCopyAttributeValue(win, kAXRoleAttribute as CFString, &role)
				if role as? String == kAXWindowRole {
					tmp.append(win)  // filter e.g. Finder's AXScrollArea
				}
			}
			return tmp
		}
		return []
	}
}

extension NSImage {
	static var statusIconDots: NSImage {
		let img = NSImage.init(size: .init(width: 20, height: 20), flipped: true) {
			let ctx = NSGraphicsContext.current!.cgContext
			let w = $0.width
			let h = $0.height
			let sw = 0.025 * w  // stroke width
			ctx.stroke(CGRect(x: 0.0 * w, y: 0.15 * h, width: 1.0 * w, height: 0.7 * h).insetBy(dx: sw / 2, dy: sw / 2), width: sw)
			ctx.fill(CGRect(x: 0, y: 0.55 * h, width: w, height: sw))
			let circle = CGRect(x: 0, y: 0.25 * h, width: 0.2 * w, height: 0.2 * w)
			ctx.fillEllipse(in: circle.offsetBy(dx: 0.12 * w, dy: 0))
			ctx.fillEllipse(in: circle.offsetBy(dx: 0.4 * w, dy: 0))
			ctx.fillEllipse(in: circle.offsetBy(dx: 0.68 * w, dy: 0))
			return true
		}
		img.isTemplate = true
		return img
	}

	static var statusIconMonitor: NSImage {
		let img = NSImage.init(size: .init(width: 21, height: 14), flipped: true) {
			let ctx = NSGraphicsContext.current!.cgContext
			let w = $0.width
			let h = $0.height
			let ssw = 0.025 * w  // small stroke width
			let lsw = 0.05 * w  // large stroke width
			// main screen
			ctx.stroke(CGRect(x: 0.1 * w, y: 0.0 * h, width: 0.8 * w, height: 0.8 * h).insetBy(dx: lsw / 2, dy: lsw / 2), width: lsw)
			ctx.clear(CGRect(x: 0.0 * w, y: 0.2 * h, width: 1.0 * w, height: 0.4 * h))
			ctx.fill(CGRect(x: 0.41 * w, y: 0.8 * h, width: 0.18 * w, height: 0.12 * h))
			ctx.fill(CGRect(x: 0.27 * w, y: 0.92 * h, width: 0.46 * w, height: 0.08 * h))
			// three windows
			ctx.stroke(CGRect(x: 0.0 * w, y: 0.28 * h, width: 0.27 * w, height: 0.24 * h).insetBy(dx: ssw / 2, dy: ssw / 2), width: ssw)
			ctx.stroke(CGRect(x: 0.34 * w, y: 0.2 * h, width: 0.32 * w, height: 0.4 * h).insetBy(dx: ssw / 2, dy: ssw / 2), width: ssw)
			ctx.stroke(CGRect(x: 0.73 * w, y: 0.28 * h, width: 0.27 * w, height: 0.24 * h).insetBy(dx: ssw / 2, dy: ssw / 2), width: ssw)
			return true
		}
		img.isTemplate = true
		return img
	}
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
// _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
