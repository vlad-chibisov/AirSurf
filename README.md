<p align="center">
  <img src=".github/logo.png" alt="AirSurf icon: a compass with a surfboard for a needle" width="360">
</p>

<h1 align="center">AirSurf</h1>

<p align="center">
  <b>A web browser for Apple TV</b>, with videos that continue in the Apple TV player.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/tvOS-26-black?logo=apple" alt="tvOS 26">
  <img src="https://img.shields.io/badge/Xcode-27%2B-147EFB?logo=xcode&logoColor=white" alt="Xcode 27 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2BB5E8" alt="MIT license"></a>
</p>

A web browser for Apple TV. This version is for personal and amateur side use on tvOS 26:

- **Redesigned interface**: a floating toolbar, a start page with your favourite and recent sites as
  large tiles, a side-panel menu, and a card-based tab overview. All of them use the tvOS focus engine.
  Liquid Glass is used on newer Apple TVs. The first Apple TV 4K (A1842, `AppleTV6,2`) and the Apple TV HD
  get a lighter blur instead, which costs less to draw.
- **Videos continue in the Apple TV player**: use the site's own player to pick the episode, voice-over
  and quality, then press its full-screen button. The video continues full screen in the system player,
  from the same stream and position, with the normal Siri Remote scrubbing, info panel, and audio and
  subtitle menus. This works for players embedded from other sites (iframes), which is how most film and
  series sites show video. Videos resume where you stopped.
- **Ad and pop-up blocking**: about 3,600 ad and tracking domains are blocked, and pop-ups that a page opens
  without you choosing a link are stopped.

It uses private APIs (WebKit is not public on tvOS), so it can only be installed from Xcode, never the App Store.

Installing
----------

There is no download: you build AirSurf yourself and sign it with your own Apple ID. A free Apple ID is
enough; a paid developer account only changes how long the app keeps working (see below).

1. Open `AirSurf.xcodeproj` in Xcode 27 or later.
2. Create `Config/Signing.local.xcconfig` with your team and a bundle identifier of your own:

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   AIRSURF_BUNDLE_ID = com.yourname.airsurf
   ```

   Your team ID is in Xcode › Settings › Accounts (select the team) or at developer.apple.com ›
   Membership. Git ignores this file, so your details stay out of the repository. (Choosing a team in
   *Signing & Capabilities* works too, but writes it into the project file.)
3. Pair the Apple TV with Xcode: on the Apple TV, Settings › Remotes and Devices › Remote App and
   Devices; in Xcode, Window › Devices and Simulators. Select the Apple TV as the run destination and
   press Run.

Builds signed with a free Apple ID stop opening after 7 days; run from Xcode again to renew. With a paid
developer account they last a year.

Using it
--------

| On a page | |
|---|---|
| Swipe | Move the pointer. Pushing it past a screen edge scrolls the page. |
| Click | Click what is under the pointer. A video plays inside the page. |
| A player's full-screen button | The video continues in the Apple TV player |
| Hold click | Actions: open link in a new tab, add to Favorites, play the page's video full screen |
| Play/Pause | Scroll mode: swipes scroll the page. Click or press Play/Pause again to leave it. |
| Hold Play/Pause | Menu |
| Up / Down on the clickpad | Scroll by most of a screen |
| Back | Previous page, then the start page, then the Home screen |

On the start page, in menus and in the tab overview the remote works as it does elsewhere in tvOS.
In the tab overview, Play/Pause closes the highlighted tab.

Quality and voice-over chosen in the site's player carry over: either they change the stream itself,
which is how most of these players work, or (players built on hls.js) the choice is applied in the
Apple TV player's own track and quality selection. Subtitles carry over too. Those that are part of the
stream are in the Apple TV player's subtitle menu anyway. Those a site's player loads as separate files
(WebVTT or SRT) are added to the stream as ordinary subtitle tracks, so they appear in the same menu in
the system caption style, and the one that was on in the page is on. The menu gets one track per
language (it names tracks by language only): the one you had on, otherwise the most complete one. When
the native player can't open a stream, the app says so and you can watch it in the page.

Some players need Media Source Extensions, which WebKit on Apple TV doesn't have; they used to stop with
"browser not supported" or "update iOS". For those the app gives the player a stand-in and plays the
same stream with the system's own HLS support, so the player's menus work and the video plays in the
page. Known players get this straight away; any other hls.js player that reports itself unsupported
is reloaded once with it.
If "Play Video Full Screen" picks the wrong stream (an advert, say), *Menu › All Videos on This Page*
lists every stream the page has loaded.

Settings (Menu › Settings): ad blocking, pop-up blocking, the tvOS player on/off, page zoom
(125% suits most sites on a TV), always-visible or auto-hiding toolbar, desktop or mobile versions of
sites, search engine (Google, Yandex, DuckDuckGo, Bing), pointer speed, and what new tabs open.

What is and isn't possible
--------------------------

- **Storage on Apple TV**: apps may only write to their Caches folder, and their settings are capped at
  about 500 KB. Compiled ad-block rules, open tabs, thumbnails, cookies and what sites save in the
  browser (local storage, IndexedDB) therefore live in Caches, with small copies of tabs and cookies in
  settings in case tvOS clears Caches.
- **Ad blocking** uses WebKit's built-in content blocker, the same engine Safari's blockers use, so it
  costs almost nothing at page-load time. The list is in `AirSurf/Resources/ContentRules-Ads.json`
  and is generated by `Tools/update_content_rules.py` from Peter Lowe's ad server list plus
  `Tools/extra-ad-domains.txt` (ad networks common on streaming sites; `re:` lines are host patterns
  for networks that rotate numbered domains). To refresh it:
  `python3 Tools/update_content_rules.py --download`, then rebuild.
- **Browser extensions** in the Safari or Chrome sense are not possible: tvOS has no Safari, and WebKit on
  tvOS has no extension system. The same effect comes from scripts the app injects into every page; the
  video detection in `Resources/BrowserAgent.js` works this way. Site-specific fixes would go there too.
- **Video**: WebKit on tvOS has no Media Source Extensions, so in-page playback always goes through the
  system's HLS support (see the stand-in above). The Apple TV player plays HLS (`.m3u8`) and MP4/MOV. Sites that only serve DASH or WebM, or
  that protect streams with DRM (Netflix, most paid services), keep playing in the page, or not at all.
  YouTube is one of these: it does not hand out plain streams.

Development
-----------

The project has no dependencies. Debug builds accept launch arguments for testing in the Simulator, where
the Siri Remote can't be scripted: `-DebugURL <url>`, `-DebugClicks "x,y@seconds;..."`,
`-DebugScroll "y@seconds"`, `-DebugActions "newtab@1;tabs@3;hold@5;menu@7"`,
`-DebugEval "js@seconds"` (result in the log). They do nothing in Release builds.

`BROWSER_MATERIALS=light` or `=glass` in the scheme's environment forces the lighter or the Liquid Glass look.

License
-------

MIT; see `LICENSE`. The ad server list in `Tools/adservers.txt`, and the blocking rules generated from
it, come from Peter Lowe's list (pgl.yoyo.org/adservers) and are under that list's own terms: free for
personal, non-commercial use.
