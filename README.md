# Lafz Prompter for macOS

An always-on-top teleprompter that sits under the MacBook notch, with first-class
Urdu support.

## Features
- Always on top, under the notch
- Hidden from screen recordings (optional)
- Urdu scripts set in Nastaliq automatically (Jameel Noori Nastaleeq or Noto
  Nastaliq Urdu, if installed), with any installed font selectable
- Voice activation that only uses the mic while you are presenting
- Global shortcuts: Control-Option-P play/pause, Control-Option-H show/hide,
  Control-Option-arrows for speed and scrolling
- Customizable speed, size, alignment, fades, and position
- Multi-monitor support

## Why this exists
NotchPrompter was released under the MIT License until May 2026, when its
license changed to personal, non-commercial use only. Lafz Prompter continues
from the last MIT-licensed version (commit `3602155`), so it stays free and open
source for everyone, including for commercial use.

## Install
Download the zip from [Releases](https://github.com/waqaskhan137/lafz-prompter/releases/latest)
or [lafz.waqasrana.space](https://lafz.waqasrana.space) and drag the app into Applications.
It is not signed with an Apple Developer ID, so the first time, right-click it and choose
Open (or allow it in System Settings, Privacy & Security).

## Build
Needs Xcode or the Xcode command line tools.

```sh
scripts/build-app.sh   # writes build/Lafz Prompter.app and build/LafzPrompter.zip
```

The website lives in `website/` and builds into `docs/` for GitHub Pages.

## Credits
Lafz Prompter is based on [NotchPrompter](https://github.com/jpomykala/NotchPrompter)
by Jakub Pomykala, from the version released under the MIT License. It is not
affiliated with or endorsed by NotchPrompter.

Global shortcuts use [HotKey](https://github.com/soffes/HotKey) by Sam Soffes
(MIT License).

## License
MIT. See [LICENSE](LICENSE).
