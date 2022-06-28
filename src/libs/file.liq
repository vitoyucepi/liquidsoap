# Read the content of a file. Returns a function of type `()->string`. File is
# done reading when function returns the empty string `""`.
# @category File
def file.read(fname) =
  fd = file.open(write=false, fname)
  is_done = ref(false)
  def read() =
    if !is_done then
      ""
    else
      s = fd.read()
      is_done := s == ""
      if !is_done then
        fd.close()
      end
      s
    end
  end
  read
end

let file.write = ()

# Stream data to a file. Returns a callback to write to the file. Execute
# with `null` or `""` to signify the end of the writing operation.
# @category File
# @param ~append Append data if file exists.
# @param ~perms Default file rights if created. Default: `0o644`.
# @param path Path to write to
def file.write.stream(~perms=0o644, ~append=false, path) =
  fd = file.open(write=true, append=append, perms=perms, path)
  def write(s) =
    s = s ?? ""
    if s == "" then fd.close() else
      fd.write(s)
    end
  end
  write
end

# Write data to a file.
# @category File
# @param ~data Data to write. If passing a callback `() -> string?`, the callback \
#              must return `null` or `""` when it has finished sending all its data.
# @param ~append Append data if file exists.
# @param ~perms Default file rights if created. Default: `0o644`.
# @param path Path to write to
def replaces file.write(~data, ~perms=0o644, ~append=false, path) =
  cb = file.write.stream(append=append, perms=perms, path)
  def rec write() =
    s = getter.get(data) ?? ""
    cb(s)
    if getter.is_constant(data) then
      cb("")
    elsif s != "" then
      write()
    end
  end
  write()
end
    
# Read the whole contents of a file.
# @category File
def file.contents(fname) =
  fn = file.read(fname)
  def rec f(cur) =
    s = fn()
    if s == "" then
      cur
    else
      f("#{cur}#{s}")
    end
  end
  f("")
end

# Get the list of lines of a file.
# @category File
def file.lines(fname)
  r/\n/.split(file.contents(fname))
end

# Iterate over the lines of a file.
# @category File
def file.lines.iterator(fname)
  list.iterator(file.lines(fname))
end

# Iterate over the contents of a file.
# @category File
def file.iterator(fname)
  f = file.read(fname)
  fun () -> begin
    s = f()
    (s=="")?null():s
  end
end

# Dummy implementation of file.mime
# @category File
def file.mime_default(_)
  ""
end
%ifdef file.mime
# Alias of file.mime (because it is available)
# @category File
def file.mime_default(fname)
  file.mime(fname)
end
%endif

# Generic mime test. First try to use file.mime if it exist.  Otherwise try to
# get the value using the file binary. Returns "" (empty string) if no value
# can be found.
# @category File
# @param file The file to test
def get_mime(fname) =
  def file_method(fname) =
    if process.test("which file") then
      list.hd(default="", process.read.lines("file -b --mime-type #{process.quote(fname)}"))
    else
      ""
    end
  end
  # First try mime method
  ret = file.mime_default(fname)
  if ret != "" then
    ret
  else
    # Now try file method
    file_method(fname)
  end
end

# Getter to the contents of a file.
# @category File
# @param fname Name of the file from which the contents should be taken.
def file.getter(fname)
  contents = ref("")
  def update()
    contents := file.contents(fname)
  end
  update()
  ignore(file.watch(fname, update))
  {!contents}
end

# Float getter from a file.
# @category File
# @param fname Name of the file from which the contents should be taken.
# @param ~default Default value when the file contains invalid data.
def file.getter.float(~default=0., fname)
  x = file.getter(fname)
  def f(x) = float_of_string(default=default, string.trim(x)) end
  getter.map.memoize(f, x)
end

%ifndef file.metadata.flac
let file.metadata.flac = fun (_) -> []
%endif

let file.metadata.flac.cover = ()

