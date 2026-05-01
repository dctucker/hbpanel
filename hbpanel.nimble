# Package
version       = "0.1.0"
author        = "Casey Tucker"
description   = "HomeBridge panel"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
namedBin      = toTable {
                  "hb": "hb",
                  "cli/hbcli": "hbcli",
                  "gui/hbgui": "hbgui"
                }

# Dependencies
requires "nim >= 2.2.0"
requires "gtk2#head"
