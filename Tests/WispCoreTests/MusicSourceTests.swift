import XCTest
@testable import WispCore

final class MusicSourceTests: XCTestCase {
    func testPlatformDomainsAndSubdomains() {
        XCTAssertEqual(MusicSource.detect(URL(string: "https://soundcloud.com/artist/song")), .soundcloud)
        XCTAssertEqual(MusicSource.detect(URL(string: "https://on.soundcloud.com/example")), .soundcloud)
        XCTAssertEqual(MusicSource.detect(URL(string: "https://artist.bandcamp.com/album/example")), .bandcamp)
        XCTAssertEqual(MusicSource.detect(URL(string: "https://example.com/music.wav")), .web)
        XCTAssertEqual(MusicSource.detect(nil), .local)
    }

    func testLookalikeAndNonwebURLs() {
        XCTAssertEqual(MusicSource.detect(URL(string: "https://bandcamp.com.example.org/track")), .web)
        XCTAssertEqual(MusicSource.detect(URL(string: "https://notsoundcloud.com/track")), .web)
        XCTAssertNil(MusicSource.validatedURL("file:///private/file"))
        XCTAssertNil(MusicSource.validatedURL("javascript:alert(1)"))
        XCTAssertNil(MusicSource.validatedURL("https://name:secret@example.com/track"))
        XCTAssertNotNil(MusicSource.validatedURL(" https://artist.bandcamp.com/track/example "))
    }
}
