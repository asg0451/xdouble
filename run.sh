#!/bin/bash
set -euo pipefail
rm -rf /Users/miles/Library/Developer/Xcode/DerivedData/xdouble-* # clean
xcodebuild -scheme xdouble build
open /Users/miles/Library/Developer/Xcode/DerivedData/xdouble-*/Build/Products/Debug/xdouble.app
