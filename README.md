<p align="center">
  <img src=".github/logo.png" alt="AirSurf icon: a compass with a surfboard for a needle" width="360">
</p>

<h1 align="center">AirSurf</h1>

<p align="center">
  <b>A web browser for Apple TV</b>, with videos that continue in the Apple TV player.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/tvOS-26%2B-black?logo=apple" alt="tvOS 26 or later">
  <img src="https://img.shields.io/badge/Xcode-27%2B-147EFB?logo=xcode&logoColor=white" alt="Xcode 27 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2BB5E8" alt="MIT license"></a>
</p>

### Ever wanted to open a website on your Apple TV?

Apple TV has no Safari, and the App Store has no browser for it either. So the film site you use on your
laptop, the match stream your friend sent, the recipe you want on the big screen: none of them can be
opened on the TV.

AirSurf changes that. It is a full web browser made for the Siri Remote: open any site, click around with
an on-screen pointer, and when a video starts, send it to the Apple TV player and watch it like anything
else on your TV.

It works on every Apple TV that can install apps, from the Apple TV HD to the latest Apple TV 4K, with
tvOS 26 or later.

What you get
------------

- **An interface that feels at home on Apple TV.** A start page with your favourite and recent sites as
  big tiles, a floating toolbar, a side menu and a card view of your tabs, all moved around with the
  remote the way you're used to. Newer Apple TVs get the Liquid Glass look.
- **Videos in the Apple TV player.** Pick the episode, voice-over and quality in the site's own player,
  then press its full-screen button. The video carries on in the Apple TV player from the same spot, with
  normal Siri Remote scrubbing, and with the audio and subtitle menus you know. The subtitles you had on in
  the page come along. Next time, the video picks up where you stopped.
- **Fewer ads and pop-ups.** Thousands of ad and tracking sites are blocked, and pages can't open pop-ups
  you didn't ask for.
- **Your tabs stay put.** Open tabs, favourites and site logins are still there after you close the app.

Installing
----------

AirSurf isn't on the App Store (Apple doesn't allow browsers on Apple TV), so you build it yourself on a
Mac and install it straight onto your Apple TV. It takes about ten minutes the first time, and a free
Apple ID is enough.

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

With a free Apple ID the app stops opening after 7 days; press Run in Xcode again to renew it. With a paid
developer account it lasts a year.

Using the remote
----------------

| On a page | |
|---|---|
| Swipe | Move the pointer. Pushing it past a screen edge scrolls the page. |
| Click | Click what is under the pointer |
| A player's full-screen button | The video continues in the Apple TV player |
| Hold click | Open a link in a new tab, add to Favorites, play the page's video full screen |
| Play/Pause | Scroll mode: swipes scroll the page. Click or press Play/Pause again to leave it. |
| Hold Play/Pause | Menu |
| Up / Down on the clickpad | Scroll by most of a screen |
| Back | Previous page, then the start page, then the Home screen |

On the start page, in menus and in the tab overview the remote works as it does everywhere else on
Apple TV. In the tab overview, Play/Pause closes the highlighted tab.

If "Play Video Full Screen" picks the wrong video (an advert, say), *Menu › All Videos on This Page*
lists every video the page has loaded.

In *Menu › Settings* you can turn ad and pop-up blocking on or off, choose whether videos go to the Apple
TV player, zoom pages (125% suits most sites on a TV), keep the toolbar visible or let it hide, ask for
desktop or mobile versions of sites, pick a search engine (Google, Yandex, DuckDuckGo, Bing), set the
pointer speed, and choose what new tabs open.

Good to know
------------

- **Netflix, YouTube and other paid or protected services won't work.** They lock their video so that
  only their own apps can play it. Use their Apple TV apps for those.
- Sites that only offer some less common video formats may play inside the page only, or not at all.
- There are no browser extensions: Apple TV has no system for them.

Want to know how it works, or help improve it? See [DEVELOPMENT.md](DEVELOPMENT.md).

License
-------

MIT; see `LICENSE`. The ad server list in `Tools/adservers.txt`, and the blocking rules generated from
it, come from Peter Lowe's list (pgl.yoyo.org/adservers) and are under that list's own terms: free for
personal, non-commercial use.
