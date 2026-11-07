# Third-party notices

Private War is licensed under the GNU General Public License, version 3 or (at your option) any later version
(GPL-3.0-or-later); see `LICENSE`. This file lists the third-party code that is included in the repository or in the
Workshop addons built from it, with the licence of each part.

## binaryheap.lua

- Used in: `addons/privatewar/lua/privatewar/modules/bots_nav/third_party/binaryheap.lua` (gamemode addon).
- Upstream: <https://github.com/Tieske/binaryheap.lua>, version 0.4 (tag `version_0v4`, commit
  `579662c1ac47bec954f29195a1d5fd9b4d5f5cb6`).
- Licence: MIT/X11. The MIT licence is compatible with the GPL; the file keeps its original notice in its header.
- Changes: only the min-heap with unique payloads is kept, and the code is reformatted and annotated for the
  project's lint and type gates. The header of the file lists the changes.

```text
Copyright 2015-2018 Thijs Schreijer

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of
the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
```

## ARC9 integration

The ARC9 integration addon (`addons/privatewar-arc9/`) talks to the ARC9 weapon base only through ARC9's public Lua
API (its weapon tables, hooks and console variables) at run time. It includes no ARC9 code or assets; ARC9 must be
installed separately and keeps its own licence.

## Development tools (not shipped)

GLuaTest (<https://github.com/CFC-Servers/GLuaTest>, GPL-3.0) runs the test suite during development. `flake.nix`
fetches it as a flake input; no GLuaTest code is included in the repository or in the Workshop addons.
