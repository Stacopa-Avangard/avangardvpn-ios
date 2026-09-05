# Contributing to AvangardVPN for iOS

This app is open source so that anyone can check it does what it claims — in
particular, that the private key is generated on the device and never leaves it,
and that the client collects only what the in-app data disclosure screen says it
collects. Reading the source is the point; contributions are welcome on top of
that.

## Copyright and ownership of contributed code

Anything you submit to this project — code, documentation, graphics, anything —
is licensed under **GPL-3.0-only**. Submitting means you are the original author
of the whole contribution, and that you grant us the full right to use, publish,
change or remove all or part of it under the terms of GPL-3.0-only, at any time.

There is **no Contributor License Agreement**, and no copyright assignment. That
is deliberate, and it is the same shape Mullvad uses: the grant above is bounded
by the licence, so nobody is signing away ownership of their work.

⚠️ It also means the project cannot relicense your contribution outside GPL-3.0.
Anyone proposing to change the licence has to get every contributor's agreement,
or rewrite their parts. That is a known and accepted cost of not having a CLA.

## AI-assisted contributions

A human has to be behind every pull request and issue. Use whatever tools you
like to write the code, but you must have read your own change and be able to
answer questions about it. Submissions where no human was clearly in the loop
will be closed.

## What to expect

Which changes get merged is at our discretion and follows our own plans for the
app. Before a large change — a new feature, a refactor, anything structural —
open an issue first so the design can be agreed before you spend the time.

⛔ Some things in this repository look like oversights and are not. Three of them
were paid for once already. Read **"Four things that must not be fixed"** in
[`AGENTS.md`](AGENTS.md) before changing the Go version pin, the tunnel's build
destination, the device-test target, or how `xcodebuild` is invoked.

## Bugs versus support

File **bugs in the app's code** here in the issue tracker. Anything else —
connection problems, account questions, quota, billing, the servers themselves —
is not answerable from this repository, and belongs with support instead.

⚠️ **Never attach a real magic-link URL, session token, or account email to an
issue.** They are credentials. Redact them before pasting logs.

## Building it

[`README.md`](README.md) is self-contained, including the failure modes whose
error messages point somewhere other than the cause. Start with **"▶ Running it
on a real iPhone"**.

Two things that will otherwise cost you an afternoon: Go is pinned to **1.21**
and a newer one fails silently overnight rather than at build time, and the
wireguard-go bridge resolves `go` and `rsync` from **Xcode's** build PATH rather
than your shell's.
