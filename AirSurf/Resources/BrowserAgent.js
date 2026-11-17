// Browser page agent.
//
// Injected at document start into every frame of every page. It does three jobs:
//   1. Notices video streams (HLS playlists, direct video files) as the page loads them,
//      so the native player can take over.
//   2. Executes pointer commands (hover / click / context / text entry / scroll) at a
//      point, relaying them into cross-origin iframes with postMessage.
//   3. Pauses page media on request.
//
// __TVB_TOKEN__ is replaced with a per-launch random string before injection.
(function () {
  'use strict';
  if (window.__tvbAgentInstalled) { return; }
  try {
    Object.defineProperty(window, '__tvbAgentInstalled', { value: true, enumerable: false });
  } catch (e) { window.__tvbAgentInstalled = true; }

  var TOKEN = '__TVB_TOKEN__';
  var isTop = false;
  try { isTop = (window === window.top); } catch (e) {}

  var bridge = null;
  try { bridge = window.webkit.messageHandlers.tvb; } catch (e) {}

  function post(message) {
    if (!bridge) { return; }
    try {
      message.frameURL = String(location.href);
      message.top = isTop;
      bridge.postMessage(message);
    } catch (e) {}
  }

  function abs(url) {
    if (url === undefined || url === null) { return ''; }
    try { return String(new URL(String(url), document.baseURI || location.href)); } catch (e) { return String(url); }
  }

  // ---------------------------------------------------------------- media sniffing

  var media = {};       // url -> candidate
  var mediaOrder = [];

  function classify(url) {
    var lower = String(url || '').toLowerCase().split('#')[0];
    if (!/^https?:/.test(lower)) { return null; }
    var path = lower.split('?')[0];
    if (/\.m3u8$/.test(path) || /[.\/=:]m3u8([\/?&:]|$)/.test(lower)) { return 'hls'; }
    if (/\.mpd$/.test(path)) { return 'dash'; }
    if (/\.(mp4|m4v|mov)$/.test(path)) { return 'file'; }
    if (/\.webm$/.test(path)) { return 'webm'; }
    return null;
  }

  function note(url, kind, via, extra) {
    url = abs(url);
    if (!url || !kind) { return; }
    var entry = media[url];
    var changed = false;
    if (!entry) {
      entry = media[url] = { url: url, kind: kind, via: via, time: Date.now() };
      mediaOrder.push(url);
      if (mediaOrder.length > 40) { delete media[mediaOrder.shift()]; }
      changed = true;
    }
    if (extra) {
      for (var key in extra) {
        if (extra[key] !== undefined && entry[key] !== extra[key]) { entry[key] = extra[key]; changed = true; }
      }
    }
    if (changed) {
      post({ t: 'media', media: entry, title: String(document.title || '') });
    }
  }

  function inspectPlaylist(url, contentType, text) {
    var looksLikeHLS = contentType.indexOf('mpegurl') !== -1;
    var head = text ? text.slice(0, 16) : '';
    if (!looksLikeHLS && head.indexOf('#EXTM3U') === -1) { return; }
    var extra = {};
    if (text) {
      extra.master = text.indexOf('#EXT-X-STREAM-INF') !== -1;
      extra.playlist = text.indexOf('#EXTINF') !== -1;
      extra.live = extra.playlist && text.indexOf('#EXT-X-ENDLIST') === -1;
    }
    note(url, 'hls', 'response', extra);
    if (extra.master) { bridgeNoteMaster(abs(url)); }
  }

  // ---------------------------------------------------------------- subtitle files
  //
  // Many players download subtitles as a separate WebVTT or SRT file and draw them over the
  // video themselves. They are not part of the stream, so the Apple TV player only gets them
  // when they are handed over with it.

  var subtitleFiles = [];

  function subtitleFormat(url, contentType, text) {
    var path = String(url || '').toLowerCase().split('#')[0].split('?')[0];
    var head = text ? String(text).replace(/^\uFEFF/, '').slice(0, 80) : '';
    if (/^WEBVTT/.test(head)) { return 'vtt'; }
    if (/^\s*\d+\s*\r?\n\s*\d+:\d\d:\d\d[,.]\d+\s*-->/.test(head)) { return 'srt'; }
    if (head && head.charAt(0) === '#') { return null; }
    if (/\.vtt$/.test(path) || contentType.indexOf('vtt') !== -1) { return 'vtt'; }
    if (/\.srt$/.test(path) || contentType.indexOf('subrip') !== -1) { return 'srt'; }
    return null;
  }

  /// First cue's text, to recognise the file among the element's text tracks.
  function firstCueText(text) {
    var match = /-->[^\n]*\n([\s\S]*?)(\r?\n\s*\r?\n|$)/.exec(String(text || ''));
    return match ? match[1].replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim().slice(0, 80) : '';
  }

  function noteSubtitleFile(url, format, text) {
    url = abs(url);
    if (!/^https?:/i.test(url)) { return; }
    // Segments of a subtitle track inside an HLS stream are WebVTT too; the Apple TV player
    // fetches those itself.
    if (text && /X-TIMESTAMP-MAP/.test(String(text).slice(0, 300))) { return; }
    for (var i = 0; i < subtitleFiles.length; i++) {
      if (subtitleFiles[i].url === url) { return; }
    }
    subtitleFiles.push({ url: url, format: format, sample: firstCueText(text), time: Date.now() });
    if (subtitleFiles.length > 24) { subtitleFiles.shift(); }
  }

  function decodeBuffer(buffer) {
    try { return new TextDecoder('utf-8').decode(new Uint8Array(buffer, 0, Math.min(buffer.byteLength, 65536))); } catch (e) { return null; }
  }

  try {
    var XHR = window.XMLHttpRequest;
    if (XHR && XHR.prototype && XHR.prototype.open) {
      var originalOpen = XHR.prototype.open;
      var onLoad = function () {
        try {
          var url = this.responseURL || this.__tvbURL;
          var kind = classify(url);
          var contentType = String(this.getResponseHeader('content-type') || '').toLowerCase();
          var text = null;
          if (this.responseType === '' || this.responseType === 'text') {
            text = this.responseText;
          } else if (this.responseType === 'arraybuffer' && this.response &&
                     (kind === 'hls' || contentType.indexOf('mpegurl') !== -1 || subtitleFormat(url, contentType, null))) {
            text = decodeBuffer(this.response);
          }
          var subtitles = subtitleFormat(url, contentType, text);
          if (subtitles) { noteSubtitleFile(url, subtitles, text); }
          if (kind === 'hls' || contentType.indexOf('mpegurl') !== -1 ||
              (text && text.charCodeAt(0) === 35 && text.slice(0, 7) === '#EXTM3U')) {
            inspectPlaylist(url, contentType, text);
          }
        } catch (e) {}
      };
      XHR.prototype.open = function (method, url) {
        try {
          this.__tvbURL = abs(url);
          var kind = classify(this.__tvbURL);
          if (kind === 'hls' || kind === 'dash') { note(this.__tvbURL, kind, 'xhr'); }
          this.addEventListener('load', onLoad);
        } catch (e) {}
        return originalOpen.apply(this, arguments);
      };
    }
  } catch (e) {}

  try {
    var originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
      window.fetch = function (input) {
        var url = '';
        try {
          url = abs(typeof input === 'string' ? input : (input && input.url));
          var kind = classify(url);
          if (kind === 'hls' || kind === 'dash') { note(url, kind, 'fetch'); }
        } catch (e) {}
        var promise = originalFetch.apply(this, arguments);
        try {
          promise.then(function (response) {
            try {
              var finalURL = response.url || url;
              var contentType = String(response.headers.get('content-type') || '').toLowerCase();
              if (contentType.indexOf('mpegurl') !== -1 || classify(finalURL) === 'hls') {
                response.clone().text().then(function (text) {
                  inspectPlaylist(finalURL, contentType, text);
                }).catch(function () {});
              } else if (subtitleFormat(finalURL, contentType, null)) {
                response.clone().text().then(function (text) {
                  var format = subtitleFormat(finalURL, contentType, text);
                  if (format) { noteSubtitleFile(finalURL, format, text); }
                }).catch(function () {});
              }
            } catch (e) {}
          }).catch(function () {});
        } catch (e) {}
        return promise;
      };
    }
  } catch (e) {}

  // ---------------------------------------------------------------- Media Source bridge
  //
  // WebKit on tvOS has no Media Source Extensions. Players built only on hls.js, with no
  // native HLS fallback, stop with "browser not supported" or "update iOS". In those frames
  // hls.js gets a stand-in MediaSource that accepts its data and drops it, while the <video>
  // element plays the same HLS stream natively. The player's own menus keep working:
  // quality, voice-over and subtitle choices are applied to the native stream where
  // possible and travel with the fullscreen request to the Apple TV player.
  //
  // Only frames that need it get the stand-in: known MSE-only player hosts, and any frame
  // whose hls.js player reported itself unsupported (it is reloaded once with the bridge).

  var BRIDGE_FLAG = 'tvb.mediaSourceBridge';
  var KNOWN_MSE_ONLY_HOSTS = /(^|\.)stloadi\.[a-z]+$/i;
  var bridgeActive = false;
  var hlsInstances = [];
  var lastMasterURL = '';
  var fakeSources = {};
  var fakeSourceCount = 0;
  var mediaSrcDescriptor = null;

  function log(text) { post({ t: 'log', msg: String(text) }); }

  function bridgeFlagStored() {
    try { return window.sessionStorage.getItem(BRIDGE_FLAG) === '1'; } catch (e) { return false; }
  }

  function mediaSourceMissing() {
    return !window.MediaSource && !window.ManagedMediaSource && !window.WebKitMediaSource;
  }

  function setNativeSrc(media, url) {
    if (mediaSrcDescriptor && mediaSrcDescriptor.set) { mediaSrcDescriptor.set.call(media, url); }
  }

  function hlsForMedia(media) {
    for (var i = hlsInstances.length - 1; i >= 0; i--) {
      try { if (hlsInstances[i].media === media) { return hlsInstances[i]; } } catch (e) {}
    }
    return null;
  }

  function trackHls(hls) {
    if (hlsInstances.indexOf(hls) === -1) {
      hlsInstances.push(hls);
      if (hlsInstances.length > 8) { hlsInstances.shift(); }
    }
  }

  function levelURL(level) {
    var url = level && (level.uri || level.url);
    if (Array.isArray(url)) { url = url[level.urlId || 0]; }
    return url ? abs(url) : '';
  }

  /// Points the real element at `url`, keeping position and play state.
  function switchNativeSource(media, url) {
    if (!url || media.__tvbNativeURL === url) { return; }
    var hadSource = !!media.__tvbNativeURL;
    // Same stream in another quality: keep the place. A new stream (another episode) starts
    // where its player asks via hls.startLoad(position), if it asks.
    var time = hadSource ? media.currentTime : (media.__tvbPendingSeek || 0);
    var playing = hadSource ? (!media.paused && !media.ended) : !!media.__tvbPendingPlay;
    media.__tvbPendingSeek = 0;
    media.__tvbPendingPlay = false;
    media.__tvbNativeURL = url;
    setNativeSrc(media, url);
    log('bridge: native source ' + url);
    if (!(time > 0) && !playing) { return; }
    var restore = function () {
      media.removeEventListener('loadedmetadata', restore);
      try { if (time > 0) { media.currentTime = time; } } catch (e) {}
      if (playing) { try { var p = media.play(); if (p && p.catch) { p.catch(function () {}); } } catch (e) {} }
    };
    media.addEventListener('loadedmetadata', restore);
  }

  function syncNativeSource(media) {
    if (!media || !media.__tvbSource) { return; }
    var hls = hlsForMedia(media);
    // After hls.js has read the playlist, not alongside it: one request at a time, as in
    // any browser. (Its level list is emptied while a new playlist loads.)
    if (hls && !(hls.levels && hls.levels.length)) { return; }
    var url = hls ? (hls.url ? abs(hls.url) : '') : lastMasterURL;
    if (hls && typeof hls.__tvbLevel === 'number' && hls.__tvbLevel >= 0 && !(hls.audioTracks && hls.audioTracks.length)) {
      url = levelURL(hls.levels && hls.levels[hls.__tvbLevel]) || url;
    }
    switchNativeSource(media, url);
  }

  function bridgeNoteMaster(url) {
    if (!bridgeActive) { return; }
    lastMasterURL = url;
    var videos = document.querySelectorAll('video, audio');
    for (var i = 0; i < videos.length; i++) {
      if (videos[i].__tvbSource && !videos[i].__tvbNativeURL) { syncNativeSource(videos[i]); }
    }
  }

  function chooseLevel(hls, index) {
    hls.__tvbLevel = Number(index);
    var media = hls.media;
    if (!media || !media.__tvbSource) { return; }
    // A variant playlist alone has no sound when the voice-overs are separate renditions;
    // then the in-page picture stays adaptive and the choice only goes to the Apple TV player.
    if (hls.audioTracks && hls.audioTracks.length) { return; }
    var level = hls.__tvbLevel >= 0 && hls.levels ? hls.levels[hls.__tvbLevel] : null;
    switchNativeSource(media, (level && levelURL(level)) || abs(hls.url));
  }

  function chooseAudioTrack(hls, index) {
    hls.__tvbAudio = Number(index);
    var media = hls.media;
    var wanted = hls.audioTracks && hls.audioTracks[index];
    var list = media && media.__tvbSource ? media.audioTracks : null;
    if (!wanted || !list || !list.length) { return; }
    var match = -1, i;
    for (i = 0; i < list.length && match < 0; i++) {
      if (wanted.name && list[i].label === wanted.name) { match = i; }
    }
    for (i = 0; i < list.length && match < 0; i++) {
      if (wanted.lang && String(list[i].language).toLowerCase() === String(wanted.lang).toLowerCase()) { match = i; }
    }
    if (match < 0 && list.length === hls.audioTracks.length) { match = Number(index); }
    for (i = 0; i < list.length && match >= 0; i++) { list[i].enabled = (i === match); }
  }

  /// What the user picked in the page's player, for the Apple TV player.
  function hlsChoices(hls) {
    var out = { master: abs(hls.url) };
    try {
      var levelIndex = typeof hls.__tvbLevel === 'number' ? hls.__tvbLevel
                       : (hls.autoLevelEnabled === false ? hls.currentLevel : -1);
      var level = levelIndex >= 0 && hls.levels ? hls.levels[levelIndex] : null;
      if (level) {
        var top = 0;
        for (var i = 0; i < hls.levels.length; i++) { top = Math.max(top, hls.levels[i].bitrate || 0); }
        out.level = { width: level.width || 0, height: level.height || 0,
                      bitrate: level.bitrate || level.maxBitrate || 0, name: String(level.name || ''),
                      highest: (level.bitrate || 0) >= top };
      }
      var audio = hls.audioTracks && hls.audioTrack >= 0 ? hls.audioTracks[hls.audioTrack] : null;
      if (audio) {
        out.audio = { name: String(audio.name || ''), lang: String(audio.lang || ''),
                      index: hls.audioTrack, count: hls.audioTracks.length };
      }
      var subtitle = hls.subtitleTracks && hls.subtitleTrack >= 0 ? hls.subtitleTracks[hls.subtitleTrack] : null;
      if (subtitle && hls.subtitleDisplay !== false) {
        out.subtitle = { name: String(subtitle.name || ''), lang: String(subtitle.lang || '') };
      }
    } catch (e) {}
    return out;
  }

  function cueText(cue) {
    return String((cue && cue.text) || '').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim().slice(0, 80);
  }

  /// Players that draw cues themselves keep their track "hidden" and mark the player instead.
  function captionsLookOn(video) {
    var element = video;
    for (var depth = 0; element && element.nodeType === 1 && depth < 8; depth++) {
      var classes = (typeof element.className === 'string') ? element.className : '';
      if (/(captions?|subtitles?|cc)[-_]+(active|enabled|on|visible)\b/i.test(classes)) { return true; }
      element = element.parentElement;
    }
    return false;
  }

  /// Subtitle files that belong to `video` but are not part of its stream, with their
  /// labels and which one is on. Empty when the stream carries its own subtitle tracks.
  function pageSubtitles(video, hls) {
    if (hls && hls.subtitleTracks && hls.subtitleTracks.length) { return []; }
    var entries = [];
    var add = function (url, format, label, lang, sample, track) {
      url = abs(url);
      for (var i = 0; i < entries.length; i++) { if (entries[i].url === url) { return entries[i]; } }
      var entry = { url: url, format: format, label: String(label || ''), lang: String(lang || ''),
                    sample: sample || '', showing: false, track: track || null };
      entries.push(entry);
      return entry;
    };
    var elements = video.querySelectorAll('track[src]');
    for (var e = 0; e < elements.length; e++) {
      var src = elements[e].src || elements[e].getAttribute('src');
      if (/^https?:/i.test(abs(src))) {
        add(src, subtitleFormat(src, '', null) || 'vtt', elements[e].label, elements[e].srclang, '', elements[e].track);
      }
    }
    for (var f = 0; f < subtitleFiles.length; f++) {
      add(subtitleFiles[f].url, subtitleFiles[f].format, '', '', subtitleFiles[f].sample, null);
    }
    var tracks = video.textTracks || [];
    // A "hidden" track counts as on only for players that draw cues themselves and leave no
    // track "showing"; otherwise hidden ones are helpers such as forced-only subtitles.
    var anyShowing = false;
    for (var s = 0; s < tracks.length; s++) { if (tracks[s].mode === 'showing') { anyShowing = true; } }
    var drawnByPlayer = !anyShowing && captionsLookOn(video);
    for (var t = 0; t < tracks.length; t++) {
      var track = tracks[t];
      if (track.kind !== 'subtitles' && track.kind !== 'captions') { continue; }
      var first = track.cues && track.cues.length ? cueText(track.cues[0]) : '';
      var match = null;
      for (var m = 0; m < entries.length && !match; m++) {
        if (entries[m].track === track || (first && entries[m].sample === first)) { match = entries[m]; }
      }
      if (!match) { continue; }
      match.label = match.label || String(track.label || '');
      match.lang = match.lang || String(track.language || '');
      if (track.mode === 'showing' || (track.mode === 'hidden' && drawnByPlayer)) { match.showing = true; }
      // Cues already loaded in the page go along as text: subtitle links on these sites
      // tend to work only for the page that was given them.
      if (track.cues && track.cues.length) { match.vtt = cuesToWebVTT(track.cues); }
    }
    // One file and the player says captions are on: that is the one, even without a match.
    if (entries.length === 1 && drawnByPlayer) { entries[0].showing = true; }
    return entries.map(function (entry) {
      var out = { url: entry.url, format: entry.format, label: entry.label, lang: entry.lang, showing: entry.showing };
      if (entry.vtt) { out.vtt = entry.vtt; }
      return out;
    });
  }

  function webVTTTime(seconds) {
    var ms = Math.max(0, Math.round(seconds * 1000));
    var pad = function (n, width) { n = String(n); while (n.length < width) { n = '0' + n; } return n; };
    return pad(Math.floor(ms / 3600000), 2) + ':' + pad(Math.floor(ms / 60000) % 60, 2) + ':' +
           pad(Math.floor(ms / 1000) % 60, 2) + '.' + pad(ms % 1000, 3);
  }

  function cuesToWebVTT(cues) {
    var out = ['WEBVTT', ''];
    for (var i = 0; i < cues.length; i++) {
      var text = String(cues[i].text || '').replace(/-->/g, '->').replace(/\r?\n\s*\r?\n/g, '\n').trim();
      if (!text) { continue; }
      out.push(webVTTTime(cues[i].startTime) + ' --> ' + webVTTTime(cues[i].endTime));
      out.push(text);
      out.push('');
    }
    return out.join('\n');
  }

  function describeSubtitleState(video) {
    var parts = [];
    var tracks = video.textTracks || [];
    for (var t = 0; t < tracks.length; t++) {
      parts.push('track[' + tracks[t].kind + ' "' + tracks[t].label + '" ' + tracks[t].language + ' ' + tracks[t].mode +
                 ' cues=' + (tracks[t].cues ? tracks[t].cues.length : '-') + ']');
    }
    var elements = video.querySelectorAll('track');
    parts.push('elements=' + elements.length);
    for (var e = 0; e < Math.min(elements.length, 3); e++) {
      parts.push('src[' + String(elements[e].getAttribute('src') || '').slice(0, 90) + ']');
    }
    for (var f = 0; f < subtitleFiles.length; f++) {
      parts.push('file[' + subtitleFiles[f].format + ' ' + subtitleFiles[f].url.split('?')[0].slice(-60) + ' "' + subtitleFiles[f].sample + '"]');
    }
    parts.push('drawnByPlayer=' + captionsLookOn(video));
    return parts.join(' ');
  }

  function wrapMethod(proto, name, after) {
    var original = proto[name];
    if (typeof original !== 'function') { return; }
    proto[name] = function () {
      // Tracked first: attachMedia sets the element's src before it returns.
      trackHls(this);
      var result = original.apply(this, arguments);
      try { after.apply(this, arguments); } catch (e) {}
      return result;
    };
  }

  function wrapSetter(proto, name, onSet) {
    var descriptor = Object.getOwnPropertyDescriptor(proto, name);
    if (!descriptor || !descriptor.set || !descriptor.configurable) { return; }
    Object.defineProperty(proto, name, {
      configurable: true, enumerable: descriptor.enumerable, get: descriptor.get,
      set: function (value) {
        descriptor.set.call(this, value);
        try { onSet(this, value); } catch (e) {}
      }
    });
  }

  function patchHls(Hls) {
    if (!Hls || !Hls.prototype || Hls.prototype.__tvbPatched) { return; }
    var proto = Hls.prototype;
    try { Object.defineProperty(proto, '__tvbPatched', { value: true }); } catch (e) { return; }
    var listen = function (instance) {
      if (instance.__tvbListening || typeof instance.on !== 'function' || !Hls.Events) { return; }
      instance.__tvbListening = true;
      instance.on(Hls.Events.MANIFEST_PARSED, function () { syncNativeSource(instance.media); });
      instance.on(Hls.Events.ERROR, function (event, data) {
        log('bridge: hls.js error ' + (data && data.type) + '/' + (data && data.details) +
            (data && data.response ? ' http ' + data.response.code : '') + (data && data.fatal ? ' fatal' : ''));
      });
    };
    wrapMethod(proto, 'attachMedia', function () { listen(this); syncNativeSource(this.media); });
    wrapMethod(proto, 'loadSource', function () { listen(this); syncNativeSource(this.media); });
    // Players restore the position after a quality or voice-over switch with startLoad(t);
    // the element playing natively has to be told separately.
    wrapMethod(proto, 'startLoad', function (position) {
      var media = this.media;
      if (!media || !media.__tvbSource || !(position > 0)) { return; }
      if (media.__tvbNativeURL && media.readyState >= 1) {
        try { media.currentTime = position; } catch (e) {}
      } else {
        media.__tvbPendingSeek = position;
      }
    });
    ['currentLevel', 'nextLevel', 'loadLevel'].forEach(function (name) { wrapSetter(proto, name, chooseLevel); });
    wrapSetter(proto, 'audioTrack', chooseAudioTrack);
    log('bridge: hls.js ' + (Hls.version || '') + ' hooked');
  }

  function FakeTimeRanges(ranges) {
    this.length = ranges.length;
    this.start = function (i) { if (i >= ranges.length) { throw new RangeError('index'); } return ranges[i][0]; };
    this.end = function (i) { if (i >= ranges.length) { throw new RangeError('index'); } return ranges[i][1]; };
  }
  // Reporting everything as buffered stops hls.js after its first segment: the element
  // fetches the stream itself.
  var EVERYTHING_BUFFERED = new FakeTimeRanges([[0, 1e7]]);

  function fireLater(target, type, before) {
    setTimeout(function () {
      if (before) { before(); }
      var event = new Event(type);
      try { target.dispatchEvent(event); } catch (e) {}
      var handler = target['on' + type];
      if (typeof handler === 'function') { try { handler.call(target, event); } catch (e) {} }
    }, 0);
  }

  var codecProbe = null;
  function bridgeCanPlay(type) {
    var lower = String(type || '').toLowerCase();
    try {
      codecProbe = codecProbe || document.createElement('video');
      if (codecProbe.canPlayType(lower)) { return true; }
    } catch (e) {}
    return /^(video|audio)\/mp4/.test(lower) && !/(av01|vp0?9|vp8|opus|vorbis|flac)/.test(lower);
  }

  function installMediaSourceBridge() {
    if (bridgeActive || !window.HTMLMediaElement || typeof EventTarget !== 'function') { return; }
    mediaSrcDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
    if (!mediaSrcDescriptor || !mediaSrcDescriptor.set) { return; }
    bridgeActive = true;

    class SourceBuffer extends EventTarget {
      constructor(type) {
        super();
        this.type = type; this.mode = 'segments'; this.updating = false;
        this.timestampOffset = 0; this.appendWindowStart = 0; this.appendWindowEnd = Infinity;
      }
      get buffered() { return EVERYTHING_BUFFERED; }
      appendBuffer() { this._update(); }
      remove() { this._update(); }
      abort() { this.updating = false; }
      changeType(type) { this.type = type; }
      _update() {
        var self = this;
        self.updating = true;
        fireLater(self, 'updatestart');
        fireLater(self, 'update', function () { self.updating = false; });
        fireLater(self, 'updateend');
      }
    }

    class MediaSource extends EventTarget {
      constructor() {
        super();
        this.readyState = 'closed'; this.duration = NaN;
        this.sourceBuffers = []; this.activeSourceBuffers = this.sourceBuffers;
      }
      static isTypeSupported(type) { return bridgeCanPlay(type); }
      addSourceBuffer(type) { var buffer = new SourceBuffer(type); this.sourceBuffers.push(buffer); return buffer; }
      removeSourceBuffer(buffer) { var i = this.sourceBuffers.indexOf(buffer); if (i >= 0) { this.sourceBuffers.splice(i, 1); } }
      endOfStream() { var self = this; fireLater(self, 'sourceended', function () { self.readyState = 'ended'; }); }
      setLiveSeekableRange() {}
      clearLiveSeekableRange() {}
    }

    function attachFake(media, source, url) {
      media.__tvbFakeURL = url;
      media.__tvbSource = source;
      if (source.readyState === 'closed') {
        fireLater(source, 'sourceopen', function () { source.readyState = 'open'; });
      }
      syncNativeSource(media);
    }

    function detachFake(media) {
      var source = media.__tvbSource;
      if (source) { fireLater(source, 'sourceclose', function () { source.readyState = 'closed'; }); }
      media.__tvbFakeURL = null; media.__tvbSource = null; media.__tvbNativeURL = null;
      media.__tvbPendingSeek = 0; media.__tvbPendingPlay = false;
    }

    var define = function (name, value) {
      try { Object.defineProperty(window, name, { configurable: true, writable: true, value: value }); } catch (e) { window[name] = value; }
    };
    define('MediaSource', MediaSource);
    define('SourceBuffer', SourceBuffer);

    var createObjectURL = URL.createObjectURL, revokeObjectURL = URL.revokeObjectURL;
    URL.createObjectURL = function (object) {
      if (object instanceof MediaSource) {
        var url = 'blob:' + location.origin + '/tvb-media-source-' + (++fakeSourceCount);
        fakeSources[url] = object;
        return url;
      }
      return createObjectURL.apply(URL, arguments);
    };
    URL.revokeObjectURL = function (url) {
      if (fakeSources[url]) { delete fakeSources[url]; return; }
      return revokeObjectURL.apply(URL, arguments);
    };

    Object.defineProperty(HTMLMediaElement.prototype, 'src', {
      configurable: true, enumerable: true,
      get: function () { return this.__tvbFakeURL || mediaSrcDescriptor.get.call(this); },
      set: function (value) {
        var source = fakeSources[String(value)];
        if (source) { attachFake(this, source, String(value)); return; }
        if (this.__tvbSource) { detachFake(this); }
        mediaSrcDescriptor.set.call(this, value);
      }
    });
    // Between a stream switch and its playlist arriving the element has no source yet; a
    // seek or play() asked for in that moment is kept for when it has one.
    var timeDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'currentTime');
    if (timeDescriptor && timeDescriptor.set) {
      Object.defineProperty(HTMLMediaElement.prototype, 'currentTime', {
        configurable: true, enumerable: true, get: timeDescriptor.get,
        set: function (value) {
          if (this.__tvbSource && !this.__tvbNativeURL) { this.__tvbPendingSeek = Number(value) || 0; }
          timeDescriptor.set.call(this, value);
        }
      });
    }
    var play = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function () {
      if (this.__tvbSource && !this.__tvbNativeURL) {
        this.__tvbPendingPlay = true;
        return Promise.resolve();
      }
      return play.apply(this, arguments);
    };
    var setAttribute = Element.prototype.setAttribute, removeAttribute = Element.prototype.removeAttribute;
    HTMLMediaElement.prototype.setAttribute = function (name, value) {
      var source = String(name).toLowerCase() === 'src' ? fakeSources[String(value)] : null;
      if (source) { attachFake(this, source, String(value)); return; }
      return setAttribute.apply(this, arguments);
    };
    HTMLMediaElement.prototype.removeAttribute = function (name) {
      if (String(name).toLowerCase() === 'src' && this.__tvbSource) { detachFake(this); }
      return removeAttribute.apply(this, arguments);
    };

    var hls = window.Hls;
    if (hls) { patchHls(hls); }
    try {
      Object.defineProperty(window, 'Hls', {
        configurable: true, enumerable: true,
        get: function () { return hls; },
        set: function (value) { hls = value; patchHls(value); }
      });
    } catch (e) {}
    document.addEventListener('error', function (event) {
      var media = event.target;
      if (media && media.__tvbNativeURL) {
        log('bridge: native playback error ' + (media.error ? media.error.code + ' ' + (media.error.message || '') : '?') +
            ' for ' + String(media.__tvbNativeURL).split('/')[2]);
      }
    }, true);
    document.addEventListener('loadedmetadata', function (event) {
      var media = event.target;
      if (media && media.__tvbNativeURL) {
        log('bridge: native stream ready ' + media.videoWidth + 'x' + media.videoHeight + ', ' + Math.round(media.duration) + ' s, ' +
            (media.audioTracks ? media.audioTracks.length : 0) + ' audio tracks');
      }
    }, true);
    log('bridge: Media Source stand-in installed for ' + location.host);
  }

  function watchForUnsupportedPlayer() {
    var checks = 0;
    var timer = setInterval(function () {
      if (++checks > 30) { clearInterval(timer); return; }
      var Hls = window.Hls;
      if (!Hls || typeof Hls.isSupported !== 'function') { return; }
      if (Hls.isSupported()) { clearInterval(timer); return; }
      var notices = document.querySelectorAll('[class*="unsupported"], [class*="not-supported"], [class*="not_supported"]');
      for (var i = 0; i < notices.length; i++) {
        var style = window.getComputedStyle(notices[i]);
        if (notices[i].getClientRects().length && style.display !== 'none' && style.visibility !== 'hidden') {
          clearInterval(timer);
          try { window.sessionStorage.setItem(BRIDGE_FLAG, '1'); } catch (e) { return; }
          log('bridge: ' + location.host + ' reports an unsupported browser; reloading with the stand-in');
          location.reload();
          return;
        }
      }
    }, 500);
  }

  try {
    if (mediaSourceMissing()) {
      if (KNOWN_MSE_ONLY_HOSTS.test(location.hostname) || bridgeFlagStored()) {
        installMediaSourceBridge();
      } else {
        watchForUnsupportedPlayer();
      }
    }
  } catch (e) {}

  function videoMetrics(video) {
    var rect = video.getBoundingClientRect();
    var duration = video.duration;
    return {
      width: Math.round(rect.width),
      height: Math.round(rect.height),
      muted: !!(video.muted || video.volume === 0),
      loop: !!video.loop,
      paused: !!video.paused,
      duration: (typeof duration === 'number' && isFinite(duration)) ? duration : 0,
      position: (typeof video.currentTime === 'number' && isFinite(video.currentTime)) ? video.currentTime : 0
    };
  }

  function videoSource(video) {
    if (video.__tvbNativeURL) { return { url: video.__tvbNativeURL, type: 'application/x-mpegurl' }; }
    var source = video.currentSrc || video.src || '';
    var typeHint = '';
    if (!source) {
      var child = video.querySelector('source[src]');
      if (child) { source = child.src || child.getAttribute('src') || ''; typeHint = child.type || ''; }
    }
    if (!typeHint) {
      var sources = video.querySelectorAll('source[src]');
      for (var i = 0; i < sources.length; i++) {
        if (abs(sources[i].src) === abs(source)) { typeHint = sources[i].type || ''; break; }
      }
    }
    return { url: source ? abs(source) : '', type: String(typeHint || '').toLowerCase() };
  }

  function noteVideo(video, eventType) {
    try {
      var source = videoSource(video);
      var metrics = videoMetrics(video);
      var isPlayback = (eventType === 'play' || eventType === 'playing');
      if (/^https?:/i.test(source.url)) {
        var kind = classify(source.url);
        if (!kind) { kind = source.type.indexOf('mpegurl') !== -1 ? 'hls' : 'file'; }
        note(source.url, kind, 'element', {
          element: true,
          width: metrics.width, height: metrics.height, muted: metrics.muted, loop: metrics.loop,
          duration: metrics.duration, started: isPlayback ? true : undefined
        });
      }
      if (isPlayback) {
        post({ t: 'playing', video: metrics, src: source.url, blob: !/^https?:/i.test(source.url) });
      }
    } catch (e) {}
  }

  ['loadstart', 'loadedmetadata', 'durationchange', 'play', 'playing'].forEach(function (type) {
    try {
      document.addEventListener(type, function (event) {
        var element = event.target;
        if (element && element.tagName === 'VIDEO') { noteVideo(element, type); }
      }, true);
    } catch (e) {}
  });

  function pauseAll() {
    var elements = document.querySelectorAll('video, audio');
    for (var i = 0; i < elements.length; i++) {
      try { elements[i].pause(); } catch (e) {}
    }
    var frames = document.querySelectorAll('iframe, frame');
    for (var j = 0; j < frames.length; j++) {
      try { frames[j].contentWindow.postMessage({ __tvb: TOKEN, cmd: 'pauseAll' }, '*'); } catch (e) {}
    }
  }

  // ---------------------------------------------------------------- fullscreen hand-off
  //
  // A page's own fullscreen button is how the user asks for the Apple TV player. The request
  // is answered by native code instead of WebKit's fullscreen mode.

  function largestVideoIn(root) {
    var videos = (root && root.querySelectorAll) ? root.querySelectorAll('video') : [];
    var best = null, bestScore = -1;
    for (var i = 0; i < videos.length; i++) {
      var rect = videos[i].getBoundingClientRect();
      var score = rect.width * rect.height + (videos[i].paused ? 0 : 1e9);
      if (score > bestScore) { best = videos[i]; bestScore = score; }
    }
    return best;
  }

  function requestNativeFullscreen(target) {
    var video = null;
    if (target && target.tagName === 'VIDEO') { video = target; }
    if (!video) { video = largestVideoIn(target); }
    if (!video) { video = largestVideoIn(document); }
    var message = { t: 'fullscreen', title: String(document.title || '') };
    if (video) {
      var source = videoSource(video);
      message.video = videoMetrics(video);
      message.src = /^https?:/i.test(source.url) ? source.url : '';
      message.blob = !!source.url && !message.src;
      var hls = hlsForMedia(video);
      if (hls && hls.url) {
        // The master playlist, plus the quality / voice-over / subtitles picked in the page.
        message.hls = hlsChoices(hls);
        message.src = message.hls.master;
        message.blob = false;
      }
      var subtitles = pageSubtitles(video, hls);
      if (subtitles.length) { message.subtitles = subtitles; }
      log('fullscreen: ' + (hls ? 'hls.js' : 'no hls.js') + '; ' + describeSubtitleState(video));
    }
    post(message);
  }

  function interceptFullscreen(prototype, name, returnsPromise) {
    try {
      if (!prototype || typeof prototype[name] !== 'function') { return; }
      Object.defineProperty(prototype, name, {
        configurable: true, writable: true,
        value: function () {
          requestNativeFullscreen(this);
          return returnsPromise ? Promise.resolve() : undefined;
        }
      });
    } catch (e) {}
  }

  try {
    interceptFullscreen(window.Element && Element.prototype, 'requestFullscreen', true);
    interceptFullscreen(window.Element && Element.prototype, 'webkitRequestFullscreen', false);
    interceptFullscreen(window.Element && Element.prototype, 'webkitRequestFullScreen', false);
    interceptFullscreen(window.HTMLVideoElement && HTMLVideoElement.prototype, 'webkitEnterFullscreen', false);
    interceptFullscreen(window.HTMLVideoElement && HTMLVideoElement.prototype, 'webkitEnterFullScreen', false);
    // Players hide their fullscreen button when the API looks unavailable.
    ['fullscreenEnabled', 'webkitFullscreenEnabled'].forEach(function (name) {
      try { Object.defineProperty(Document.prototype, name, { configurable: true, get: function () { return true; } }); } catch (e) {}
    });
    if (window.HTMLVideoElement) {
      try { Object.defineProperty(HTMLVideoElement.prototype, 'webkitSupportsFullscreen', { configurable: true, get: function () { return true; } }); } catch (e) {}
    }
  } catch (e) {}

  // ---------------------------------------------------------------- point commands

  var INTERACTIVE = 'a[href], button, input, textarea, select, option, label, summary, video, ' +
                    '[role="button"], [role="link"], [role="tab"], [role="menuitem"], [role="option"], ' +
                    '[role="checkbox"], [role="switch"], [role="slider"], [onclick], [tabindex], [contenteditable]';
  var EDITABLE = 'input, textarea, select, [contenteditable=""], [contenteditable="true"]';
  var TEXT_TYPES = { text: 1, search: 1, url: 1, email: 1, password: 1, tel: 1, number: 1,
                     date: 1, datetime: 1, 'datetime-local': 1, month: 1, time: 1, week: 1 };

  var lastEditable = null;
  var lastHover = null;

  function isFrameElement(element) {
    return !!element && (element.tagName === 'IFRAME' || element.tagName === 'FRAME');
  }

  function frameDocument(frame) {
    try { return frame.contentDocument || null; } catch (e) { return null; }
  }

  // Deepest element at a viewport point, descending shadow roots and same-origin frames.
  function hitTest(root, x, y, depth) {
    if (!root || typeof root.elementFromPoint !== 'function' || depth > 12) { return null; }
    var element = root.elementFromPoint(x, y);
    if (!element) { return null; }
    if (element.shadowRoot && typeof element.shadowRoot.elementFromPoint === 'function') {
      var inner = hitTest(element.shadowRoot, x, y, depth + 1);
      if (inner && inner.element && inner.element !== element) { return inner; }
    }
    if (isFrameElement(element)) {
      var doc = frameDocument(element);
      if (doc) {
        var point = pointInFrame(element, x, y);
        var nested = hitTest(doc, point.x, point.y, depth + 1);
        if (nested) { return nested; }
      }
    }
    return { element: element, x: x, y: y };
  }

  function pointInFrame(frame, x, y) {
    var rect = frame.getBoundingClientRect();
    var scaleX = frame.offsetWidth ? rect.width / frame.offsetWidth : 1;
    var scaleY = frame.offsetHeight ? rect.height / frame.offsetHeight : 1;
    return {
      x: (x - rect.left) / (scaleX || 1) - (frame.clientLeft || 0),
      y: (y - rect.top) / (scaleY || 1) - (frame.clientTop || 0)
    };
  }

  function closest(element, selector) {
    while (element && element.nodeType === 1) {
      try { if (element.matches && element.matches(selector)) { return element; } } catch (e) { return null; }
      element = element.parentElement || (element.getRootNode && element.getRootNode().host) || null;
    }
    return null;
  }

  function pointerCursor(element) {
    try {
      var view = element.ownerDocument.defaultView;
      return view.getComputedStyle(element).cursor === 'pointer';
    } catch (e) { return false; }
  }

  function isInteractive(element) {
    if (!element) { return false; }
    if (closest(element, INTERACTIVE)) { return true; }
    return pointerCursor(element);
  }

  function findVideo(element, x, y) {
    var direct = closest(element, 'video');
    if (direct) { return direct; }
    var doc = (element && element.ownerDocument) || document;
    var videos = doc.querySelectorAll('video');
    var best = null, bestArea = 0;
    for (var i = 0; i < videos.length; i++) {
      var rect = videos[i].getBoundingClientRect();
      if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) {
        var area = rect.width * rect.height;
        if (area > bestArea) { best = videos[i]; bestArea = area; }
      }
    }
    return best;
  }

  function looksLikePlayControl(element) {
    var depth = 0;
    while (element && element.nodeType === 1 && depth < 8) {
      var label = [
        element.id || '',
        (typeof element.className === 'string') ? element.className : '',
        element.getAttribute('aria-label') || '',
        element.getAttribute('title') || '',
        element.getAttribute('data-plyr') || ''
      ].join(' ').toLowerCase();
      if (/(^|[^a-z])(play|player|playback|video|watch|trailer|poster)([^a-z]|$)/.test(label) ||
          /(jw-|vjs-|plyr|ytp-|pjs|playerjs|video-js|allplay|kodik)/.test(label)) {
        return true;
      }
      element = element.parentElement;
      depth += 1;
    }
    return false;
  }

  var CONTROL = 'button, a[href], [role="button"], [data-plyr], [data-allplay], [data-action], [tabindex]';

  function looksLikeFullscreenControl(element) {
    // Only the clicked control itself (an icon inside it is fine). Player containers carry
    // state classes such as "allplay--fullscreen-enabled", which say nothing about the click.
    var depth = 0;
    while (element && element.nodeType === 1 && depth < 5) {
      var classes = (typeof element.className === 'string') ? element.className : ((element.className && element.className.baseVal) || '');
      classes = classes.replace(/\S*(full-?screen|fs)[-_]*(enabled|supported|active|fallback|mode|ios)\S*|\S*is-full-?screen\S*/gi, '');
      var label = [
        element.id || '',
        classes,
        element.getAttribute('aria-label') || '',
        element.getAttribute('title') || '',
        element.getAttribute('data-plyr') || '',
        element.getAttribute('data-allplay') || '',
        element.getAttribute('data-action') || ''
      ].join(' ').toLowerCase();
      if (/full-?screen|fullscreen|полноэкран|во весь экран|на весь экран|(^|[^a-z])fs([^a-z]|$)|expand/.test(label)) {
        return true;
      }
      if (element.matches && element.matches(CONTROL)) {
        return false;
      }
      element = element.parentElement;
      depth += 1;
    }
    return false;
  }

  function describeEditable(element) {
    var target = closest(element, EDITABLE);
    if (!target) { return null; }
    var tag = target.tagName.toLowerCase();
    var type = String(target.type || '').toLowerCase();
    var info = { tag: tag };
    if (tag === 'select') {
      info.kind = 'select';
      info.multiple = !!target.multiple;
      info.options = [];
      for (var i = 0; i < target.options.length && i < 200; i++) {
        var option = target.options[i];
        info.options.push({ text: String(option.text || option.value || ''), index: i,
                            selected: !!option.selected, disabled: !!option.disabled });
      }
    } else if (tag === 'textarea' || target.isContentEditable || (tag === 'input' && (!type || TEXT_TYPES[type]))) {
      info.kind = 'text';
      info.type = (tag === 'input') ? (type || 'text') : 'text';
      info.multiline = (tag === 'textarea' || !!target.isContentEditable);
      info.value = (typeof target.value === 'string') ? target.value : String(target.textContent || '');
      info.placeholder = String(target.placeholder || target.getAttribute('aria-label') || '');
      info.label = String(target.title || target.getAttribute('aria-label') || target.name || target.placeholder || '');
      info.hasForm = !!target.form;
    } else {
      return null;
    }
    info.__element = target;
    return info;
  }

  function describe(element, x, y) {
    var info = {
      frame: { url: String(location.href), title: String(document.title || ''),
               width: window.innerWidth, height: window.innerHeight }
    };
    if (!element) { return info; }
    info.interactive = isInteractive(element);

    var link = closest(element, 'a[href]');
    if (link) {
      var rawHref = String(link.getAttribute('href') || '');
      info.link = {
        href: abs(link.href || rawHref),
        target: String(link.getAttribute('target') || '').toLowerCase(),
        text: String(link.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 120),
        script: /^\s*(javascript:|#\s*$)/i.test(rawHref) || rawHref === ''
      };
    }
    if (element.tagName === 'IMG' && element.currentSrc) {
      info.image = { src: abs(element.currentSrc) };
    }

    var editable = describeEditable(element);
    if (editable) { info.editable = editable; }

    var video = findVideo(element, x, y);
    if (video) {
      var source = videoSource(video);
      var metrics = videoMetrics(video);
      metrics.src = /^https?:/i.test(source.url) ? source.url : '';
      metrics.blob = !!source.url && !metrics.src;
      var videoHls = hlsForMedia(video);
      if (videoHls && videoHls.url) {
        metrics.hls = hlsChoices(videoHls);
        metrics.src = metrics.hls.master;
        metrics.blob = false;
      }
      var videoSubtitles = pageSubtitles(video, videoHls);
      if (videoSubtitles.length) { metrics.subtitles = videoSubtitles; }
      metrics.kindHint = source.type;
      info.video = metrics;
    }
    info.playIntent = !!video || looksLikePlayControl(element);
    // On the picture itself (or a plain overlay on it), as opposed to a control drawn over
    // the video such as an episode list or a quality menu.
    var control = closest(element, 'a[href], button, select, input, textarea, [role="button"], [role="option"], ' +
                                   '[role="menuitem"], [role="listbox"], [role="tab"], li, option');
    info.onVideoSurface = !!video && (!!closest(element, 'video') || !control || looksLikePlayControl(control));
    info.fullscreenControl = looksLikeFullscreenControl(element);
    if (info.fullscreenControl && video) { log('fullscreen control: ' + describeSubtitleState(video)); }
    info.hasVideoElement = document.querySelectorAll('video').length > 0;

    info.media = [];
    for (var i = 0; i < mediaOrder.length; i++) {
      if (media[mediaOrder[i]]) { info.media.push(media[mediaOrder[i]]); }
    }
    return info;
  }

  function fire(target, type, constructorName, x, y, extra) {
    try {
      var view = (target.ownerDocument && target.ownerDocument.defaultView) || window;
      var Constructor = view[constructorName] || window[constructorName];
      var init = { bubbles: true, cancelable: true, composed: true, view: view,
                   clientX: x, clientY: y, screenX: x, screenY: y, button: 0,
                   buttons: (type === 'pointerdown' || type === 'mousedown') ? 1 : 0 };
      if (constructorName === 'PointerEvent') { init.pointerType = 'mouse'; init.pointerId = 1; init.isPrimary = true; }
      if (extra) { for (var key in extra) { init[key] = extra[key]; } }
      return target.dispatchEvent(new Constructor(type, init));
    } catch (e) { return true; }
  }

  function hover(element, x, y) {
    if (element && element !== lastHover) {
      if (lastHover && lastHover.isConnected) {
        fire(lastHover, 'pointerout', 'PointerEvent', x, y);
        fire(lastHover, 'mouseout', 'MouseEvent', x, y);
      }
      fire(element, 'pointerover', 'PointerEvent', x, y);
      fire(element, 'mouseover', 'MouseEvent', x, y);
      lastHover = element;
    }
    if (element) {
      fire(element, 'pointermove', 'PointerEvent', x, y);
      fire(element, 'mousemove', 'MouseEvent', x, y);
    }
    return { interactive: isInteractive(element) };
  }

  function click(element, x, y) {
    var info = describe(element, x, y);
    if (!element) { info.action = 'none'; return info; }

    if (info.editable) {
      lastEditable = info.editable.__element;
      try { lastEditable.focus(); } catch (e) {}
      info.action = 'edit';
      return info;
    }
    if (info.link && info.link.target === '_blank' && !info.link.script && /^https?:/i.test(info.link.href)) {
      info.action = 'newtab';
      return info;
    }

    try {
      var focusTarget = closest(element, INTERACTIVE);
      if (focusTarget && focusTarget.focus) { focusTarget.focus({ preventScroll: true }); }
    } catch (e) {}

    hover(element, x, y);
    fire(element, 'pointerdown', 'PointerEvent', x, y);
    fire(element, 'mousedown', 'MouseEvent', x, y);
    fire(element, 'pointerup', 'PointerEvent', x, y);
    fire(element, 'mouseup', 'MouseEvent', x, y);
    if (typeof element.click === 'function') {
      element.click();
    } else {
      fire(element, 'click', 'MouseEvent', x, y, { detail: 1 });
    }
    info.action = 'click';
    return info;
  }

  function setNativeValue(element, value) {
    try {
      var prototype = (element.tagName === 'TEXTAREA') ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
      var descriptor = Object.getOwnPropertyDescriptor(prototype, 'value');
      if (descriptor && descriptor.set) { descriptor.set.call(element, value); return; }
    } catch (e) {}
    element.value = value;
  }

  function setText(data) {
    var target = lastEditable;
    if (!target || !target.isConnected) { return { ok: false }; }
    var text = String((data && data.text) || '');
    if (typeof target.value === 'string') { setNativeValue(target, text); } else { target.textContent = text; }
    try {
      target.dispatchEvent(new Event('input', { bubbles: true }));
      target.dispatchEvent(new Event('change', { bubbles: true }));
    } catch (e) {}
    if (data && data.submit) {
      var keyInit = { bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13 };
      var proceed = true;
      try {
        proceed = target.dispatchEvent(new KeyboardEvent('keydown', keyInit));
        target.dispatchEvent(new KeyboardEvent('keypress', keyInit));
        target.dispatchEvent(new KeyboardEvent('keyup', keyInit));
      } catch (e) {}
      if (proceed && target.form) {
        try {
          if (typeof target.form.requestSubmit === 'function') { target.form.requestSubmit(); } else { target.form.submit(); }
        } catch (e) { try { target.form.submit(); } catch (e2) {} }
      }
    }
    return { ok: true };
  }

  function setSelect(data) {
    var target = lastEditable;
    if (!target || !target.isConnected || target.tagName !== 'SELECT') { return { ok: false }; }
    var index = Number(data && data.index);
    if (!(index >= 0 && index < target.options.length)) { return { ok: false }; }
    target.selectedIndex = index;
    try {
      target.dispatchEvent(new Event('input', { bubbles: true }));
      target.dispatchEvent(new Event('change', { bubbles: true }));
    } catch (e) {}
    return { ok: true };
  }

  function canScroll(element, dx, dy) {
    var style;
    try { style = element.ownerDocument.defaultView.getComputedStyle(element); } catch (e) { return false; }
    var scrollY = /(auto|scroll|overlay)/.test(style.overflowY) && element.scrollHeight > element.clientHeight + 1;
    var scrollX = /(auto|scroll|overlay)/.test(style.overflowX) && element.scrollWidth > element.clientWidth + 1;
    if (dy > 0 && scrollY && element.scrollTop + element.clientHeight < element.scrollHeight - 1) { return true; }
    if (dy < 0 && scrollY && element.scrollTop > 0) { return true; }
    if (dx > 0 && scrollX && element.scrollLeft + element.clientWidth < element.scrollWidth - 1) { return true; }
    if (dx < 0 && scrollX && element.scrollLeft > 0) { return true; }
    return false;
  }

  function scrollAt(element, data) {
    var dx = Number(data && data.dx) || 0, dy = Number(data && data.dy) || 0;
    var node = element;
    while (node && node.nodeType === 1) {
      if (node !== document.documentElement && node !== document.body && canScroll(node, dx, dy)) {
        node.scrollLeft += dx; node.scrollTop += dy;
        return { scrolled: true };
      }
      node = node.parentElement;
    }
    if (!isTop) {
      var before = { x: window.scrollX, y: window.scrollY };
      window.scrollBy(dx, dy);
      return { scrolled: before.x !== window.scrollX || before.y !== window.scrollY };
    }
    return { scrolled: false };
  }

  function handlePoint(command, x, y, id, data) {
    var hit = hitTest(document, x, y, 0);
    var element = hit ? hit.element : null;

    if (isFrameElement(element) && !frameDocument(element)) {
      var point = pointInFrame(element, hit.x, hit.y);
      try {
        element.contentWindow.postMessage({ __tvb: TOKEN, cmd: command, x: point.x, y: point.y, id: id, data: data || null }, '*');
        return 'relay';
      } catch (e) {}
    }

    var result;
    var px = hit ? hit.x : x, py = hit ? hit.y : y;
    switch (command) {
      case 'hover': result = hover(element, px, py); break;
      case 'click': result = click(element, px, py); break;
      case 'context': result = describe(element, px, py); result.action = 'context'; break;
      case 'setText': result = setText(data); break;
      case 'setSelect': result = setSelect(data); break;
      case 'scroll': result = scrollAt(element, data); break;
      default: result = {};
    }
    if (result.editable) { delete result.editable.__element; }
    post({ t: 'point', id: id, cmd: command, result: result });
    return 'done';
  }

  window.addEventListener('message', function (event) {
    var data = event.data;
    if (!data || typeof data !== 'object' || data.__tvb !== TOKEN) { return; }
    event.stopImmediatePropagation();
    if (data.cmd === 'pauseAll') { pauseAll(); return; }
    try { handlePoint(data.cmd, Number(data.x) || 0, Number(data.y) || 0, data.id, data.data); } catch (e) {
      post({ t: 'point', id: data.id, cmd: data.cmd, result: { error: String(e) } });
    }
  }, true);

  // Entry points for native code. They are only meaningful in the top frame, where
  // native evaluates JavaScript; the token keeps page scripts from calling them usefully.
  var api = {
    point: function (token, command, viewX, viewY, viewWidth, id, data) {
      if (token !== TOKEN) { return 'denied'; }
      var scale = (viewWidth > 0 && window.innerWidth > 0) ? (window.innerWidth / viewWidth) : 1;
      try { return handlePoint(command, viewX * scale, viewY * scale, id, data || null); } catch (e) {
        post({ t: 'point', id: id, cmd: command, result: { error: String(e) } });
        return 'error';
      }
    },
    pauseAll: function (token) { if (token === TOKEN) { pauseAll(); } return true; },
    pageInfo: function (token) {
      if (token !== TOKEN) { return ''; }
      var color = '';
      try {
        var meta = document.querySelector('meta[name="theme-color"]');
        if (meta && meta.content) { color = meta.content; }
        if (!color) {
          var candidates = [document.body, document.documentElement];
          for (var i = 0; i < candidates.length && !color; i++) {
            if (!candidates[i]) { continue; }
            var background = getComputedStyle(candidates[i]).backgroundColor;
            if (background && background !== 'transparent' && !/rgba\(\s*0\s*,\s*0\s*,\s*0\s*,\s*0\s*\)/.test(background)) { color = background; }
          }
        }
      } catch (e) {}
      return JSON.stringify({ title: String(document.title || ''), color: color });
    }
  };
  try {
    Object.defineProperty(window, '__tvbAgent', { value: api, enumerable: false, configurable: false, writable: false });
  } catch (e) { window.__tvbAgent = api; }
})();
