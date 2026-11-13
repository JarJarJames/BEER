# Governance

How decisions get made and how changes land in BEER.

## Roles

- **Maintainer** — [@JarJarJames](https://github.com/JarJarJames), on behalf of Saint Widukind Technologies LLC. Has final say
  on scope and direction, and is currently the **only** person who can approve and
  merge pull requests into `master`. Reviews contributions but is stepping back
  from day-to-day development (see the README "Project status").
- **Contributors** — anyone who opens issues or pull requests. Contributions are
  welcome from everyone; see `CONTRIBUTING.md`.
- **Senior maintainers** — experienced developers granted review/merge rights
  over time (see below). The project is actively looking for them.

## How changes land

- Work lands in **`dev`**. `master` holds released code; the maintainer merges
  `dev` into `master` when cutting a release.
- `master` is **protected**. All changes go through a pull request — including the
  maintainer's own.
- Every PR requires approval from a code owner (the maintainer) before it can
  merge. **Force-pushes and branch deletion on `master` are disabled.**
- Contributors cannot self-merge. Open a PR and request review.

## Becoming a senior maintainer

This project needs hands more than it needs gatekeeping. The path is informal and
merit-based:

1. Land a few solid, well-tested PRs (bug fixes, tests, or tidying code that
   doesn't yet follow `PROJECT_STRUCTURE.md` are the fastest way to build trust).
2. Show good judgment in reviews and issues.
3. Open an issue expressing interest (or comment on one you've contributed to).

Senior maintainers get added to `CODEOWNERS` and granted the ability to review and
merge. The aim is to grow a small group who can keep BEER moving without the
original author in the loop.

## Releases

- Versions are tagged `vX.Y.Z` (loose semantic versioning).
- **0.x releases go straight to stable.** Every 0.x version is already a
  pre-release, so there are no nightlies before 1.0.0.
- **A stable release:** merge `dev` into `master` with a merge commit (not a
  squash), move the `## Unreleased` changelog heading to `## X.Y.Z — <date>`,
  and tag `vX.Y.Z` on `master`.
- **From 1.0.0 on, every stable release has at least one nightly first.** A
  nightly is built from `dev`, tagged `vX.Y.Z-nightly.N` (N counts up from 1
  for each nightly of that version), and published as a GitHub
  **pre-release** that is not marked latest. Its notes open with a line saying
  it's a nightly and link the current stable release. The stable release
  follows once the nightly has been tested.
- Both kinds are built with `./scripts/build_app.sh <version>` (compiles,
  bundles the CloudSync helper, ad-hoc signs, zips) and published via
  `gh release create` with the `BEER.zip` attached. Add `--prerelease
  --latest=false` for a nightly. Put the zip's SHA-256 in the notes.
- **The version you pass to `build_app.sh` is the one BEER shows in its
  window title** ("BEER X.Y.Z"), so it must be the tag without the `v`. Leave
  it off and the script builds 0.2.0. Before publishing, check the built app
  says the right version:

  ```bash
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" .build/BEER.app/Contents/Info.plist
  ```
- Builds are not notarized; release notes must include the
  `xattr -dr com.apple.quarantine /Applications/BEER.app` step.

## Decisions & scope

Direction is decided in issues and PR discussion, with the maintainer (and, in
time, senior maintainers) making the call. Big or risky changes — anything
touching saves, Steam auth, or the runtime — should be proposed in an issue first
so the approach can be agreed before code is written.
