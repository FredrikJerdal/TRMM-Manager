import SwiftUI

struct AgentAuditView: View {
    let agentId: String
    let baseURL: String
    let apiKey: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @AppStorage("hideSensitive") private var hideSensitiveInfo: Bool = false
    
    @State private var auditLogs: [AuditLog] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var effectiveAPIKey: String {
        return KeychainHelper.shared.getAPIKey() ?? apiKey
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DarkGradientBackground()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if auditLogs.isEmpty && !isLoading && errorMessage == nil {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.text.fill")
                                    .font(.title)
                                    .foregroundStyle(appTheme.accent.opacity(0.5))
                                Text("No audit logs found")
                                    .font(.headline)
                                    .foregroundStyle(Color.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(20)
                        } else if let errorMessage {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title)
                                    .foregroundStyle(.red)
                                Text("Error Loading Logs")
                                    .font(.headline)
                                    .foregroundStyle(Color.white)
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(Color.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(20)
                        } else {
                            LazyVStack(spacing: 12, pinnedViews: []) {
                                ForEach(auditLogs) { log in
                                    auditLogCard(log)
                                }
                            }
                            .padding(20)
                            .animation(.easeInOut(duration: 0.25), value: auditLogs.count)
                        }
                    }
                }
                
                if isLoading {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    ProgressView("Loading audit logs…")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
            }
            .navigationTitle(L10n.key("agents.management.audit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(appTheme.accent)
                }
            }
        }
        .task {
            await fetchAuditLogs()
        }
    }
    
    private func auditLogCard(_ log: AuditLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top: author and action label (keeps command out of the top)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(log.action.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                }

                Spacer(minLength: 0)
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)

            // Details grid
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    infoLabel("Agent", log.agent)
                    infoLabel("Client", log.site.client_name)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 16) {
                    infoLabel("Site", log.site.name)
                    infoLabel("Time", formatTime(log.entry_time))
                    Spacer(minLength: 0)
                }

                HStack(spacing: 16) {
                    infoLabel("Object", log.object_type.capitalized)
                    infoLabel("IP", hideSensitiveInfo ? "[REDACTED]" : log.ip_address)
                    Spacer(minLength: 0)
                }
            }
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.8))

            // Command shown below details (full wrap, grows card)
            VStack(alignment: .leading, spacing: 6) {
                Text("Command")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(log.message)
                    .font(.caption)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private func infoLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func formatTime(_ timestamp: String) -> String {
        // Use the shared date utilities which respect user settings/fallbacks
        return formatLastSeenTimestamp(timestamp)
    }
    
    @MainActor
    private func fetchAuditLogs() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let sanitizedURL = baseURL.removingTrailingSlash()
        guard let url = URL(string: "\(sanitizedURL)/logs/audit/") else {
            errorMessage = "Invalid URL"
            return
        }
        
        let payload: [String: Any] = [
            "pagination": [
                "sortBy": "entry_time",
                "descending": true,
                "page": 1,
                "rowsPerPage": 1000,
                "rowsNumber": 1000
            ],
            "agentFilter": [agentId]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            errorMessage = "Failed to encode payload"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = jsonData
        request.addDefaultHeaders(apiKey: effectiveAPIKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        DiagnosticLogger.shared.logHTTPRequest(method: "PATCH", url: url.absoluteString, headers: request.allHTTPHeaderFields ?? [:])
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                DiagnosticLogger.shared.logHTTPResponse(method: "PATCH", url: url.absoluteString, status: httpResponse.statusCode, data: data)
                
                guard httpResponse.statusCode == 200 else {
                    if httpResponse.statusCode == 403 {
                        errorMessage = L10n.key("agents.management.audit.permission")
                    } else {
                        errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                    }
                    return
                }
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(AuditLogResponse.self, from: data)
                withAnimation(.easeInOut(duration: 0.25)) {
                    auditLogs = decodedResponse.audit_logs
                }
                DiagnosticLogger.shared.append("Fetched \(decodedResponse.audit_logs.count) audit logs for agent \(agentId)")
            } catch {
                let responseBody = String(data: data, encoding: .utf8) ?? "<unable to decode response body>"
                let diagnostic = """
                MALFORMED /logs/audit/ RESPONSE
                Error: \(describeDecodingError(error))
                Expected: { audit_logs: [AuditLog], total: Int } with audit_log fields: id, entry_time, ip_address, site { id, name, client_name }, username, agent, agent_id, action, object_type, before_value, after_value, message, debug_info
                Got: \(summarizeAuditPayloadShape(from: data))
                Full Response JSON:
                \(responseBody)
                """
                errorMessage = L10n.key("agents.management.audit.decodeError")
                DiagnosticLogger.shared.appendError(diagnostic)
            }
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticLogger.shared.appendError("Error fetching audit logs: \(error.localizedDescription)")
        }
    }

    private func describeDecodingError(_ error: Error) -> String {
        guard let decErr = error as? DecodingError else {
            return error.localizedDescription
        }

        switch decErr {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Missing key '\(key.stringValue)' at \(path.isEmpty ? "root" : path): \(context.debugDescription)"
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Type mismatch for \(type) at \(path.isEmpty ? "root" : path): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Missing value for \(type) at \(path.isEmpty ? "root" : path): \(context.debugDescription)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Corrupted data at \(path.isEmpty ? "root" : path): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private func summarizeAuditPayloadShape(from data: Data) -> String {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return "<non-JSON response>"
        }

        guard let dictionary = jsonObject as? [String: Any] else {
            return "Top-level type: \(type(of: jsonObject))"
        }

        var parts: [String] = ["Top-level keys: \(dictionary.keys.sorted().joined(separator: ", "))"]
        if let logs = dictionary["audit_logs"] as? [[String: Any]] {
            parts.append("audit_logs count: \(logs.count)")
            if let first = logs.first {
                parts.append("first audit_log keys: \(first.keys.sorted().joined(separator: ", "))")
                if let before = first["before_value"] {
                    parts.append("before_value type: \(typeName(before))")
                }
                if let after = first["after_value"] {
                    parts.append("after_value type: \(typeName(after))")
                }
            }
        }
        return parts.joined(separator: " | ")
    }

    private func typeName(_ value: Any) -> String {
        switch value {
        case is NSNull:
            return "null"
        case is [String: Any]:
            return "object"
        case is [Any]:
            return "array"
        case is String:
            return "string"
        case is Bool:
            return "bool"
        case is Int, is Double, is Float, is NSNumber:
            return "number"
        default:
            return String(describing: type(of: value))
        }
    }
}
