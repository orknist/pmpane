import AppKit
import SwiftUI

/// Forces the underlying AppKit table to grow/shrink only the last column.
/// SwiftUI’s `.width(min:ideal:max:)` alone often still distributes leftover width.
struct TableLastColumnAutosize: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.apply()
    }

    final class ProbeView: NSView {
        private var applied = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        override func layout() {
            super.layout()
            apply()
        }

        func apply() {
            guard let tableView = findEnclosingTableView() else { return }

            if tableView.columnAutoresizingStyle != .lastColumnOnlyAutoresizingStyle {
                tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
                applied = false
            }

            let columns = tableView.tableColumns
            guard !columns.isEmpty else { return }

            var needsFit = !applied
            for (index, column) in columns.enumerated() {
                let isLast = index == columns.count - 1
                let desired: NSTableColumn.ResizingOptions = isLast
                    ? [.autoresizingMask, .userResizingMask]
                    : [.userResizingMask]
                if column.resizingMask != desired {
                    column.resizingMask = desired
                    needsFit = true
                }
            }

            if needsFit {
                tableView.sizeLastColumnToFit()
                applied = true
            }
        }

        private func findEnclosingTableView() -> NSTableView? {
            var ancestor: NSView? = superview
            while let current = ancestor {
                if let table = findTableView(in: current) {
                    return table
                }
                ancestor = current.superview
            }
            return nil
        }

        private func findTableView(in root: NSView) -> NSTableView? {
            if let table = root as? NSTableView { return table }
            for child in root.subviews {
                if let found = findTableView(in: child) { return found }
            }
            return nil
        }
    }
}

extension View {
    /// Only the last table column absorbs leftover horizontal space.
    func tableLastColumnAutosize() -> some View {
        background(TableLastColumnAutosize())
    }
}
