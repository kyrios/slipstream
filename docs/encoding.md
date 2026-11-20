# The ProRes intermediate

What Slipstream makes of a ProRes file dropped into the upload center, why, and what it
measured. The numbers live in `Sources/DropCore/Plan.swift` and `Transcoder.swift`; this page
carries their reasons. The Funkhaus design record decided them (its ADR-0007, §7 and §8); the
rate above 30 fps follows YouTube's upload recommendation (decided 2026-11-20).

## Why an intermediate

4K ProRes 422 HQ is about 5 GB a minute: too big to upload. Slipstream encodes it on the Mac
before the upload, into an HEVC file that is only the ladder's source: the server makes every rung
from it, 4K at `ultrafast` in stage 1 and `slower` in stage 2, as from any master. The Funkhaus
also sends it to YouTube as the master. No reader of the site gets it, and it is not archived.
The ProRes on the Mac stays the only source for encoding the video again.

**The rules**: the 4K rung made from the intermediate scores at most 1 VMAF point
below the 4K rung made from the ProRes, both against the ProRes, with `vmaf_4k_v0.6.1`. And the
intermediate meets YouTube's recommended upload rate for SDR 2160p: 35 to 45 Mbit/s at 24, 25
and 30 fps, 53 to 68 at 48, 50 and 60 fps
([YouTube Help, "Recommended upload encoding settings"](https://support.google.com/youtube/answer/1722171),
read 2026-11-20). The Funkhaus checks a master against the lower end.

## What comes out

| | value | why |
|---|---|---|
| Video | HEVC Main 10, tagged `hvc1`, 4:2:0 10-bit, VideoToolbox | the media engine: about the same time at any rate, so the rate buys quality and costs only bytes |
| Rate | 50 Mbit/s average up to 30 fps, 70 Mbit/s above 30.5 fps (48, 50, 59.94, 60); no peak limit; the same for every size | 50 lost 0.8 VMAF in the 4K rung on the alpaca clip, 40 lost 1.2 (see "Measured"); 70 clears 68, the top of YouTube's range above 30 fps; 29.97 and 30 stay at 50 |
| Size | the source's, scaled into 3840×2160 only when larger, never up; portrait turns the box | the server's `fit()`, the same rounding: 4096×2160 becomes 3840×2024 |
| Frames | the source's frame rate and timestamps, every frame kept | |
| Key frames | every 4 seconds at most | |
| Colour | the source's primaries, transfer and matrix, all three or none | Final Cut writes Rec. 709 (1-1-1); a missing tag is not invented |
| Audio | the first audio track, AAC-LC stereo 48 kHz 256 kbit/s; mono becomes two equal channels | the server takes `0:a:0` |
| Container | MP4, `moov` before `mdat` (fast start) | |

Timecode and other tracks are dropped. The file is read back and checked before the page may
upload it: playable by AVFoundation, `hvc1`, Main 10, the index in front, the source's length
within one frame, audio where the source had some. Until then it lives in a temporary folder.

10 minutes of 4K are 3.8 GB at 50 Mbit/s, about 35 s of upload at 1 Gbit/s, and 5.3 GB at
70 Mbit/s, about 50 s; a 30-minute video (11 GB, or 16 GB above 30 fps) still fits the 28 GiB
the server holds for uploads in flight. The Mac asks for the source's size, an eighth of it for
the intermediate and 1 GiB before it takes a ProRes file (`ProResJobs.roomNeeded`); an eighth
holds the intermediate of 4K ProRes 422 at either rate.

## Where it runs

In its own process, `Contents/Helpers/slipstream-cli --progress-json`, at `nice 19`
(`ProcessEncoder`), like every encode Slipstream runs. One at a time. The pause and the CPU
limits of the settings do not apply: the user waits for it, and it runs on the media engine.

## Measured

On a Mac Studio (M2 Max, Homebrew ffmpeg's `hevc_videotoolbox`,
libvmaf, 2026-10-26). The clip: 10 s of 4K30 iPhone footage (HLG), made into ProRes 422 HQ.
The 4K rung: x265 `slower` CRF 29, `vbv-maxrate=5000:vbv-bufsize=10000`.

| intermediate | encode for 10 s | 10 minutes | 4K rung from it, VMAF 4K / default | lost |
|---|---|---|---|---|
| none: the rung from the ProRes | — | — | 89.6 / 79.5 | — |
| VideoToolbox 20 Mbit/s | 4.2 s | 1.5 GB | 86.1 / 73.8 | 3.4 / 5.7 |
| VideoToolbox 40 Mbit/s | 5.2 s | 3.1 GB | 88.4 / 77.6 | 1.2 / 2.0 |
| **VideoToolbox 50 Mbit/s** | **4.0 s** | **3.8 GB** | **88.8 / 78.4** | **0.8 / 1.2** |
| VideoToolbox 60 Mbit/s | 4.4 s | 4.6 GB | 89.2 / 79.0 | 0.4 / 0.6 |
| VideoToolbox 80 Mbit/s | 4.4 s | 6.1 GB | 89.4 / 79.3 | 0.2 / 0.3 |

`bin/test-encode` through Slipstream's own encode (synthetic 4K25 ProRes 422 HQ, 60 s,
788 Mbit/s, testsrc2 with grain, Rec. 709, PCM stereo, timecode), Apple M2 Max, macOS 26.5.1,
2026-10-26, with the Mac at a load of about 80 from other encodes: **25.2 s for 60 s of 4K**;
the file has 49.9 Mbit/s (video 49.65, audio 0.25), 374 MB, 1500 frames, `hvc1` Main 10,
bt709 ×3, boxes `ftyp moov mdat`, 60.000 s; AVFoundation plays it and decodes its first and
last frame.

Above 30 fps, `slipstream-cli` on a synthetic 4K59.94 ProRes 422 HQ (10 s, testsrc2 with grain,
Rec. 709, PCM stereo), Apple M2 Max, macOS 27.2, 2026-11-20, load about 8: **12.2 s for 10 s of
4K**; the file has 69.1 Mbit/s (video 68.9, audio 0.17), 86 MB, 600 frames, `hvc1` Main 10.

**The first real export decides**: `bin/rungs.zsh` runs the table above on it.
If the rung from the intermediate loses more than 1 point at 50 Mbit/s, the rate up to 30 fps
goes to the first of 60 and 80 that passes, here and in `Plan.swift`. A warning sign: on a 2-s ProRes 422 HQ
clip of 4K footage (M2 Max, 2026-10-26, when `bin/rungs.zsh` was added) 50 Mbit/s lost 1.37
points and 80 Mbit/s 0.68; two seconds are too short to decide on.

The ProRes Drop delivery encode (5 Mbit/s, remuxed as the 4K rung) is gone: on the alpaca
clip it scored PSNR-Y 29.8 dB and SSIM 0.840, against 32.9 dB and 0.912 for x265 `slower`.
