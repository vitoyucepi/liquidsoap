def f() =
  # Default response
  def handler(req, _) =
    test.equal(req.http_version, "1.1")
    test.equal(req.method, "GET")
    test.equal(req.body(timeout=5.0), "")
    test.equal(req.query, [])
    test.equal(req.path, "/default")
  end

  harbor.http.register("/default", port=3456, handler)
  resp = http.get("http://localhost:3456/default")
  test.equal(resp.status_message, "OK")
  test.equal(resp.status_code, 200)
  test.equal(resp.http_version, "1.1")
  test.equal(resp.headers, [])
  test.equal("#{resp}", "")

  # Endpoint are executed in the order they are declared
  def handler(_, _) =
    test.fail()
  end

  harbor.http.register.regexp(r/default/g, port=3456, handler)
  harbor.http.register("/default", port=3456, handler)
  resp = http.get("http://localhost:3456/default")
  test.equal(resp.status_message, "OK")
  test.equal(resp.status_code, 200)
  test.equal(resp.http_version, "1.1")
  test.equal(resp.headers, [])
  test.equal("#{resp}", "")

  # String response with matches
  def handler(req, _) =
    test.equal(req.http_version, "1.1")
    test.equal(req.method, "GET")
    test.equal(req.body(timeout=5.0), "")
    test.equal(req.query, [("bla", "blo"), ("gni", "gno")])
    test.equal(req.path, "/path/gno/blo")
  end

  harbor.http.register("/path/:gni/:bla", port=3456, handler)
  resp = http.get("http://localhost:3456/path/gno/blo")
  test.equal(resp.status_message, "OK")
  test.equal(resp.status_code, 200)
  test.equal(resp.http_version, "1.1")
  test.equal(resp.headers, [])
  test.equal("#{resp}", "")

  # Full query
  def handler(req, res) =
    test.equal(req.http_version, "1.0")
    test.equal(req.method, "POST")
    test.equal(
      req.query,
      [("bla", "in"), ("foo", "with"), ("gnu", "gno"), ("gni", "gno")]
    )

    test.equal(
      req.headers,
      [
        ("host", "localhost:3456"),
        ("user-agent", http.user_agent),
        ("accept", "*/*"),
        ("req", "header"),
        ("content-length", "9"),
        ("content-type", "application/x-www-form-urlencoded")
      ]
    )

    test.equal(req.path, "/some/path/with/full/in/it")
    test.equal(req.body(timeout=5.0), "foobarlol")
    res.status_code(201)
    res.status_message("YYR")
    res.http_version("1.0")
    data_count = ref(3)

    def data() =
      if
        data_count() >= 0
      then
        data_count := data_count() - 1
        "gnigno"
      else
        ""
      end
    end

    res.data(data)
    res.headers([("some", "value")])
    res.content_type("liquidsoap/test")
  end

  harbor.http.register.regexp(
    r/(?<foo>[^\/]+)\/full\/(?<bla>[^\/]+)/g, method="POST", port=3456, handler
  )

  resp =
    http.post(
      http_version="1.0",
      data="foobarlol",
      headers=[("req", "header")],
      "http://localhost:3456/some/path/with/full/in/it?gni=gno&gnu=gno"
    )

  test.equal(resp.status_message, "YYR")
  test.equal(resp.status_code, 201)
  test.equal(resp.http_version, "1.0")
  test.equal(
    resp.headers,
    [
      ("some", "value"),
      ("transfer-encoding", "chunked"),
      ("content-type", "liquidsoap/test")
    ]
  )

  test.equal("#{resp}", "gnignognignognignognigno")

  # Large non-chunked query
  def handler(req, _) =
    test.equal(req.http_version, "1.1")
    test.equal(req.method, "POST")
    test.equal(req.query, [])
    test.equal(
      req.headers,
      [
        ("host", "localhost:3456"),
        ("user-agent", http.user_agent),
        ("accept", "*/*"),
        ("content-length", "10000"),
        ("content-type", "application/x-www-form-urlencoded")
      ]
    )

    test.equal(req.path, "/large_non_chunked")
    test.equal(string.length(encoding="ascii", req.body(timeout=5.0)), 10_000)
  end

  harbor.http.register("/large_non_chunked", method="POST", port=3456, handler)
  resp =
    http.post(
      data=string.make(10_000), "http://localhost:3456/large_non_chunked"
    )

  test.equal(resp.status_message, "OK")
  test.equal(resp.status_code, 200)
  test.equal(resp.http_version, "1.1")
  test.equal(resp.headers, [])
  test.equal("#{resp}", "")

  # Chunked query
  def handler(req, res) =
    test.equal(req.http_version, "1.1")
    test.equal(req.method, "POST")
    test.equal(req.query, [])
    test.equal(
      req.headers,
      [
        ("host", "localhost:3456"),
        ("user-agent", http.user_agent),
        ("accept", "*/*"),
        ("transfer-encoding", "chunked"),
        ("content-type", "application/x-www-form-urlencoded"),
        ("expect", "100-continue")
      ]
    )

    test.equal(req.path, "/chunked")
    test.equal(req.body(timeout=5.0), "foobarlol")
  end

  harbor.http.register("/chunked", method="POST", port=3456, handler)
  data =
    begin
      is_done = ref(false)
      fun () ->
        if
          is_done()
        then
          ""
        else
          is_done := true
          "foobarlol"
        end
    end

  resp = http.post(data=data, "http://localhost:3456/chunked")
  test.equal(resp.status_message, "OK")
  test.equal(resp.status_code, 200)
  test.equal(resp.http_version, "1.1")
  test.equal(resp.headers, [])
  test.equal("#{resp}", "")

  # Large chunked query
  def handler(req, res) =
    test.equal(req.http_version, "1.1")
    test.equal(req.method, "POST")
    test.equal(req.query, [])
    test.equal(
      req.headers,
      [
        ("host", "localhost:3456"),
        ("user-agent", http.user_agent),
        ("accept", "*/*"),
        ("transfer-encoding", "chunked"),
        ("content-type", "application/x-www-form-urlencoded"),
        ("expect", "100-continue")
      ]
    )

    test.equal(req.path, "/large_chunked")

    def rec f(count) =
      ret = req.data()
      if
        ret != ""
      then
        f(count + string.length(encoding="ascii", ret))
      else
        count
      end
    end

    test.equal(f(0), 10_000_000)
  end

  harbor.http.register("/large_chunked", method="POST", port=3456, handler)
  data =
    begin
      tmp = string.make(10_000)
      count = ref(10_000_000 / 10_000)
      fun () ->
        if
          0 < count()
        then
          count := count() - 1
          tmp
        else
          ""
        end
    end

  # Custom response
  def handler(req) =
    test.equal(req.http_version, "1.1")
    test.equal(req.method, "GET")
    test.equal(req.data(), "")
    test.equal(req.query, [])
    test.equal(req.path, "/custom")
    req.socket.write(
      "HTTP/1.0 201 YYR\r\nFoo: bar\r\n\r\n"
    )
    req.socket.close()
    null
  end

  harbor.http.register.simple("/custom", port=3456, handler)
  resp = http.get("http://localhost:3456/custom")
  test.equal(resp.status_message, "YYR")
  test.equal(resp.status_code, 201)
  test.equal(resp.http_version, "1.0")
  test.equal(resp.headers, [("foo", "bar")])
  test.equal("#{resp}", "")

  # Cors headers
  harbor.http.middleware.register(harbor.http.middleware.cors(origin="foo.com"))
  resp = http.get("http://localhost:3456/default")
  test.equal(resp.status_message, "OK")
  test.equal(resp.http_version, "1.1")
  test.equal(resp.status_code, 200)
  test.equal(
    resp.headers,
    [("access-control-allow-origin", "foo.com"), ("vary", "Origin")]
  )

  test.equal("#{resp}", "")

  # transport conflict
  transport = http.transport.ssl(certificate="foo", key="bla")
  try
    harbor.http.register(
      "/default", transport=transport, port=3456, fun (_, _) -> ()
    )

    test.fail()
  catch err : [error.http] do
    test.equal(
      err.message,
      "Port is already opened with a different transport"
    )
  end

  # Response ended
  read = ref(fun (~timeout:_) -> error.raise(error.assertion))

  def handler(req, _) =
    read := req.data
  end

  harbor.http.register("/response_ended", port=3456, handler)
  resp = http.get("http://localhost:3456/response_ended")
  test.equal(resp.status_message, "OK")
  test.equal(resp.status_code, 200)
  try
    fn = read()
    fn(timeout=10.)
    test.fail()
  catch err : [error.http] do
    test.equal(
      err.message,
      "Response ended!"
    )
  end

  # Register output on the same port
  o = output.harbor(port=4455, mount="bla.wav", %wav, sine())
  o.on_start(synchronous=true, test.pass)
end

test.check(f)
