import SwiftUI
import AppKit

struct FlowContextMenuContent: View {
    @EnvironmentObject private var profileStore: CaptureProfileStore
    @Environment(\.captureProfileActions) private var profileActions
    let flow: MitmFlow
    let isHostPinned: Bool
    let isAppPinned: Bool

    let onEditRetry: () -> Void
    let onMapLocal: () -> Void
    let onPinHost: () -> Void
    let onUnpinHost: () -> Void
    let onPinApp: () -> Void
    let onUnpinApp: () -> Void
    let onFilterApp: () -> Void
    let onFilterDevice: () -> Void

    var body: some View {
        Button {
            ClipboardHelper.copy(flow.request?.url)
        } label: {
            Label("Copy URL", systemImage: "link")
        }
        .disabled(flow.request?.url == nil)

        Button {
            ClipboardHelper.copy(flow.curlString)
        } label: {
            Label("Copy cURL", systemImage: "terminal")
        }
        .disabled(flow.request == nil)

        Divider()

        Section {
            if let member = CaptureProfileMember.request(for: flow) {
                profileMemberMenu("This Call", scope: "request", member: member)
            }
            if !flow.host.isEmpty {
                profileMemberMenu("This Host", scope: "host", member: .host(flow.host))
            }
            if let app = flow.clientApp, !FlowClientApp.normalizedID(app.id).isEmpty {
                profileMemberMenu("This App", scope: "app", member: .app(app.id))
            }
        } header: {
            Label("Profiles", systemImage: "person.crop.rectangle.stack")
        }
        .disabled(!profileStore.canEdit)

        Section {
            Button(action: onEditRetry) {
                Label("Edit & Retry", systemImage: "arrow.triangle.2.circlepath")
            }

            Button(action: onMapLocal) {
                Label("Map Local", systemImage: "pencil.and.outline")
            }
        } header: {
            Label("Actions", systemImage: "bolt")
        }

        Section {
            Button {
                openTeamsWithCopiedDetails()
            } label: {
                Label("Open Teams (copied)", systemImage: "message")
            }
            .disabled(flow.request == nil)

            if flow.xRequestID != nil {
                Button {
                    presentRequestIDShare()
                } label: {
                    Label("Share X-Request-ID…", systemImage: "number")
                }
            }

            Button {
                presentDetailsShare()
            } label: {
                Label("Share Details…", systemImage: "square.and.arrow.up")
            }
            .disabled(flow.request == nil)

            Button {
                presentURLShare()
            } label: {
                Label("Share URL…", systemImage: "link")
            }
            .disabled(flow.request?.url == nil)

            Button {
                presentCurlShare()
            } label: {
                Label("Share cURL…", systemImage: "terminal")
            }
            .disabled(flow.request == nil)
        } header: {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        if shouldShowFilters || shouldShowPins {
            Divider()
        }

        if shouldShowFilters {
            Section {
                if flow.clientApp != nil {
                    Button(action: onFilterApp) {
                        Label("Filter by App", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                if !flow.clientIP.isEmpty {
                    Button(action: onFilterDevice) {
                        Label("Filter by Device", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            } header: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
        }

        if shouldShowPins {
            Section {
                if flow.clientApp != nil {
                    if isAppPinned {
                        Button(action: onUnpinApp) {
                            Label("Unpin App", systemImage: "pin.slash")
                        }
                    } else {
                        Button(action: onPinApp) {
                            Label("Pin App", systemImage: "pin")
                        }
                    }
                }

                if !flow.host.isEmpty {
                    if isHostPinned {
                        Button(action: onUnpinHost) {
                            Label("Unpin Host", systemImage: "pin.slash")
                        }
                    } else {
                        Button(action: onPinHost) {
                            Label("Pin Host", systemImage: "pin")
                        }
                    }
                }
            } header: {
                Label("Pin", systemImage: "pin")
            }
        }

        Divider()

        Section {
            Button {
                let titles = SharePresenter.availableServiceTitles(for: [flow.request?.url ?? "", flow.teamsShareText ?? ""])
                ClipboardHelper.copy(titles.joined(separator: "\n"))
            } label: {
                Label("Copy share targets", systemImage: "list.bullet")
            }
        } header: {
            Label("Debug", systemImage: "ladybug")
        }
    }

    private func profileMemberMenu(_ title: LocalizedStringKey, scope: String, member: CaptureProfileMember) -> some View {
        Section {
            Button("Create Profile…", systemImage: "plus") { profileActions?.create(member) }
                .accessibilityIdentifier("capture.profile.create.\(scope)")
            if !profileStore.profiles.isEmpty {
                Divider()
                ForEach(profileStore.profiles) { profile in
                    Button(profile.name) { profileActions?.add(member, profile.id) }
                        .disabled(profile.members.contains(member.normalized ?? member))
                        .accessibilityIdentifier("capture.profile.add.\(scope).\(profile.name)")
                }
            }
        } header: { Text(title) }
    }

    private var shouldShowFilters: Bool {
        flow.clientApp != nil || !flow.clientIP.isEmpty
    }

    private var shouldShowPins: Bool {
        flow.clientApp != nil || !flow.host.isEmpty
    }

    private func presentDetailsShare() {
        guard let shareText = flow.teamsShareText else { return }
        SharePresenter.present(items: [shareText])
    }

    private func presentRequestIDShare() {
        guard let requestID = flow.xRequestID else { return }
        SharePresenter.present(items: [requestID])
    }

    private func presentURLShare() {
        guard let urlString = flow.request?.url else { return }
        guard let url = URL(string: urlString) else { return }
        SharePresenter.present(items: [url])
    }

    private func presentCurlShare() {
        guard let curl = flow.curlString else { return }
        SharePresenter.present(items: [curl])
    }

    private func openTeamsWithCopiedDetails() {
        guard let shareText = flow.teamsShareText else { return }
        ClipboardHelper.copy(shareText)
        openTeams()
    }

    private func openTeams() {
        let candidates = [
            "msteams://teams.microsoft.com",
            "https://teams.microsoft.com/"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

struct CaptureProfileActions {
    let create: (CaptureProfileMember) -> Void
    let add: (CaptureProfileMember, UUID) -> Void
}

private struct CaptureProfileActionsKey: EnvironmentKey {
    static let defaultValue: CaptureProfileActions? = nil
}

extension EnvironmentValues {
    var captureProfileActions: CaptureProfileActions? {
        get { self[CaptureProfileActionsKey.self] }
        set { self[CaptureProfileActionsKey.self] = newValue }
    }
}
