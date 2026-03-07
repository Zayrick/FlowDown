@testable import FlowDownModelExchange
import Foundation
import Testing

@Test func `public key round trip`() throws {
    let keyPair = ModelExchangeKeyPair()
    let encoded = keyPair.encodedPublicKey
    #expect(ModelExchangePublicKey(encoded: encoded) != nil)
    let restored = try #require(ModelExchangePublicKey(encoded: encoded))
    #expect(restored.signing == keyPair.publicKey.signing)
    #expect(restored.agreement == keyPair.publicKey.agreement)
}

@Test func `signed request verifies`() throws {
    let keyPair = ModelExchangeKeyPair()
    let builder = ModelExchangeRequestBuilder(callbackScheme: "thirdparty", keyPair: keyPair)
    let request = try builder.makeExchangeURL(
        session: "session-1",
        appName: "Tester",
        reason: "Need a model",
        capabilities: [.audio, .developerRole],
        multipleSelection: false,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
    )

    var components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
    components.queryItems = components.queryItems?.filter { $0.name != "sig" }
    let path = try ModelExchangeAPI.canonicalPath(from: #require(components.url))
    let signature = request.headers[ModelExchangeAPI.signatureHeader]
    #expect(signature != nil)
    let pub = keyPair.publicKey.signingKey
    #expect(pub != nil)
    #expect(try ModelExchangeAPI.verify(path: path, signature: #require(signature), publicKey: #require(pub)))
}

@Test func `encrypt decrypt round trip`() throws {
    let requester = ModelExchangeKeyPair()
    let peer = requester.publicKey
    let plain = Data("super-secret-model".utf8)
    let payload = try ModelExchangeCrypto.encrypt(plain, for: peer, session: "session-abc")
    let recovered = try ModelExchangeCrypto.decrypt(payload, with: requester)
    #expect(recovered == plain)
}
