#!/usr/bin/env swift
import Cocoa
import AppKit

typealias AppPID = Int32  // see kCGWindowOwnerPID
typealias WinNum = Int  // see kCGWindowNumber (Int32) and NSWindow.windowNumber (Int)
typealias WinPos = (WinNum, CGRect)  // win-num, bounds
typealias WinConf = [AppPID: [WinPos]]  // app-pid, window-list
typealias SpaceId = WinNum  // see NSWindow.windowNumber (Int)

class AppDelegate: NSObject, NSApplicationDelegate {
	private var statusItem: NSStatusItem!
	private var numScreens: Int = NSScreen.screens.count
	private var state: [Int: WinConf] = [:]  // [screencount: [pid: [windows]]]

	private var spacesAll: [SpaceId] = []  // keep forever (and keep order)
	private var spacesVisited: Set<WinNum> = []  // fill-up on space-switch
	private var spacesNeedRestore: Set<SpaceId> = []  // dropped after restore

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		// show Accessibility Permissions popup
		AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() : true] as CFDictionary)
		// track space changes
		NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.activeSpaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
		_ = self.currentSpace()  // create space-id win for current space
		self.spacesVisited = Set(self.getWinIds())
		// create status menu icon
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
		self.statusItem.menu!.addItem(withTitle: "Memmon (v1.5)", action: nil, keyEquivalent: "")
		self.statusItem.menu!.addItem(withTitle: "Hide Status Icon", action: #selector(self.enableInvisbleMode), keyEquivalent: "")
		self.statusItem.menu!.addItem(withTitle: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q")
	}

	@objc func enableInvisbleMode() {
		self.statusItem = nil
	}

	func applicationDidChangeScreenParameters(_ notification: Notification) {
		if self.numScreens != NSScreen.screens.count {
			self.saveState()
			self.numScreens = NSScreen.screens.count
			self.spacesVisited.removeAll(keepingCapacity: true)
			self.restoreState()
		}
	}
	
	private func getWinIds(allSpaces: Bool = false) -> [WinNum] {
		NSWindow.windowNumbers(options: allSpaces ? [.allApplications, .allSpaces] : .allApplications)?.map{ $0.intValue } ?? []
	}
	
	// MARK: - Save State (CGWindow) -
	
	private func saveState() {
		self.spacesNeedRestore = Set(self.spacesAll)
		if self.state[self.numScreens] == nil {
			self.state[self.numScreens] = [:]  // otherwise state.keys wont run
		}
		let newState = self.getState()
		let dummy: WinPos = (0, CGRect.zero)
		for kNum in self.state.keys {
			let isCurrent = kNum == self.numScreens
			var tmp_state: WinConf = [:]
			for (n_app, n_windows) in newState {
				if let old_windows = self.state[kNum]![n_app] {
					var win_arr: [WinPos] = []
					for n_win in n_windows {
						// In theory, every space that was visited, was also restored.
						// If not visited (and not restored) then windows may still appear minimized,
						// so we rather copy the old value, assuming windows weren't moved while in an unvisited space.
						if isCurrent && self.spacesVisited.contains(n_win.0) {
							win_arr.append(n_win)
						} else {
							// caution! the positions of all other states are updated as well.
							let old_win = old_windows.first { $0.0 == n_win.0 }
							win_arr.append(old_win ?? dummy)
						}
					}
					tmp_state[n_app] = win_arr
				} else if isCurrent {  // and not saved yet
					tmp_state[n_app] = n_windows  // TODO: or only add if visited?
				}
			}
			self.state[kNum] = tmp_state
		}
	}
	
	private func getState() -> WinConf {
		let allWinNums = self.getWinIds(allSpaces: true).filter { !self.spacesAll.contains($0) }
		var state: WinConf = [:]
		let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as NSArray? as? [[String: AnyObject]]
		
		for entry in windowList! {
			// let owner = entry[kCGWindowOwnerName as String] as! String
			if entry[kCGWindowLayer as String] as! CGWindowLevel != kCGNormalWindowLevel {
				continue
			}
			let winNum = entry[kCGWindowNumber as String] as! WinNum
			guard let insIdx = allWinNums.firstIndex(of: winNum) else {
				continue
			}
			let pid = entry[kCGWindowOwnerPID as String] as! AppPID
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
	
	// MARK: - Restore State (AXUIElement) -
	
	private func restoreState() {
		if let space = currentSpace(), self.spacesNeedRestore.contains(space) {
			self.spacesNeedRestore.remove(space)
			let spaceWinNums = self.getWinIds()
			self.spacesVisited.formUnion(spaceWinNums)
			for (pid, bounds) in self.state[self.numScreens] ?? [:] {
				self.setWindowSizes(pid, bounds.filter{ spaceWinNums.contains($0.0) })
			}
		}
	}
	
	private func setWindowSizes(_ pid: pid_t, _ sizes: [WinPos]) {
		guard sizes.count > 0 else { return }
		let win = self.axWinList(pid)
		guard win.count == sizes.count else { return }
		for i in 0 ..< win.count {
			var pt = sizes[i].1
			if pt.isEmpty { continue }  // filter dummy elements
			let origin = AXValueCreate(AXValueType(rawValue: kAXValueCGPointType)!, &pt.origin)!
			let size = AXValueCreate(AXValueType(rawValue: kAXValueCGSizeType)!, &pt.size)!
			AXUIElementSetAttributeValue(win[i], kAXPositionAttribute as CFString, origin);
			AXUIElementSetAttributeValue(win[i], kAXSizeAttribute as CFString, size);
		}
	}
	
	private func axWinList(_ pid: pid_t) -> [AXUIElement] {
		let appRef = AXUIElementCreateApplication(pid)
		var value: CFTypeRef?
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

	// MARK: - Space Management -

	@objc func activeSpaceChanged(_ notification: Notification) {
		self.restoreState()
	}

	private func currentSpace() -> SpaceId? {
		let thisSpace = self.getWinIds()
		var candidates = self.spacesAll.filter { thisSpace.contains($0) }
		if candidates.count > 0 {
			let best = candidates.removeFirst()
			if candidates.count > 0 {
				// if a full-screen app is closed, win moves to current active space -> remove duplicates
				self.spacesAll.removeAll { candidates.contains($0) }
				for oldNum in candidates {
					NSApp.window(withWindowNumber: oldNum)?.close()
				}
			}
			return best
		}
		// create new space-id window (space was not visited yet)
		let win = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		win.isReleasedWhenClosed = false  // win is released either way. But crashes if true.
		guard win.isOnActiveSpace else {
			// dashboard or other full-screen app that prohibits display
			return nil
		}
		win.collectionBehavior = [.ignoresCycle, .stationary]
		win.setIsVisible(true)
		self.spacesAll.append(win.windowNumber)
		return win.windowNumber
	}
}

// MARK: - Status Bar Icon -

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

// MARK: - Main Entry

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
// _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
