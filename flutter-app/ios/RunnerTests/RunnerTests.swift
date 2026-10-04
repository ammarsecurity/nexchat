import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  func testConsumingRingRetainsIdentityForAnswerAndDecline() {
    let store = IncomingCallEventStore()
    store.save(["callId": "attempt-a", "conversationId": "room", "action": "ring"])
    XCTAssertEqual(store.consume()?["action"] as? String, "ring")
    XCTAssertNil(store.consume())
    XCTAssertTrue(store.matches("attempt-a"))
    store.setAction("accept")
    XCTAssertEqual(store.consume()?["callId"] as? String, "attempt-a")
    store.setAction("decline")
    XCTAssertEqual(store.consume()?["conversationId"] as? String, "room")
  }

  func testDelayedCancelForOldAttemptDoesNotMatchNewCallInSameRoom() {
    let store = IncomingCallEventStore()
    store.save(["callId": "attempt-a", "conversationId": "room", "action": "ring"])
    store.save(["callId": "attempt-b", "conversationId": "room", "action": "ring"])
    XCTAssertFalse(store.matches("attempt-a"))
    XCTAssertTrue(store.matches("attempt-b"))
    XCTAssertFalse(store.matches(nil))
    XCTAssertFalse(store.matches(""))
  }

  func testClearRemovesBothIdentityAndQueuedEvent() {
    let store = IncomingCallEventStore()
    store.save(["callId": "attempt-a", "action": "ring"])
    store.clear()
    XCTAssertNil(store.active)
    XCTAssertNil(store.consume())
    store.setAction("accept")
    XCTAssertNil(store.consume())
  }
}
