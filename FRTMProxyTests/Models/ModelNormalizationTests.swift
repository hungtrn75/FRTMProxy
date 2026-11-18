import Testing
import Foundation
@testable import FRTMProxy

@Suite("Normalizzazioni dei modelli")
struct ModelNormalizationTests {

    @Test("Copied cURL negotiates compression and preserves shell arguments")
    func curlShellArguments() throws {
        let url = "https://example.com/cards?name=O'Brien&value=$HOME"
        let header = "literal $HOME `whoami` \"quoted\" \\ O'Brien"
        let body = "{\"text\":\"$HOME `whoami` O'Brien\"}\nsecond line"
        var flow = MitmFlow(id: "curl-test", event: "request")
        flow.request = MitmFlow.Request(
            method: "POST", url: url,
            headers: ["Accept-Encoding": "gzip, deflate, br", "X-Test": header],
            body: body
        )
        let command = try #require(flow.curlString)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Replace curl with an argument recorder; no network request is made.
        process.arguments = ["-f", "-c", "curl() { printf '%s\\0' \"$@\"; }; " + command]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let arguments = String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
        #expect(arguments == ["--compressed", "-X", "POST", url, "-H", "X-Test: " + header, "--data-binary", body])
    }

    @Test("Copied cURL is unavailable without a request")
    func curlWithoutRequest() {
        #expect(MitmFlow(id: "empty", event: "response").curlString == nil)
    }

    // MARK: PinnedHost

    @Test("PinnedHost.normalized trimma e abbassa il case")
    func pinnedHostNormalized() {
        #expect(PinnedHost.normalized("  API.Example.COM  ") == "api.example.com")
        #expect(PinnedHost.normalized("") == "")
    }

    @Test("PinnedHost init normalizza l'host")
    func pinnedHostInit() {
        #expect(PinnedHost(host: "  Foo.COM ").host == "foo.com")
    }

    // MARK: FlowClientApp

    @Test("FlowClientApp.normalizedID trimma e abbassa il case")
    func clientAppNormalizedID() {
        #expect(FlowClientApp.normalizedID("  Com.Foo.Bar ") == "com.foo.bar")
    }

    @Test("FlowClientApp init trimma i campi ma preserva il case di id/displayName")
    func clientAppInit() {
        let app = FlowClientApp(id: "  com.foo ", displayName: "  Foo App ", bundleIdentifier: " com.foo ")
        #expect(app.id == "com.foo")
        #expect(app.displayName == "Foo App")
        #expect(app.bundleIdentifier == "com.foo")
    }

    // MARK: String.proxySanitizedFilename

    @Test("proxySanitizedFilename sostituisce i caratteri non validi con '_'")
    func sanitizeFilename() {
        #expect("a/b:c?.txt".proxySanitizedFilename() == "a_b_c_.txt")
        #expect("https://example.com/path".proxySanitizedFilename() == "https_example.com_path")
    }

    @Test("proxySanitizedFilename genera un fallback per input vuoto/solo separatori")
    func sanitizeFilenameFallback() {
        #expect("   ".proxySanitizedFilename().hasPrefix("item-"))
        #expect("///".proxySanitizedFilename().hasPrefix("item-"))
    }

    // MARK: TrafficProfileLibrary

    @Test("profile(with:) risolve i preset built-in")
    func trafficProfileLookup() {
        #expect(TrafficProfileLibrary.profile(with: "traffic.3g").name == "3G Urban")
        #expect(TrafficProfileLibrary.profile(with: nil).id == TrafficProfileLibrary.disabled.id)
        #expect(TrafficProfileLibrary.profile(with: "does.not.exist").id == TrafficProfileLibrary.disabled.id)
    }

    @Test("manualProfile fa il clamp dei valori negativi e del packet loss oltre 100%")
    func manualProfileClamps() {
        let p = TrafficProfileLibrary.manualProfile(
            latencyMs: -50, jitterMs: -10, downstreamKbps: -1, upstreamKbps: -1,
            packetLossPercent: 150, responseDelayMs: -5
        )
        #expect(p.latencyMs == 0)
        #expect(p.jitterMs == 0)
        #expect(p.downstreamKbps == 0)
        #expect(p.upstreamKbps == 0)
        #expect(p.responseDelayMs == 0)
        #expect(p.packetLoss == 1.0) // 100% → 1.0
    }

    @Test("manualProfile converte la percentuale in frazione")
    func manualProfilePacketLossFraction() {
        #expect(TrafficProfileLibrary.manualProfile(packetLossPercent: 8).packetLoss == 0.08)
    }
}
