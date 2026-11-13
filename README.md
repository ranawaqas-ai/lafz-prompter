# Lafz Prompter for macOS

An always-on-top teleprompter that sits under the MacBook notch and also displays
Urdu in Nastaliq.

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
license changed to personal non-commercial use only. Lafz Prompter continues
from the last MIT-licensed version (commit `3602155`), so it stays free and open
source for everyone, including for commercial use.

## Install
Download the zip from [Releases](https://github.com/ranawaqas-ai/lafz-prompter/releases/latest)
or [lafz.waqasrana.space](https://lafz.waqasrana.space) and drag the app into Applications,
or install it with Homebrew:

```sh
brew install --cask ranawaqas-ai/tap/lafz-prompter
```

The app is signed with a Developer ID and notarized by Apple, and it updates itself.

## Build
Building requires Xcode or the Xcode command line tools.

```sh
scripts/build-app.sh   # writes build/Lafz Prompter.app and build/LafzPrompter.zip
```

The build is signed ad hoc unless `SIGN_IDENTITY` names a Developer ID certificate.
With `NOTARY_PROFILE` also set to a `notarytool` keychain profile, it is notarized
and stapled.

The website lives in `website/` and builds into `docs/` for GitHub Pages.

## Credits
Lafz Prompter is based on [NotchPrompter](https://github.com/jpomykala/NotchPrompter)
by Jakub Pomykala, from the version released under the MIT License. It is not
affiliated with or endorsed by NotchPrompter.

Global shortcuts use [HotKey](https://github.com/soffes/HotKey) by Sam Soffes,
and updates use [Sparkle](https://sparkle-project.org) (both MIT License).

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md). Pull requests need the
[Contributor License Agreement](CLA.md), which a check asks you to sign once.

## License
GNU General Public License version 3 or later. See [LICENSE](LICENSE) and
[NOTICE](NOTICE). Versions 1.0 to 1.2 were released under the MIT License, and
code that comes from NotchPrompter keeps its MIT notice in NOTICE.