# Decode a flac-encoded cover metadata string
# @category String
def file.metadata.flac.cover.decode(s) =
  # See https://xiph.org/flac/format.html#metadata_block_picture
  i = ref(0)

  def read_int() =
    ret = string.binary.to_int(little_endian=false, string.sub(s, start=!i, length=4))
    i := !i + 4
    ret
  end

  def read_string(len) =
    ret = string.sub(s, start=!i, length=len)
    i := !i + len
    (ret:string)
  end

  pic_type = read_int()
  mime_len = read_int()
  mime = mime_len == 0 ? "image/" : read_string(mime_len)
  desc_len = read_int()
  desc = read_string(desc_len)
  width = read_int()
  height = read_int()
  color_depth = read_int()
  number_of_colors = read_int()
  number_of_colors = number_of_colors > 0 ? null(number_of_colors) : null()
  data_len = read_int()
  data = string.sub(s, start=!i, length=data_len)

  if data == "" then
    log.info("Failed to read cover metadata")
    null()
  else
    null(data.{
      picture_type=pic_type,
      mime=mime, description=desc,
      width=width, height=height,
      color_depth=color_depth,
      number_of_colors=number_of_colors
     })
  end
end

# Encode cover metadata for embedding with 
# flac files
# @category String
def file.metadata.flac.cover.encode(
        ~picture_type,
        ~mime, ~description="",
        ~width, ~height,
        ~color_depth, ~number_of_colors=null(),
        data) =
  def encode_string(s) =
    len = 1 + (string.length(s) / 8)
    str_len = string.binary.of_int(little_endian=false, pad=4, len)
    if string.length(str_len) > 4 then
      error.raise(error.invalid, "Data length too long for APIC format!")
    end
    pad = string.make(char_code=0, len * 8 - string.length(s))
    (str_len, "#{s}#{pad}") 
  end
  pic_type = string.binary.of_int(little_endian=false, pad=4, picture_type)
  let (mime_len, mime) = encode_string(mime)
  let (desc_len, description) = encode_string(description)
  width = string.binary.of_int(little_endian=false, pad=4, width)
  height = string.binary.of_int(little_endian=false, pad=4, height)
  color_depth = string.binary.of_int(little_endian=false, pad=4, color_depth)
  number_of_colors = string.binary.of_int(little_endian=false, pad=4, number_of_colors ?? 0)
  let (data_len, data) = encode_string(data)
  "#{pic_type}#{mime_len}#{mime}#{desc_len}#{description}#{width}#{height}#{color_depth}#{number_of_colors}#{data_len}#{data}"
end

%ifdef http.get.stream
# Download file using a regular http.get request. Returns `true` on success.
# @category File
# @param ~filename Downloaded filename.
# @param ~timeout Timeout in seconds
def file.download(~filename, ~timeout=5., url) =
  file_writer = file.write.stream(filename)

  response = http.get.stream(
    on_body_data=file_writer,
    timeout_ms=int_of_float(timeout * 1000.),
    url
  )

  response.status_code < 400
end
%endif

# Keep a record of played files. This is primarily useful to know when a song
# was last played and avoid repetitions.
# @flag extra
# @param ~duration Duration (in seconds) after which songs are forgotten. By default, songs are not forgotten which means that the playlog will contain all the songs ever played.
# @param ~hash Function to extract an identifier from the metadata. By default, the filename is used but we could return the artist to know when a song from a given artist was last played for instance.
# @param ~persistency Set a file name where the values are stored and loaded in case the script is restarted.
# @category Source / Track Processing
# @method add Record that file with given metadata has been played.
# @method last How long ago a file was played (in seconds), `infinity` is returned if the song has never been played.
def playlog(~duration=infinity, ~persistency=null(), ~hash=fun(m)->m["filename"])
  l = ref([])
  # Load from persistency file
  if null.defined(persistency) then
    if file.exists(null.get(persistency)) then
      let json.parse ( parsed : [(string * float)]? ) = file.contents(null.get(persistency))
      if null.defined(parsed) then
         l := null.get(parsed)
      end
    end
  end
  # Save into persistency file
  def save()
    if null.defined(persistency) then
      let json.stringify data = !l
      file.write(data=data, null.get(persistency))
    end
  end
  # Remove too old elements
  def prune()
    if duration != infinity then
      t = time()
      l := list.assoc.filter(fun(_, tf) -> t - tf <= duration, !l)
    end
  end
  # Add a new entry
  def add(m)
    prune()
    f = hash(m)
    l := (f, time()) :: !l
    save()
  end
  # Last time this entry was played
  def last(m)
    f = hash(m)
    time() - list.assoc(default = 0.-infinity, f, !l)
  end
  { add=add, last=last }
end