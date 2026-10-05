import Testing

@testable import EZHAKit

struct SSEParserTests {
  @Test func joinsEventsSplitAcrossChunks() {
    var parser = SSEParser()
    #expect(parser.feed("event: sta").isEmpty)
    #expect(parser.feed("tus\ndata: {\"stage\":\"requesting_model\"}\n").isEmpty)
    let messages = parser.feed("\nevent: delta\ndata: {\"delta\":\"x\"}\n\n")
    #expect(messages.map(\.event) == ["status", "delta"])
    #expect(messages[0].data == #"{"stage":"requesting_model"}"#)
  }

  @Test func joinsMultiLineDataAndHandlesCRLF() {
    var parser = SSEParser()
    let messages = parser.feed("event: result\r\ndata: {\"a\":\r\ndata: 1}\r\n\r\n")
    #expect(messages == [.init(event: "result", data: "{\"a\":\n1}")])
  }

  @Test func ignoresUnknownEventsAndMapsKnownOnes() throws {
    var parser = SSEParser()
    let messages = parser.feed(
      "event: ping\ndata: {}\n\nevent: status\ndata: {\"stage\":\"finalizing\"}\n\n")
    #expect(try SSEParser.estimateEvent(from: messages[0]) == nil)
    #expect(try SSEParser.estimateEvent(from: messages[1]) == .status("finalizing"))
    #expect(throws: AIError.message("boom")) {
      try SSEParser.estimateEvent(from: .init(event: "error", data: #"{"error":"boom"}"#))
    }
  }

  @Test func flushesTheLastBlockAtTheEnd() {
    var parser = SSEParser()
    #expect(parser.feed("event: delta\ndata: {}").isEmpty)
    #expect(parser.finish().map(\.event) == ["delta"])
  }
}
