import SwiftUI
import WebKit

struct GridWebView: NSViewRepresentable {
    @ObservedObject var viewModel: GridViewViewModel
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, viewModel: viewModel)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: Coordinator.bridgeName)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.websiteDataStore = .default()
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        
        if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "GridViewWeb/dist") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        } else {
            let html = """
            <html>
            <body style="font-family: -apple-system; display:flex; align-items:center; justify-content:center; height:100%; background:#1f1f24; color:#fff;">
                <div>
                    <h2>Grid View Assets Missing</h2>
                    <p>Please run the GridViewWeb build to generate the web bundle.</p>
                </div>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    // MARK: - Coordinator
    
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let bridgeName = "gridBridge"
        
        weak var webView: WKWebView?
        weak var viewModel: GridViewViewModel?
        
        init(parent: GridWebView, viewModel: GridViewViewModel) {
            self.viewModel = viewModel
            super.init()
            self.viewModel?.coordinator = self
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Inform JS that native is ready
            send(event: "nativeReady", payload: [
                "sessionId": viewModel?.sessionId.uuidString as Any,
                "defaultEntity": viewModel?.selectedEntity.rawValue as Any
            ])
        }
        
        // MARK: - Message Handling
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Coordinator.bridgeName else { return }
            
            if let bodyString = message.body as? String,
               let data = bodyString.data(using: .utf8) {
                handleMessageData(data)
            } else if let dictionary = message.body as? [String: Any],
                      let data = try? JSONSerialization.data(withJSONObject: dictionary) {
                handleMessageData(data)
            } else {
                print("GridWebView: Unsupported message body \(message.body)")
            }
        }
        
        private func handleMessageData(_ data: Data) {
            do {
                let message = try JSONDecoder().decode(GridBridgeIncomingMessage.self, from: data)
                route(message: message)
            } catch {
                print("GridWebView: Failed to decode message \(error)")
            }
        }
        
        private func route(message: GridBridgeIncomingMessage) {
            guard let viewModel else { return }
            
            switch message.type {
            case "gridReady":
                if let entityString = message.entityType,
                   let entity = GridEntityType(rawValue: entityString) {
                    viewModel.webViewReady(for: entity)
                }
            case "requestPage":
                if let payload = message.payload,
                   let entityString = payload["entityType"]?.value as? String,
                   let entity = GridEntityType(rawValue: entityString) {
                    let offsetValue = payload["offset"]?.value
                    let limitValue = payload["limit"]?.value
                    let offset = (offsetValue as? Int) ?? (offsetValue as? Double).map { Int($0) } ?? 0
                    let limit = (limitValue as? Int) ?? (limitValue as? Double).map { Int($0) } ?? 200
                    let sorts = parseSortModel(payload["sortModel"]?.value)
                    let filters = parseFilterModel(payload["filterModel"]?.value)
                    viewModel.requestPage(entityType: entity, offset: offset, limit: limit, sorts: sorts, filters: filters)
                }
            case "edit":
                if let data = message.rawPayloadData {
                    do {
                        let payload = try JSONDecoder().decode(GridEditPayload.self, from: data)
                        viewModel.handleEdit(payload)
                    } catch {
                        print("GridWebView: Failed to decode edit payload: \(error)")
                    }
                }
            case "undo":
                viewModel.handleUndo()
            case "redo":
                viewModel.handleRedo()
            case "createCustomColumn":
                if let data = message.rawPayloadData {
                    do {
                        let request = try JSONDecoder().decode(CreateCustomColumnRequest.self, from: data)
                        viewModel.createCustomColumn(request: request)
                    } catch {
                        print("GridWebView: Failed to decode custom column request \(error)")
                    }
                }
            case "columnStateChanged":
                if let payload = message.payload,
                   let entityString = payload["entityType"]?.value as? String,
                   let entity = GridEntityType(rawValue: entityString) {
                    let order = (payload["columnOrder"]?.value as? [String]) ?? []
                    let visible = (payload["visibleColumns"]?.value as? [String]) ?? []
                    let frozen = (payload["frozenColumns"]?.value as? [String]) ?? []
                    viewModel.updateColumnState(for: entity, columnOrder: order, visibleColumns: visible, frozenColumns: frozen)
                }
            case "showColumnMenu":
                viewModel.showColumnMenu()
            case "showAddColumnSheet":
                viewModel.showAddColumnSheet()
            case "showFilterBuilder":
                viewModel.showFilterBuilder()
            case "deleteRows":
                if let payload = message.payload,
                   let recordIds = payload["recordIds"]?.value as? [String] {
                    viewModel.handleDeleteRows(recordIds: recordIds)
                }
            case "copyResponse":
                // Handle copy response from web view - put data on clipboard
                if let payload = message.payload,
                   let copyData = payload["data"]?.value as? String {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(copyData, forType: .string)
                }
            default:
                print("GridWebView: Unhandled message type \(message.type)")
            }
        }
        
        // MARK: - Sending Messages
        
        func send(event: String, payload: [String: Any]) {
            guard let webView else { return }
            var message: [String: Any] = ["type": event]
            message["payload"] = payload
            
            // Serialize to JSON string
            guard let data = try? JSONSerialization.data(withJSONObject: message),
                  let jsonString = String(data: data, encoding: .utf8) else {
                print("❌ GridWebView: Failed to serialize message \(event)")
                return
            }
            
            // Use a safer approach: encode JSON as base64, then decode in JavaScript
            // This avoids all escaping issues
            guard let jsonData = jsonString.data(using: .utf8) else {
                print("❌ GridWebView: Failed to convert JSON string to data")
                return
            }
            let base64String = jsonData.base64EncodedString()
            
            let script = """
                (function() {
                    try {
                        const base64 = "\(base64String)";
                        const jsonString = atob(base64);
                        const message = JSON.parse(jsonString);
                        window.gridBridge?.handleNativeMessage(message);
                    } catch (e) {
                        console.error('Failed to parse native message:', e);
                        console.error('Base64 length:', base64.length);
                    }
                })();
            """
            
            webView.evaluateJavaScript(script, completionHandler: { result, error in
                if let error = error {
                    print("❌ GridWebView: Failed to send message \(event) - \(error)")
                    if event == "pageData" {
                        let rowCount = (payload["rows"] as? [[String: Any]])?.count ?? 0
                        print("❌ GridWebView: pageData payload had \(rowCount) rows")
                        if rowCount > 0, let firstRow = (payload["rows"] as? [[String: Any]])?.first {
                            print("❌ GridWebView: First row keys: \(firstRow.keys.sorted())")
                            print("❌ GridWebView: First row name value: \(firstRow["contact.name"] ?? "nil")")
                        }
                    }
                } else {
                    if event == "pageData" {
                        let rowCount = (payload["rows"] as? [[String: Any]])?.count ?? 0
                        print("✅ GridWebView: Successfully sent pageData with \(rowCount) rows")
                        if rowCount > 0, let firstRow = (payload["rows"] as? [[String: Any]])?.first {
                            print("✅ GridWebView: First row has \(firstRow.keys.count) keys")
                            if let nameValue = firstRow["contact.name"] {
                                print("✅ GridWebView: First row name value: '\(nameValue)'")
                            } else {
                                print("⚠️ GridWebView: First row missing 'contact.name' key")
                            }
                        }
                    }
                }
            })
        }
        
        // MARK: - Helpers
        
        private func parseSortModel(_ value: Any?) -> [GridSortDescriptor]? {
            guard let entries = value as? [[String: Any]] else { return nil }
            let descriptors: [GridSortDescriptor] = entries.compactMap { entry in
                guard let columnId = entry["colId"] as? String else { return nil }
                guard let sortValue = entry["sort"] as? String else { return nil }
                let direction: GridSortDescriptor.Direction
                switch sortValue.lowercased() {
                case "asc":
                    direction = .ascending
                case "desc":
                    direction = .descending
                default:
                    return nil
                }
                return GridSortDescriptor(columnId: columnId, direction: direction)
            }
            return descriptors.isEmpty ? nil : descriptors
        }
        
        private func parseFilterModel(_ value: Any?) -> [String: AnyCodable]? {
            guard let dictionary = value as? [String: Any] else { return nil }
            var result: [String: AnyCodable] = [:]
            for (columnId, rawValue) in dictionary {
                guard let filterDict = rawValue as? [String: Any] else { continue }
                if let filterText = filterDict["filter"] as? String, !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result[columnId] = AnyCodable(filterText)
                } else if let values = filterDict["values"] as? [String], !values.isEmpty {
                    result[columnId] = AnyCodable(values)
                }
            }
            return result.isEmpty ? nil : result
        }
    }
}

// MARK: - Incoming Message Model

private struct GridBridgeIncomingMessage: Decodable {
    let type: String
    let entityType: String?
    let payload: [String: AnyCodable]?
    
    var rawPayloadData: Data? {
        guard let payload else { return nil }
        return try? JSONSerialization.data(withJSONObject: payload.mapValues { $0.value })
    }
}

