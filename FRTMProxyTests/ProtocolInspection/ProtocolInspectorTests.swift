import Foundation
import Testing
@testable import FRTMProxy

@Suite("ProtocolInspector")
struct ProtocolInspectorTests {
    @Test("Body preparation runs off the UI actor and preserves large JSON content")
    func backgroundBodyPreparation() async throws {
        let objects = (0..<2000).map { ["index": $0, "value": $0 * 2] }
        let data = try JSONSerialization.data(withJSONObject: objects)
        let source = String(decoding: data, as: UTF8.self)
        var prepared = await Task.detached {
            BodyRenderCache(source: source, headers: ["Content-Type": "application/json"])
        }.value
        #expect(prepared.inspection?.kind == .json)
        #expect(prepared.prettyPrinted != nil)
        let first = prepared.pretty()
        #expect(prepared.pretty() == first)
        let decoded = try JSONSerialization.jsonObject(with: Data(first.utf8)) as? [[String: Int]]
        #expect(decoded == objects)
        #expect(prepared.source == source)
    }

    @Test("Body preparation invalidates protocol and image information when headers change")
    func bodyPreparationHeaders() {
        let source = "data: hello\n\n"
        let text = BodyRenderCache(source: source, headers: ["Content-Type": "text/plain"])
        let events = BodyRenderCache(source: source, headers: ["Content-Type": "text/event-stream"])
        #expect(text.inspection?.kind == .text)
        #expect(events.inspection?.kind == .serverSentEvents)
        #expect(events.inspection?.sections.first?.content.contains("hello") == true)
        #expect(events.imageData == nil)
        let image = BodyRenderCache(source: "aGVsbG8=", headers: ["Content-Type": "image/png"])
        #expect(image.imageData == Data("hello".utf8))
        #expect(BodyRenderCache(source: nil).inspection == nil)
    }

    @Test func modernProtocolFixturesAndFalsePositiveBoundary() {
        #expect(ProtocolInspector.inspect(body: "{\"index\":1}\n{\"index\":2}\n", headers: ["Content-Type": "application/x-ndjson"])?.kind == .ndjson)
        #expect(ProtocolInspector.inspect(body: #"[{"jsonrpc":"2.0","id":1,"method":"eth_chainId"},{"jsonrpc":"2.0","id":2,"method":"eth_call"}]"#, headers: [:])?.kind == .jsonRPC)
        #expect(ProtocolInspector.inspect(body: #"{"model":"test-model","messages":[{"role":"user","content":"Hello"}]}"#, headers: [:])?.kind == .aiAPI)
        #expect(ProtocolInspector.inspect(body: #"{"model":"car"}"#, headers: [:])?.kind == .json)
        #expect(ProtocolInspector.inspect(body: nil, headers: ["Payment-Required": "opaque-proof"])?.kind == .paymentFlow)
    }
    @Test("GraphQL espone operationName e variables")
    func graphQL() {
        let result = ProtocolInspector.inspect(
            body: #"{"operationName":"Users","query":"query Users { users { id } }","variables":{"limit":2}}"#,
            headers: ["Content-Type": "application/json"]
        )
        #expect(result?.kind == .graphQL)
        #expect(result?.summary == "Users")
        #expect(result?.sections.contains(where: { $0.id == "variables" }) == true)
    }

    @Test("JWT viene decodificato senza dichiarare la firma verificata")
    func jwt() {
        let result = ProtocolInspector.inspect(
            body: nil,
            headers: ["Authorization": "Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiIxMjMifQ."]
        )
        #expect(result?.kind == .jwt)
        #expect(result?.summary == "Signature is not verified")
        #expect(result?.sections.count == 3)
    }

    @Test("SSE mantiene gli eventi separati")
    func sse() {
        let result = ProtocolInspector.inspect(
            body: "event: ping\ndata: one\n\nevent: ping\ndata: two\n",
            headers: ["content-type": "text/event-stream"]
        )
        #expect(result?.kind == .serverSentEvents)
        #expect(result?.sections.count == 2)
    }

    @Test("gRPC decodifica più frame protobuf")
    func grpc() {
        let frame = Data([0, 0, 0, 0, 3, 0x08, 0x96, 0x01]).base64EncodedString()
        let result = ProtocolInspector.inspect(body: frame, headers: ["content-type": "application/grpc"])
        #expect(result?.kind == .grpc)
        #expect(result?.sections.first?.content.contains("1: varint 150") == true)
    }

    @Test("Protobuf malformato non legge oltre il buffer")
    func malformedProtobuf() {
        #expect(ProtobufWireDecoder.decode(Data([0x0A, 0x08, 0x01])) == nil)
    }

    @Test("Header duplicati che differiscono solo per maiuscole non causano crash")
    func duplicateCaseHeaders() {
        let result = ProtocolInspector.inspect(
            body: #"{"ok":true}"#,
            headers: [
                "Content-Type": "application/json",
                "content-type": "application/problem+json"
            ]
        )

        #expect(result?.kind == .json)
    }
}
