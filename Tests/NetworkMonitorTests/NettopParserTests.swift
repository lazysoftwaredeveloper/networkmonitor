import XCTest
@testable import NetworkMonitorCore

final class NettopParserTests: XCTestCase {
    func testParsesProcessRow() {
        let row = NettopParser.parseRow("02:21:32.760799,Google Chrome H.1578,4529465,414001,")
        XCTAssertEqual(row?.pid, 1578)
        XCTAssertEqual(row?.processName, "Google Chrome H")
        XCTAssertEqual(row?.bytesIn, 4_529_465)
        XCTAssertEqual(row?.bytesOut, 414_001)
    }

    func testSplitsPIDAtLastDot() {
        let row = NettopParser.parseRow("02:21:32,com.apple.WebKit.12345,10,20,")
        XCTAssertEqual(row?.processName, "com.apple.WebKit")
        XCTAssertEqual(row?.pid, 12345)
    }

    func testHandlesCommaInProcessName() {
        let row = NettopParser.parseRow("02:21:32,Example, Helper.999,111,222,")
        XCTAssertEqual(row?.pid, 999)
        XCTAssertEqual(row?.bytesIn, 111)
        XCTAssertEqual(row?.bytesOut, 222)
    }

    func testDiscardsInitialBaselineSample() {
        var parser = NettopParser()
        _ = parser.consume("time,,bytes_in,bytes_out,\n01:00:00,Safari.10,100,200,\n")
        XCTAssertNil(parser.flush())

        _ = parser.consume("time,,bytes_in,bytes_out,\n01:00:02,Safari.10,25,30,\n")
        let sample = parser.flush()
        XCTAssertEqual(sample?.count, 1)
        XCTAssertEqual(sample?.first?.bytesIn, 25)
        XCTAssertEqual(sample?.first?.bytesOut, 30)
    }

    func testRejectsRowsWithoutPID() {
        XCTAssertNil(NettopParser.parseRow("01:00:00,header,bytes_in,bytes_out,"))
        XCTAssertNil(NettopParser.parseRow("01:00:00,listener,,"))
    }
    func testParsesIdleProcessWithEmptyCounters() {
        let row = NettopParser.parseRow("02:21:32.760799,airportd.494,,,")
        XCTAssertEqual(row?.pid, 494)
        XCTAssertEqual(row?.bytesIn, 0)
        XCTAssertEqual(row?.bytesOut, 0)
    }

    func testEmitsEmptySamplesAfterInitialBaseline() {
        var parser = NettopParser()
        _ = parser.consume("time,,bytes_in,bytes_out,\n01:00:00,Safari.10,100,200,\n")
        XCTAssertNil(parser.flush())

        let emptySample = parser.consume("time,,bytes_in,bytes_out,\n")
        XCTAssertEqual(emptySample.count, 1)
        XCTAssertTrue(emptySample[0].isEmpty)
    }

}
