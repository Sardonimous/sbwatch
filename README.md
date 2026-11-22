# SBWatch

An Xtream Codes live-TV client for Roku (BrightScript / SceneGraph), built for personal use and sideloading in developer mode.

> **Built with Claude.** Most of SBWatch was designed and written by **Claude** (Anthropic's AI assistant) in conversation with the repository owner: the architecture, the BrightScript / SceneGraph code, the on-device search index, the grid guide, the icon and this README. The owner set the requirements, tested every build on a real Roku Ultra, and reported the bugs and ideas that shaped each version.

SBWatch is only a player. You supply your own Xtream provider; no content or credentials are included in this repository.

## Features
- **Movies and Series with resume.** Switch between Live TV, Movies and Series from the first row of the category list ("Browse: ..."). Movies open a detail screen (poster, plot, rating, cast, and the provider's video / audio format when it has one - with a warning for audio the Roku cannot play) with Play / Resume / Start over / Add or remove favorite; Series open into seasons and episodes; when an episode ends, a 10-second countdown (OK: play now, Back: stop) precedes the next one. Progress is saved every 15 seconds and when you stop, Recently Watched only records a channel once it has really started playing. A "Continue Watching" list shows what you left part-way, and titles with saved progress are marked "(resume 34:10)". Search, the category filter and the index work in each mode.
- Xtream login (server URL, username, password), saved on the Roku
- Categories with a name filter; channels load per category, so 30,000-channel providers stay within Roku memory limits
- A gold star marks channels that are in your Favorites (on every list except Favorites itself, and in the guide)
- Channel logos next to channel names (list, guide, now/next panel, playback banner)
- Now/next panel with color-coded, scrollable program cards
- Full time-grid guide (fetched lazily for the visible rows only)
- Search: whole-provider channel search (on-device name index) and program-title search in the open channel list
- Favorites and recently watched
- HLS playback with automatic MPEG-TS fallback; stream "nerd" info panel

## Install (developer mode)
1. On the Roku: Home x3, Up x2, Right, Left, Right, Left, Right -> enable developer mode, set a web password, note the IP.
2. Build the package: `./build.sh` (creates `dist/SBWatch-v<version>.zip`).
3. Browse to `http://ROKU_IP`, log in (user `rokudev`), upload the zip from `dist/`, click Install.
4. Debug console (optional): `telnet ROKU_IP 8085`

## Entering the provider
On first launch SBWatch shows three keyboard prompts (server URL, username, password); the Roku iOS app's keyboard types into them. Press `*` on the category list to change the provider later.

Or launch with arguments (app must not already be running):

    curl -d '' 'http://ROKU_IP:8060/launch/dev?server=http%3A%2F%2Fhost%3A8080&user=USER&pass=PASS'

Credentials are stored in the Roku registry on the device, never in the package.

## Controls
| Where | Key | Action |
|---|---|---|
| Lists | OK | open category / play channel |
| Lists | Left / Right | move between category list, channel list, guide panel |
| Category list | first rows | Search ...; Filter categories ... (the filter is remembered) |
| Category list | Replay | open the search dialog |
| Channel list | `*` | add / remove favorite |
| Favorites list | `*` | menu: Move (Up/Down, OK to drop, Back to cancel), Move to top, Remove |
| Channel list | Replay | open the full guide |
| Guide | Left/Right, Up/Down | program / channel; OK watch; Rewind/FF page; Replay = now; `*` favorite; Back close |
| Watching (any mode) | OK | first press: info banner with a help line; second press (while the help is showing): playback options (guide, stream info, favorite, audio track, ...) |
| Watching (any mode) | Play/Pause | pause / resume |
| Watching (any mode) | A | add / remove favorite (an episode favorites its series) |
| Watching (any mode) | B | closed captions on / off |
| Watching (any mode) | `*` | playback options (same menu as the second OK) |
| Watching (any mode) | Back | stop (returns to the list, or to the guide if you started from it) |
| Watching Live TV | Up / Down, Left | previous / next channel, open the guide |
| Watching Movies / Series | Left / Right, Rewind / Fast-forward, Replay | seek 10 s, 60 s, back 10 s |
| Watching Series | Up / Down | previous / next episode (from an episode list) |
| Any list | A | add / remove favorite |
| Channel, movie and series lists | B | cycle the sort order (temporary - never saved) |
| Recently Watched, Continue Watching | `*` | remove this item / clear the list |

Closed captions: SBWatch declares the in-band EIA-608 caption channels (CC1-CC4) to the Roku player, which is what makes the Roku show them (a decoder like ExoPlayer finds them by itself; Roku does not). Press **B** to turn captions on or off; the Replay menu item **Caption channel** cycles CC1 -> CC2 -> CC3 -> CC4. (You can also use Roku's Settings > Accessibility > Captions.) DVB / teletext subtitles are not supported by the Roku player.

## Long names scroll
In the category and channel / movie / series lists, a name that does not fit is shown with "..." and scrolls sideways while its row is highlighted.

## Sorting
Press **B** on a channel, movie or series list to cycle through the orders that apply, ending with "Original order". It is temporary: opening a list again restores the provider's order. Available orders: Title A-Z / Z-A (always); Newest / oldest added (series: recently updated), when the provider supplies dates; Highest / lowest rated and Newest / oldest year (movies and series), when the provider supplies them.

## Releasing
Releases are made from tags. `tools/release-notes.sh` prints notes for everything committed since the last tag (each commit's subject and description). `tools/release.sh` does the whole release: it builds the zip, writes the notes, tags the commit as `v<major>.<minor>.<build>` (from the manifest), pushes, and creates the GitHub release with the zip attached. It needs the GitHub CLI (`gh auth login` once). Bump the version in `manifest` and commit first. Plain git can do the tag and the notes (`git tag -a`, `git log`); creating the release itself on GitHub is what `gh release create` adds.

## Debug log
Errors are echoed to the Roku debug console (`telnet ROKU_IP 8085`) with a time stamp: playback errors with the full error code / message / info, the video and audio formats and the (masked) stream URL, API failures, and a "no sound" check a few seconds after a movie starts. Every video state change is logged too.

## Movies and Series notes
- Everything saved on the Roku shares its 32 KB registry: Live favorites (about 70), Movie favorites and Series favorites (about 40 each), Recently Watched (10) and resume points (newest 30). A resume point is saved after 30 seconds of viewing and cleared when you finish (95% watched).
- Playback uses the Roku player's own controls: OK pause / play, Left / Right and Rewind / Fast-forward to seek, `*` for audio and subtitle choices, Back to stop. B turns captions on / off.
- Favorites exist separately for Live TV, Movies and Series (a series is favorited as a whole). Recently Watched and the program guide are for Live TV only. Resume data is cleared if you change provider.
- Playback options include **Audio track** when a file has several audio tracks - useful when a movie plays without sound (the info screen lists each track and codec; the Roku cannot decode every audio format, e.g. DTS).

## Notes
- Stream info: the player's "latency" field returns 2147483647 (the largest 32-bit number) on these streams, which is a placeholder for "not reported", so the panel says so.
- **A / B buttons:** on remotes that have them (Roku reports the key names as `A` and `B`), A toggles the favorite star (it also works during playback, where the system captures `*`) and B turns closed captions on or off. Roku does not document how A/B reach apps; if they ever stop working, press them while watching the debug console (`telnet ROKU_IP 8085`): SBWatch prints the key name of any key it does not recognize.
- The stream info panel hides itself after 15 seconds.
- The help line at the bottom of the main screen changes with context (categories, channels, Favorites, program guide, moving a channel).
- Search dialog: **Search channels**, **Search program guide (current channel list)**, **Rebuild channel search index** (Back closes the dialog). If the index file is found to be incomplete, SBWatch rebuilds it once per session and re-runs the search. An empty channel search reports how many channels are indexed and whether the index is incomplete.
- Search index: fetched category by category (progress top right) and stored as small verified files in the Roku's cache (or temporary storage if the cache is unusable); old index files are wiped before each rebuild. Refreshed every ~3 days. The index code is generic (`live` / `vod` / `series`).
- Guide data comes from Xtream `get_short_epg`, per channel, cached 5 minutes. There is no provider-wide guide search (Xtream has none, and full XMLTV is too large for a Roku).
- Stream resolution is shown only if the stream's playlist declares it; Roku does not expose decoder resolution to apps.
- The category filter is remembered across restarts (clear it from the filter dialog).
- Favorites can be reordered from the Favorites list (`*`); the order is saved immediately.
- Favorites and recently watched are stored in the Roku registry (about 20 KB, roughly 200 favorites with logos). The registry survives upgrading the sideloaded app, so they are kept across versions; only removing the app from the Roku clears them. Older saved formats are still read, and settings saved under the app's earlier name are picked up automatically.

## Layout
    manifest            Roku manifest
    source/             main.brs, utils.brs (shared helpers)
    components/         scene, guide, search, tasks, list items
    images/             channel icon
    build.sh            builds dist/SBWatch.zip

## Development
`python3 tools/lint.py` runs a structural check (balanced blocks, undefined functions, reserved words used as variable names). `./build.sh` builds `dist/SBWatch-v<version>.zip`.

## Arabic text
Roku has no Arabic glyphs and does not join or reorder right-to-left text. SBWatch shapes Arabic itself (letter joining, right-to-left order, mixed Arabic / English lines) and draws it with a trimmed copy of the **DejaVu Sans** font (76 KB, see `fonts/README.txt`). It applies to titles in lists, the guide, the details screen and the info panels. DejaVu Sans is distributed under its own free license (`fonts/LICENSE-DejaVu.txt`).

## Credits
Written by Claude (Anthropic) with the repository owner, who directed the project and tested it on hardware.

Provider and trademark names belong to their owners. Use SBWatch only with content you are authorized to access.
