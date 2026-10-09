# Governance

How decisions get made and how changes land in BEER.

## Roles

- **Maintainer** — [@JarJarJames](https://github.com/JarJarJames), on behalf of Widukind Technologies LLC. Has final say
  on scope and direction, and is currently the **only** person who can approve and
  merge pull requests into `master`. Reviews contributions but is stepping back
  from day-to-day development (see the README "Project status").
- **Contributors** — anyone who opens issues or pull requests. Contributions are
  welcome from everyone; see `CONTRIBUTING.md`.
- **Senior maintainers** — experienced developers granted review/merge rights
  over time (see below). The project is actively looking for them.

## How changes land

- `master` is **protected**. All changes go through a pull request — including the
  maintainer's own.
- Every PR requires approval from a code owner (the maintainer) before it can
  merge. **Force-pushes and branch deletion on `master` are disabled.**
- Contributors cannot self-merge. Open a PR and request review.

## Becoming a senior maintainer

This project needs hands more than it needs gatekeeping. The path is informal and
merit-based:

1. Land a few solid, well-tested PRs (bug fixes or cleanup of the AI-generated
   cruft are the fastest way to build trust).
2. Show good judgment in reviews and issues.
3. Open an issue expressing interest (or comment on one you've contributed to).

Senior maintainers get added to `CODEOWNERS` and granted the ability to review and
merge. The aim is to grow a small group who can keep BEER moving without the
original author in the loop.

## Releases

- Versions are tagged `vX.Y.Z` (loose semantic versioning).
- A release is built with `./scripts/build_app.sh <version>` (compiles, bundles
  the CloudSync helper, ad-hoc signs, zips) and published via
  `gh release create` with the `BEER.zip` attached.
- Builds are not notarized; release notes must include the
  `xattr -dr com.apple.quarantine /Applications/BEER.app` step.

## Decisions & scope

Direction is decided in issues and PR discussion, with the maintainer (and, in
time, senior maintainers) making the call. Big or risky changes — anything
touching saves, Steam auth, or the runtime — should be proposed in an issue first
so the approach can be agreed before code is written.
