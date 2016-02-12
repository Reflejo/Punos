//
//  MockServerTests.swift
//  PunosTests
//
//  Created by Ali Rantakari on 9.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import XCTest
import Punos

private extension NSHTTPURLResponse {
    func headerWithName(name: String) -> String? {
        return (allHeaderFields as? [String:String])?[name]
    }
    var allHeaderNames: Set<String> {
        guard let headers = allHeaderFields as? [String:String] else { return [] }
        return Set(headers.keys) ?? []
    }
}

private var sharedServer = MockHTTPServer()

class MockServerTests: XCTestCase {
    
    // ------------------------------------------------
    // MARK: Helpers; plumbing
    
    var server: MockHTTPServer { return sharedServer }
    
    override class func setUp() {
        super.setUp()
        sharedServer = MockHTTPServer()
        do {
            try sharedServer.start()
        } catch let error {
            fatalError("\(error)")
        }
    }
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
        server.clearAllMockingState()
    }
    
    func request(method: String, _ path: String, body: String? = nil, headers: [String:String]? = nil, timeout: NSTimeInterval = 2, wait: Bool = true, completionHandler: ((NSData, NSHTTPURLResponse, NSError?) -> Void)? = nil) {
        let expectation: XCTestExpectation = expectationWithDescription("Request \(method) \(path)")
        
        let request = NSMutableURLRequest(URL: NSURL(string: "\(server.baseURLString ?? "")\(path)")!)
        request.HTTPMethod = method
        if let headers = headers {
            headers.forEach { request.addValue($1, forHTTPHeaderField: $0) }
        }
        if let body = body {
            request.HTTPBody = body.dataUsingEncoding(NSUTF8StringEncoding)
        }
        
        NSURLSession.sharedSession().dataTaskWithRequest(request) { data, response, error in
            guard let response = response as? NSHTTPURLResponse else {
                XCTFail("The response should always be an NSHTTPURLResponse")
                return
            }
            completionHandler?(data!, response, error)
            expectation.fulfill()
        }.resume()
        
        if wait {
            waitForExpectationsWithTimeout(timeout) { error in
                if error != nil {
                    XCTFail("Request error: \(error)")
                }
            }
        }
    }
    
    
    // ------------------------------------------------
    // MARK: Test cases
    
    func testStartupAndShutdownEffectOnAPI() {
        let s = MockHTTPServer()
        
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.port, 0)
        XCTAssertNil(s.baseURLString)
        
        try! s.start(8888)
        
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.port, 8888)
        XCTAssertEqual(s.baseURLString, "http://localhost:8888")
        
        s.stop()
        
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.port, 0)
        XCTAssertNil(s.baseURLString)
    }
    
    func testResponseMocking_defaultsWhenNoMockResponsesConfigured() {
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 200)
            XCTAssertEqual(response.allHeaderNames, [])
            XCTAssertEqual(data.length, 0)
            XCTAssertNil(error)
        }
    }
    
    func testResponseMocking_defaultMockResponseWithNoMatcher() {
        let mockData = "foofoo".dataUsingEncoding(NSUTF16StringEncoding)!
        server.mockResponse(
            status: 201,
            data: mockData,
            headers: ["X-Greeting": "Hey yall", "Content-Type": "thing/foobar"],
            onlyOnce: false,
            matcher: nil)
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
            XCTAssertEqual(response.allHeaderNames, ["X-Greeting", "Content-Type", "Content-Length"])
            XCTAssertEqual(response.headerWithName("X-Greeting"), "Hey yall")
            XCTAssertEqual(response.headerWithName("Content-Type"), "thing/foobar")
            XCTAssertEqual(response.headerWithName("Content-Length"), "\(mockData.length)")
            XCTAssertEqual(data, mockData)
            XCTAssertNil(error)
        }
    }
    
    func testResponseMocking_matcher() {
        server.mockResponse(status: 500) // default fallback
        server.mockResponse(status: 202) { request in
            return (request.method == "GET" && request.path.containsString("foo"))
        }
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        request("GET", "/dom/xfoobar/gg") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        
        request("POST", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 500)
        }
        request("GET", "/oof") { data, response, error in
            XCTAssertEqual(response.statusCode, 500)
        }
    }
    
    func testResponseMocking_matcher_overlapping() {
        server.mockResponse(status: 201) { request in
            return request.path.containsString("foo")
        }
        server.mockResponse(status: 202) { request in
            return request.path.containsString("bar")
        }
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        request("GET", "/bar") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        
        // Both match --> 1st one added wins
        request("GET", "/foobar") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
    }
    
    func testResponseMocking_matcher_viaEndpointParameter() {
        server.mockResponse(endpoint: "GET /foo", status: 201)
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        
        // If `matcher` and `endpoint` are both given, `endpoint`
        // takes precedence:
        //
        server.mockResponse(endpoint: "GET /foo", status: 201) { req in return false }
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
    }
    
    func testResponseMocking_onlyOnce_withoutMatcher() {
        
        // The responses should be dealt in the same order in which they were configured:
        //
        server.mockResponse(status: 201, onlyOnce: true)
        server.mockResponse(status: 202, onlyOnce: true)
        server.mockResponse(status: 203, onlyOnce: true)
        server.mockResponse(status: 500) // default fallback
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 203)
        }
        
        // All three 'onlyOnce' responses are exhausted — we should get the fallback:
        request("POST", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 500)
        }
    }
    
    func testResponseMocking_onlyOnce_withMatcher() {
        server.mockResponse(status: 500) // default fallback
        
        let matcher: MockResponseMatcher = { request in request.path == "/match-me" }
        server.mockResponse(status: 201, onlyOnce: true, matcher: matcher)
        server.mockResponse(status: 202, onlyOnce: true, matcher: matcher)
        server.mockResponse(status: 203, onlyOnce: true, matcher: matcher)
        
        request("GET", "/match-me") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        
        // Try one non-matching request "in between":
        request("POST", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 500)
        }
        
        request("GET", "/match-me") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        request("GET", "/match-me") { data, response, error in
            XCTAssertEqual(response.statusCode, 203)
        }
        
        // All three 'onlyOnce' responses are exhausted — we should get the fallback:
        request("POST", "/match-me") { data, response, error in
            XCTAssertEqual(response.statusCode, 500)
        }
    }
    
    func testLatestRequestsGetters() {
        request("GET", "/gettersson")
        request("HEAD", "/headster")
        
        request("POST", "/foo/bar?a=1&b=2", body: "i used to be with it", headers: ["X-Eka":"eka", "X-Toka":"toka"]) { data, response, error in
            XCTAssertEqual(self.server.latestRequests.count, 3)
            XCTAssertEqual(self.server.latestRequestEndpoints, [
                "GET /gettersson",
                "HEAD /headster",
                "POST /foo/bar",
                ])
            
            XCTAssertNotNil(self.server.lastRequest)
            if self.server.lastRequest != nil {
                XCTAssertEqual(self.server.lastRequest?.endpoint, "POST /foo/bar")
                XCTAssertEqual(self.server.lastRequest?.method, "POST")
                XCTAssertEqual(self.server.lastRequest?.path, "/foo/bar")
                XCTAssertEqual(self.server.lastRequest!.query, ["a":"1", "b":"2"])
                XCTAssertEqual(self.server.lastRequest!.headers["X-Eka"], "eka")
                XCTAssertEqual(self.server.lastRequest!.headers["X-Toka"], "toka")
                XCTAssertEqual(self.server.lastRequest?.data, "i used to be with it".dataUsingEncoding(NSUTF8StringEncoding))
            }
            
            self.server.clearLatestRequests()
            
            XCTAssertEqual(self.server.latestRequests.count, 0)
            XCTAssertNil(self.server.lastRequest)
        }
    }
    
    func testResponseMocking_delay() {
        // Let's try to keep the delay short enough to not make our
        // tests slow, but long enough for us to reliably check that
        // it was intentional and not accidental
        //
        let delayToTest: NSTimeInterval = 0.5
        
        // First try with NO delay:
        //
        server.mockResponse(status: 205, delay: 0)
        
        let noDelayStartDate = NSDate()
        request("GET", "/foo") { data, response, error in
            let endDate = NSDate()
            XCTAssertEqual(response.statusCode, 205)
            XCTAssertLessThan(endDate.timeIntervalSinceDate(noDelayStartDate), 0.1)
        }
        
        // Then try with the delay:
        //
        server.clearMockResponses()
        server.mockResponse(status: 201, delay: delayToTest)
        
        let withDelayStartDate = NSDate()
        request("GET", "/foo") { data, response, error in
            let endDate = NSDate()
            XCTAssertEqual(response.statusCode, 201)
            XCTAssertGreaterThan(endDate.timeIntervalSinceDate(withDelayStartDate), delayToTest)
        }
    }
    
    func testResponseMocking_headersSpecialCasedByGCDWebServerAPI() {
        
        // Test that we can, if we want, modify the values of response headers
        // that the GCDWebServer API handles as some kind of a special case
        // (either through a bespoke property/API or by setting values by default
        // on its own.)
        //
        let fakeHeaders = [
            "Etag": "-etag",
            "Cache-Control": "-cc",
            "Server": "-server",
            "Date": "-date",
            "Connection": "-connection",
            "Last-Modified": "-lm",
            "Transfer-Encoding": "-te",
        ]
        server.mockResponse(headers: fakeHeaders)
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.allHeaderFields as! [String:String], fakeHeaders)
        }
    }
    
    func testManyRequestsInQuickSuccession() {
        server.mockResponse(status: 201, onlyOnce: true)
        server.mockResponse(status: 202, onlyOnce: true)
        server.mockResponse(status: 203, onlyOnce: true)
        server.mockResponse(status: 204, onlyOnce: true)
        server.mockResponse(status: 205, onlyOnce: true)
        
        let waitBetweenRequestSends: NSTimeInterval = 0.01
        
        request("GET", "/foo1", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo2", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo3", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 203)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo4", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 204)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo5") { data, response, error in
            XCTAssertEqual(response.statusCode, 205)
            XCTAssertEqual(self.server.latestRequestEndpoints, [
                "GET /foo1",
                "GET /foo2",
                "GET /foo3",
                "GET /foo4",
                "GET /foo5",
                ])
        }
    }
    
    func testConcurrentRequests() {
        server.mockResponse(status: 201, delay: 0.5, onlyOnce: true)
        server.mockResponse(status: 202, delay: 0.1, onlyOnce: true)
        server.mockResponse(status: 203, delay: 0.2, onlyOnce: true)
        server.mockResponse(status: 204, delay: 0.1, onlyOnce: true)
        server.mockResponse(status: 205, onlyOnce: true)
        
        let waitBetweenRequestSends: NSTimeInterval = 0.05
        
        let finishedRequestStatusesLock = NSLock()
        var finishedRequestStatuses = [Int]()
        func statusFinished(status: Int) {
            finishedRequestStatusesLock.lock()
            finishedRequestStatuses.append(status)
            finishedRequestStatusesLock.unlock()
        }
        
        request("GET", "/foo1", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
            statusFinished(response.statusCode)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo2", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
            statusFinished(response.statusCode)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo3", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 203)
            statusFinished(response.statusCode)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo4", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 204)
            statusFinished(response.statusCode)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo5", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 205)
            statusFinished(response.statusCode)
        }
        
        waitForExpectationsWithTimeout(2) { error in
            if error != nil {
                XCTFail("Request error: \(error)")
                return
            }
            
            XCTAssertEqual(self.server.latestRequestEndpoints, [
                "GET /foo1",
                "GET /foo2",
                "GET /foo3",
                "GET /foo4",
                "GET /foo5",
                ])
            
            // The first request (that got the status 201) should have
            // gotten its response the _last_, due to the long delay):
            XCTAssertEqual(finishedRequestStatuses.count, 5)
            XCTAssertEqual(finishedRequestStatuses.last, 201)
        }
    }
    
    // TODO: test "convenience" versions of .mockResponse()
    
}
