#!/usr/bin/env swift
import Cocoa
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
	private var statusItem: NSStatusItem!
	private var numScreens: Int = NSScreen.screens.count
	private var state: [Int: [Int32: [CGRect]]] = [:]  // [screencount: [pid: [windows]]]
	
	func applicationDidFinishLaunching(_ aNotification: Notification) {
		if UserDefaults.standard.bool(forKey: "invisible") == true {
			return
		}
		self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		if let button = self.statusItem.button {
			button.image = self.statusMenuIcon()
		}
		self.statusItem.menu = NSMenu(title: "")
		self.statusItem.menu!.addItem(withTitle: "Hide Status Icon", action: #selector(self.enableInvisbleMode), keyEquivalent: "")
		self.statusItem.menu!.addItem(withTitle: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q")
	}

	func statusMenuIcon() -> NSImage {
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

	@objc func enableInvisbleMode() {
		self.statusItem = nil
	}

	func applicationDidChangeScreenParameters(_ notification: Notification) {
		if numScreens != NSScreen.screens.count {
			// save state
			self.state[numScreens] = self.getState()
			numScreens = NSScreen.screens.count
			// restore state
			if let previous = self.state[numScreens] {
				self.restoreState(previous)
			}
		}
	}
	
	private func getState() -> [Int32: [CGRect]] {
		var state: [Int32: [CGRect]] = [:]
		let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as NSArray? as? [[String: AnyObject]]
		for entry in windowList! {
			let pid = entry[kCGWindowOwnerPID as String] as! Int32
			let layer = entry[kCGWindowLayer as String] as! Int32
			// let owner = entry[kCGWindowOwnerName as String] as! String
			if layer != 0 {
				continue
			}
			let b = entry[kCGWindowBounds as String] as! [String: Int]
			let bounds = CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!)
			if (state[pid] == nil) {
				state[pid] = [bounds]
			} else {
				state[pid]!.append(bounds)
			}
		}
		return state
	}
	
	private func restoreState(_ state: [Int32: [CGRect]]) {
		for (pid, bounds) in state {
			self.setWindowSizes(pid, bounds)
		}
	}
	
	private func setWindowSizes(_ pid: Int32, _ sizes: [CGRect]) {
		let win = self.axWinList(pid)
		guard win.count > 0, win.count == sizes.count else {
			print(pid, win.count, sizes.count)
			return
		}
		for i in 0 ..< win.count {
			var newPoint = sizes[i].origin
			var newSize = sizes[i].size
			AXUIElementSetAttributeValue(win[i], kAXPositionAttribute as CFString,
										 AXValueCreate(AXValueType(rawValue: kAXValueCGPointType)!, &newPoint)!);
			AXUIElementSetAttributeValue(win[i], kAXSizeAttribute as CFString,
										 AXValueCreate(AXValueType(rawValue: kAXValueCGSizeType)!, &newSize)!);
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

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
// _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
