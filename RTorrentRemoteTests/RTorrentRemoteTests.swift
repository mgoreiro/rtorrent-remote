import XCTest
@testable import RTorrentRemote

final class TelegramCommandTests: XCTestCase {
    func testParsesBasicCommands() {
        XCTAssertEqual(TelegramCommand.parse("/start"), .help)
        XCTAssertEqual(TelegramCommand.parse("/list"), .list(filter: nil))
        XCTAssertEqual(TelegramCommand.parse("/list Descargando"), .list(filter: "descargando"))
        XCTAssertEqual(TelegramCommand.parse("/status"), .status)
        XCTAssertEqual(TelegramCommand.parse("/pause 3"), .pause("3"))
        XCTAssertEqual(TelegramCommand.parse("/resume all"), .resume("all"))
        XCTAssertEqual(TelegramCommand.parse("/confirm"), .confirm)
    }

    func testStripsBotSuffixAndIsCaseInsensitive() {
        XCTAssertEqual(TelegramCommand.parse("/LIST@MiBot"), .list(filter: nil))
    }

    func testMagnetAndURLAreAdds() {
        XCTAssertEqual(TelegramCommand.parse("magnet:?xt=urn:btih:abc"), .add("magnet:?xt=urn:btih:abc"))
        XCTAssertEqual(TelegramCommand.parse("https://x.org/a.torrent"), .add("https://x.org/a.torrent"))
    }

    func testDestructiveCommandsRequireArgument() {
        XCTAssertEqual(TelegramCommand.parse("/remove"), .unknown("/remove"))
        XCTAssertEqual(TelegramCommand.parse("/removedata 2"), .removeData("2"))
    }

    func testSpeedParsing() {
        XCTAssertEqual(TelegramCommand.parse("/speed"), .speed(down: nil, up: nil))
        XCTAssertEqual(TelegramCommand.parse("/speed 500 100"), .speed(down: 500, up: 100))
    }

    func testPlainTextIsUnknown() {
        XCTAssertEqual(TelegramCommand.parse("hola"), .unknown("hola"))
    }

    func testChatIDParsing() {
        XCTAssertEqual(parseTelegramChatIDs("123, 456;-789\nabc"), [123, 456, -789])
        XCTAssertTrue(parseTelegramChatIDs("").isEmpty)
    }
}

final class DataPathSafetyTests: XCTestCase {
    func testRejectsDangerousPaths() {
        for path in ["", "/", "/home", "relative/path/x", "/data/../etc", "/data/../../"] {
            XCTAssertFalse(RTorrentClient.isSafeDataPath(path), path)
        }
    }

    func testAcceptsNormalPaths() {
        XCTAssertTrue(RTorrentClient.isSafeDataPath("/home/user"))
        XCTAssertTrue(RTorrentClient.isSafeDataPath("/mnt/downloads/Some Movie"))
    }
}

final class ModelTests: XCTestCase {
    private func torrent(name: String, size: Int64 = 100, completed: Int64 = 0, down: Int64 = 0) -> Torrent {
        Torrent(hash: name, name: name, sizeBytes: size, completedBytes: completed, downRate: down, upRate: 0, ratio: 0,
                isActive: true, isOpen: true, isHashing: false, state: 1, label: "", message: "",
                peersConnected: 0, seedersConnected: 0, baseDirectory: "/x/y")
    }

    func testSortKeys() {
        let small = torrent(name: "b", size: 10), big = torrent(name: "a", size: 99)
        XCTAssertTrue(TorrentSortKey.size.isOrderedBefore(small, big))
        XCTAssertTrue(TorrentSortKey.name.isOrderedBefore(big, small))
    }

    func testStatusAndProgress() {
        XCTAssertEqual(torrent(name: "t", size: 100, completed: 50, down: 5).status, .downloading)
        XCTAssertEqual(torrent(name: "t", size: 100, completed: 50).progress, 0.5, accuracy: 0.0001)
        XCTAssertTrue(torrent(name: "t", size: 100, completed: 100).isComplete)
    }

    func testLegacyProfileDecodesWithNewFields() throws {
        let json = #"{"host":"srv","port":8080,"path":"/RPC2","useHTTPS":false,"username":"u","allowInsecureTLS":true}"#
        let profile = try JSONDecoder().decode(ConnectionProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.host, "srv")
        XCTAssertEqual(profile.port, 8080)
        XCTAssertEqual(profile.pinnedCertSHA256, "")
        XCTAssertFalse(profile.name.isEmpty)
    }
}

final class XMLRPCTests: XCTestCase {
    func testBuildsRequest() {
        let xml = XMLRPCClient.buildRequestXML(method: "d.erase", params: [.string("ABC")])
        XCTAssertTrue(xml.contains("<methodName>d.erase</methodName>"))
        XCTAssertTrue(xml.contains("ABC"))
    }

    func testParsesArrayResponse() throws {
        let xml = """
        <?xml version="1.0"?><methodResponse><params><param><value><array><data>
        <value><string>one</string></value><value><i4>2</i4></value>
        </data></array></value></param></params></methodResponse>
        """
        let values = try XMLRPCParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(values.first?.arrayValue.count, 2)
        XCTAssertEqual(values.first?.arrayValue[1].intValue, 2)
    }

    func testFaultThrows() {
        let xml = """
        <?xml version="1.0"?><methodResponse><fault><value><struct>
        <member><name>faultCode</name><value><int>-501</int></value></member>
        <member><name>faultString</name><value><string>boom</string></value></member>
        </struct></value></fault></methodResponse>
        """
        XCTAssertThrowsError(try XMLRPCParser.parse(data: Data(xml.utf8)))
    }
}

final class TorrentHashTests: XCTestCase {
    func testHexMagnetHash() {
        let hash = "0123456789abcdef0123456789abcdef01234567"
        XCTAssertEqual(TorrentHash.infoHash(fromMagnetURI: "magnet:?xt=urn:btih:\(hash)&dn=x")?.lowercased(), hash)
    }

    func testInvalidMagnetReturnsNil() {
        XCTAssertNil(TorrentHash.infoHash(fromMagnetURI: "not a magnet"))
    }
}

final class StatsTests: XCTestCase {
    func testDurationFormatting() {
        XCTAssertEqual(Formatters.duration(30), "30 s")
        XCTAssertEqual(Formatters.duration(125), "2 min")
        XCTAssertEqual(Formatters.duration(3 * 3600 + 5 * 60), "3 h 5 min")
        XCTAssertEqual(Formatters.duration(2 * 86_400 + 4 * 3600), "2 d 4 h")
        XCTAssertEqual(Formatters.duration(86_400), "1 d")
        XCTAssertEqual(Formatters.duration(-5), "0 s")
    }

    func testTimeOnServerAndSharing() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var stats = TorrentStats()
        XCTAssertNil(stats.timeOnServer(now: now))
        stats.addedDate = now.addingTimeInterval(-7200)
        stats.finishedDate = now.addingTimeInterval(-3600)
        XCTAssertEqual(stats.timeOnServer(now: now), 7200)
        XCTAssertEqual(stats.timeSharing(now: now), 3600)
    }
}
