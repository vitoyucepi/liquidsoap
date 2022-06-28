# Enable telnet server.
# @category Interaction
# @param ~port Port on which we should listen.
def server.telnet(~port=1234) =
  settings.server.telnet.port.set(port)
  settings.server.telnet.set(true)
end

# Register a command that outputs the RMS of the returned source.
# @category Source / Visualization
# @param ~id Force the value of the source ID.
def server.rms(~id=null(),s) =
  let s = rms(id=id,s)
  id = source.id(s)
  def rms(_) =
    rms = s.rms()
    "#{rms}"
  end
  server.register(namespace="#{id}",
                  description="Return the current RMS of the source.",
                  usage="rms",
                  "rms",rms)
  s
end

# Register a server/telnet command to update a source's metadata. Returns a new
# source, which will receive the updated metadata. The command has the following
# format: insert key1="val1",key2="val2",...
# @category Source / Track Processing
# @param ~id Force the value of the source ID.
def server.insert_metadata(~id=null(),s) =
  s = insert_metadata(id=id,s)
  insert = s.insert_metadata
  def insert(s) =
    #TODO: we don't split as expected if one string contains a comma, but this
    #is difficult to achieve with regexps
    l = r/,/.split(s)
    def f(l,x) =
      def sub(s) = r/\"/.replace(fun (_) -> '"', s) end
      if x != "" then
        ret = r/([^=]+)\s*=\s*"((?:\"|[^"])*)"/.exec(x)
        if ret[1] != "" then
          list.append(l, [(ret[1], sub(ret[2]))])
        else
          l
        end
      else
        l
      end
    end
    meta = list.fold(f,[],l)
    if meta != [] then
      insert(meta)
      "Done"
    else
      "Syntax error or no metadata given. Use key1=\"val1\",key2=\"val2\",.."
    end
  end
  id = source.id(s)
  server.register(namespace="#{id}",
                  description="Insert a metadata chunk.",
                  usage="insert key1=\"val1\",key2=\"val2\",..",
                  "insert",insert)
  s
end

# Restart one server client waiting on the given condition.
# @param c condition
# @category Interaction
def server.signal(c) =
  signal = fst(snd(c))
  signal()
end

# Restart all server clients waiting on the given condition.
# @param c condition
# @category Interaction
def server.broadcast(x) =
  broadcast = snd(snd(x))
  broadcast()
end

# Start an interface for the "telnet" server over http.
# @category Liquidsoap
# @flag extra
# @param ~port Port of the server.
# @param ~uri URI of the server.
def server.harbor(~port=8000, ~uri="/telnet")
  def webpage(~protocol=_, ~data=_, ~headers=_, _)
    data="
<html>
  <head>
    <meta charset='utf-8'/>
    <title>Liquidsoap telnet server</title>
    <style>
      body {
          font-family: sans-serif;
      }
      h1 {
          text-align: center;
      }
      textarea {
          display: block;
          margin: 0 auto;
          color: lightgreen;
          background-color: black;
          padding: 1ex;
      }
    </style>
    <script>
      window.onload = function () {
        c = document.getElementById('console');

        function send() {
          var lines = c.value.substr(0, c.selectionStart).split('\\n');
          var line = lines[lines.length-1];
          var data = line;
          console.log('send ' + line);
          var xmlHttp = new XMLHttpRequest();
          xmlHttp.open('POST', '#{uri}');
          xmlHttp.onreadystatechange = function () {
            if(xmlHttp.readyState === XMLHttpRequest.DONE) {
              var status = xmlHttp.status;
              if (status === 0 || (status >= 200 && status < 400)) {
                c.value += xmlHttp.responseText + 'END\\n';
                c.scrollTop = c.scrollHeight;
              } else {
                console.log('Failed to send values.')
              }
            }
          }
          xmlHttp.send(data);
        }

        c.addEventListener('keypress', function(e) {if (e.which == 13) {send()}})
      }
    </script>
  </head>
  <body>
    <h1>Liquidsoap telnet server</h1>
    <textarea id='console' cols='80' rows='25'></textarea>
    <p style='text-align: center'>Type <code>help</code> if you are lost.</p>
  </body>
</html>
"
    http.response(data=data)
  end

  harbor.http.register(port=port, method="GET", uri, webpage)

  def setter(~protocol=_, ~data, ~headers=_, _)
    log.info("Executing command: #{data}")
    answer = server.execute(data)
    answer = string.concat(separator="\n", answer) ^ "\n"
    http.response(data=answer)
  end

  harbor.http.register(port=port, method="POST", uri, setter)
  log.important(label="server.harbor", "Website should be ready at <http://localhost:#{port}#{uri}>.")
end