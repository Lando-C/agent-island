# Third Party Notices

Agent Island includes small adapted source-code portions from permissively licensed
open-source projects.

## DevIsland

- Repository: https://github.com/nangchang/DevIsland
- License: MIT
- Copyright: Copyright (c) 2026 nangchang
- Used/adapted portions:
  - notch display center calculation using `NSScreen.auxiliaryTopLeftArea` and
    `NSScreen.auxiliaryTopRightArea`
  - `NSScreen.displayId` helper
  - collection behavior pattern for all-spaces/full-screen auxiliary notch panels
  - iTerm2 and Terminal exact `windowID + tabIndex` targeting before TTY/title
    fallback
  - cmux tab/terminal AppleScript targeting
  - WezTerm GUI socket enumeration before pane activation

MIT license text from DevIsland:

```text
MIT License

Copyright (c) 2026 nangchang

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## pi-island

- Repository: https://github.com/phun333/pi-island
- License: MIT
- Copyright: Copyright (c) 2026 phun333
- Used/adapted portions:
  - `NSPanel.constrainFrameRect(_:to:)` no-op strategy for deliberate placement
    in the macOS menu-bar/notch area
  - native host placement principles using `.statusBar` level

MIT license text from pi-island:

```text
MIT License

Copyright (c) 2026 phun333

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## agentbro

- Repository: https://github.com/shirenchuang/agentbro
- License: Apache-2.0
- Used as architecture/product reference only in this version. No source file
  from agentbro is currently copied into Agent Island.

## Ping Island

- Repository: https://github.com/erha19/ping-island
- License: Apache-2.0
- Copyright: Copyright 2026 Ping Island contributors
- Adapted portions:
  - persistent Codex app-server/broker JSON-RPC response routing
  - `item/tool/requestUserInput` answer payload shape
  - command, file, and permission approval result boundaries

The upstream Apache-2.0 license is available at:
https://github.com/erha19/ping-island/blob/main/LICENSE

Upstream NOTICE preserved for the adapted portions:

```text
Ping Island
Copyright 2026 Ping Island contributors

Ping Island is an independent project. It draws inspiration from
claude-island by Farouq Aldori, but it is not a full fork or a verbatim
derivative of that project.
```

## Vibe Notch

- Repository: https://github.com/farouqaldori/vibe-notch
- License: Apache-2.0
- Used as architecture/product reference in this version. Candidate modules for
  future direct adaptation include hook socket handling, session state, chat
  history, terminal visibility, tmux target matching, sound selection, and notch
  geometry. No source file from Vibe Notch is currently copied into Agent Island.

## Research-only References

The following projects are kept in the local research directory but should not be
copied into Agent Island mainline unless license compatibility is confirmed:

- BoringNotch, GPL isolated reference.
- MioIsland, no license file present in the local snapshot.
