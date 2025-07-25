# Create an audio source from the given track, with
# metadata and track marks from that same track.
# @category Source / Track processing
def source.audio(~id=null("source.audio"), audio) =
  source(
    id=id,
    {
      audio=audio,
      metadata=track.metadata(audio),
      track_marks=track.track_marks(audio)
    }
  )
end

# Create a video source from the given track, with
# metadata and track marks from that same track.
# @category Source / Track processing
def source.video(~id=null("source.video"), video) =
  source(
    id=id,
    {
      video=video,
      metadata=track.metadata(video),
      track_marks=track.track_marks(video)
    }
  )
end

# Remove duplicate metadata in a track.
# @param ~using Labels to use to compare the metadata. Defaults to all of them \
#               when `null`.
# @category Metadata
def track.metadata.deduplicate(
  ~id=null("track.metadata.deduplicate"),
  ~using=null,
  t
) =
  last_meta = ref([])

  def f(m) =
    m =
      if
        null.defined(using)
      then
        using = null.get(using)
        list.filter(fun (x) -> list.mem(fst(x), using), m)
      else
        m
      end

    if
      m == last_meta()
    then
      []
    else
      last_meta := m
      m
    end
  end

  track.metadata.map(
    id=id, insert_missing=false, update=false, strip=true, f, t
  )
end

# Remove duplicate metadata in a source.
# @category Metadata
# @param ~using Labels to use to compare the metadata. Defaults to all of them \
#               when `null`.
# @param ~id Source id
# @param s source
def metadata.deduplicate(~id=null("metadata.deduplicate"), ~using=null, s) =
  tracks = source.tracks(s)
  source(
    id=id,
    tracks.{metadata=track.metadata.deduplicate(using=using, tracks.metadata)}
  )
end

# Rewrite metadata on the fly using a function.
# @category Source / Track processing
# @argsof track.metadata.map
def metadata.map(
  ~id=null("metadata.map"),
  %argsof(track.metadata.map[!id]),
  f,
  (s:source)
) =
  tracks = source.tracks(s)
  source(
    id=id,
    tracks.{
      metadata=
        track.metadata.map(%argsof(track.metadata.map), f, tracks.metadata)
    }
  )
end

# Turn a source into an infaillible source by adding blank when the source is
# not available.
# @param s the source to turn infaillible
# @category Source / Track processing
def mksafe(~id="mksafe", s) =
  fallback(id=id, track_sensitive=false, [(s : source), blank(id="safe_blank")])
end

# Creates a source that plays only one track of the input source.
# @category Source / Track processing
# @param s The input source.
def once(~id=null("once"), s) =
  sequence(id=id, [(s : source), source.fail()])
end

# Skip track when detecting a blank.
# @category Source / Track processing
# @param ~id Force the value of the source ID.
# @param ~threshold Power in decibels under which the stream is considered silent.
# @param ~max_blank Maximum silence length allowed, in seconds.
# @param ~min_noise Minimum duration of noise required to end silence, in seconds.
# @param ~track_sensitive Reset blank counter at each track.
def blank.skip(
  ~id=null("blank.skip"),
  ~threshold=-40.,
  ~max_blank=20.,
  ~min_noise=0.,
  ~track_sensitive=true,
  s
) =
  s' = blank.detect(
    id=id,
    threshold=threshold,
    max_blank=max_blank,
    min_noise=min_noise,
    track_sensitive=track_sensitive,
    s
  )
  s'.on_blank(source.methods(s).skip)
  s'
end

# Run a function regularly. This is similar to `thread.run` but based on a
# source internal time instead of the computer's time.
# @category Source / Track processing
# @param s Source whose time is taken as reference.
# @param ~delay Time to wait before the first run (in seconds).
# @param ~every How often to run the function (in seconds). The function is run once if `null`.
# @param f Function to run.
def source.run(s, ~delay=0., ~every=null, f) =
  next = ref(delay)

  def check() =
    if
      source.time(s) >= next()
    then
      null.case(
        every, {next := infinity}, fun (every) -> next := next() + every
      )

      f()
    end
  end

  source.methods(s).on_frame(check)
  s
end

# Append an extra track to every track. Set the metadata ‘liq_append’ to
# `false` to inhibit appending on one track.
# @category Source / Track processing
# @param f Given the metadata, build the source producing the track to append. The function can return `null` to prevent appending a new track.
# @param ~insert_missing Treat track beginnings without metadata as having empty one.
# @param ~merge Merge the track with its appended track.
# @flag extra
def append(~id=null("append"), ~insert_missing=true, ~merge=false, s, f) =
  last_meta = ref(null)
  pending = ref(null)

  def next() =
    p = pending()
    pending := null
    last_meta := null

    if null.defined(p) then null.get(p) else (s : source) end
  end

  d =
    source.dynamic(
      track_sensitive=true, merge={merge and null.defined(pending)}, next
    )

  def f(m) =
    if
      d.current_source() == (s : source)
    then
      if
        m["liq_append"] == "false"
      then
        last_meta := null
        pending := null
      elsif
        last_meta() != m
      then
        last_meta := m
        s = f(m)
        d.prepare(s)
        pending := s
      end
    end
  end

  if insert_missing then d.on_track(synchronous=true, f) end
  d.on_metadata(synchronous=true, f)

  s = fallback(id=id, track_sensitive=false, [d, s])
  s.{
    pending=
      # Return the pending source
      fun () -> pending(),
    set_pending=
      # Set the pending source
      fun (s) -> pending.set(s),
    cancel_pending=
      # Cancel any pending appended source.
      fun () -> pending.set(null),
    skip=
      # Skip the current track. Pending appended source are cancelled by default. Pass `cancel_pending=false` to keep it.
      fun (~cancel_pending=true) ->
        begin
          if cancel_pending then pending.set(null) end
          s.skip()
        end
  }
end

# Prepend an extra track before every track. Set the metadata `liq_prepend` to
# `false` to inhibit prepending on one track.
# @category Source / Track processing
# @param f Given the metadata, build the source producing the track to append. The function can return `null` to prevent any track prepend.
# @param ~merge Merge the track with its appended track.
# @flag extra
def prepend(~id=null("prepend"), ~merge=false, s, f) =
  last_meta = ref(null)

  def on_meta(m) =
    if
      m["liq_prepend"] == "false"
    then
      last_meta := null
    elsif last_meta() != m then last_meta := m
    end
  end

  s.on_track(
    synchronous=true, fun (m) -> m == [] ? last_meta := null : on_meta(m)
  )
  s.on_metadata(synchronous=true, on_meta)

  def next() =
    if
      null.defined(last_meta)
    then
      m = last_meta()
      last_meta := null
      if
        null.defined(m)
      then
        m = null.get(m)
        p = (f(m) : source?)
        if
          null.defined(p)
        then
          sequence(merge=merge, [null.get(p), s])
        else
          s
        end
      else
        s
      end
    else
      s
    end
  end

  d = source.dynamic(track_sensitive=true, next)
  fallback(id=id, track_sensitive=true, [d, s])
end
