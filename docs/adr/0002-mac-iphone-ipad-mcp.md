# 2. Mac, iPhone, iPad and MCP from one core

Date: 2026-11-04 · Status: accepted

The owner wants the app everywhere and Claude as a first-class way in. One Swift package (FujiKit) drives the camera
(ImageCaptureCore works on macOS and on iPhone/iPad over USB-C), the library, history and inbox; `Shared/` SwiftUI
serves Mac and iOS; `fuji mcp` exposes the same operations to agents. iPad at regular width uses the Mac layout.
Distribution: GitHub (DMG + auto-update, one-line installer); no App Store for now (trademark, review, warranty
stance of Fujifilm).
