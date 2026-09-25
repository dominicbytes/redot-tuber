# Third-party notices

Redot Tuber is a standalone project. It is inspired in part by the generic addon and OAuth architecture of [Kani's Twitcher](https://github.com/kanimaru/twitcher), via the Redot-oriented fork at [dominicbytes/twitcher](https://github.com/dominicbytes/twitcher). Redot Tuber is not endorsed by Kani, Twitch, YouTube, Google, Godot, or the Redot project.

The precise component dispositions and donor commit are recorded in `docs/lineage/twitcher-reuse.md`.

## Native YouTube stream helper

The standalone `redot-tuber-stream-helper` binaries include the Go 1.27.1 standard library and the exact Go modules pinned in `native/stream-helper/go.mod` and `go.sum`. Their license texts and the gRPC notice are shipped in `native/stream-helper/licenses/`:

| Component | Version | License file |
| --- | --- | --- |
| Go runtime and standard library | 1.27.1 | `GO-LICENSE.txt` (BSD-style) |
| `github.com/bufbuild/protocompile` | 0.14.1 | `PROTOCOMPILE-LICENSE.txt` (Apache-2.0) |
| `google.golang.org/grpc` | 1.84.0 | `GRPC-LICENSE.txt`, `GRPC-NOTICE.txt` (Apache-2.0) |
| `google.golang.org/protobuf` | 1.36.12 | `PROTOBUF-LICENSE.txt` (BSD-style) |
| `google.golang.org/genproto/googleapis/rpc` | 2026-07-06 snapshot pinned in `go.mod` | `GENPROTO-LICENSE.txt` (Apache-2.0) |
| `golang.org/x/net`, `x/sync`, `x/sys`, `x/text` | Versions pinned in `go.mod` | Corresponding `X-*-LICENSE.txt` (BSD-style) |

`native/stream-helper/stream_list.proto` is adapted from the [official YouTube Streaming Live Chat guide](https://developers.google.com/youtube/v3/live/streaming-live-chat). Google's sample code on that page is under the Apache 2.0 License, reproduced in `GRPC-LICENSE.txt`; the guide's prose is CC BY 4.0 and is linked rather than reproduced. This project is not endorsed by Google or YouTube.

## Twitcher MIT license

MIT License

Copyright (c) 2024 Kani

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
