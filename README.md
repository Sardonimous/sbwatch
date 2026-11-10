# SBWatch

An Xtream Codes live-TV client for Roku (BrightScript / SceneGraph), built for personal use and sideloading in developer mode.

SBWatch is only a player. You supply your own Xtream provider; no content or credentials are included in this repository.

## Features
- Xtream login (server URL, username, password), saved on the Roku
- Categories with a name filter; channels load per category, so 30,000-channel providers stay within Roku memory limits
- Channel logos next to channel names (list, guide, now/next panel, playback banner)
- Now/next panel with colour-coded, scrollable programme cards
- Full time-grid guide (fetched lazily for the visible rows only)
- Search: whole-provider channel search (on-device name index) and programme-title search in the open channel list
- Favorites and recently watched
- HLS playback with automatic MPEG-TS fallback; stream "nerd" info panel

## Install (developer mode)
1. On the Roku: Home x3, Up x2, Right, Left, Right, Left, Right -> enable developer mode, set a web password, note the IP.
2. Build the package: `./build.sh` (creates `dist/SBWatch.zip`).
3. Browse to `http://ROKU_IP`, log in (user `rokudev`), upload `dist/SBWatch.zip`, click Install.
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
| Category list | first row | Search; second row: filter categories (Replay also opens the filter) |
| Channel list | `*` | add / remove favorite |
| Channel list | Replay | open the full guide |
| Guide | Left/Right, Up/Down | programme / channel; OK watch; Rewind/FF page; Replay = now; `*` favorite; Back close |
| Watching | Up / Down | previous / next channel |
| Watching | Left | open the guide |
| Watching | Replay | playback menu (guide, stream info, favorite, force HLS/TS) |
| Watching | `*` | the Roku system Options menu (captions, audio) |

Closed captions: turn them on in the Roku Options menu (`*` while watching) or Settings > Accessibility > Captions. They work when the stream carries CEA-608/708 captions or HLS WebVTT subtitles.

## Notes
- Search index: built in the Roku cache, category by category (progress top right), refreshed every ~3 days. The index code is generic (`live` / `vod` / `series`).
- Guide data comes from Xtream `get_short_epg`, per channel, cached 5 minutes. There is no provider-wide guide search (Xtream has none, and full XMLTV is too large for a Roku).
- Stream resolution is shown only if the stream's playlist declares it; Roku does not expose decoder resolution to apps.
- Favorites are stored in the Roku registry (about 20 KB), roughly 200 channels with logos.

## Layout
    manifest            Roku manifest
    source/             main.brs, utils.brs (shared helpers)
    components/         scene, guide, search, tasks, list items
    images/             channel icon
    build.sh            builds dist/SBWatch.zip

Provider and trademark names belong to their owners. Use SBWatch only with content you are authorized to access.
