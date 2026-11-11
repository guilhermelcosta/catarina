# Releasing Catarina

The branch model is `develop` -> `release/x.y.z` -> `master`. Feature branches
target `develop`; `master` is the source of truth and the only branch that gets
release tags.

## The proposal opens itself

Every push to `develop` runs `.github/workflows/release-proposal.yml`, which
keeps exactly one open pull request from `release/x.y.z` to `master`:

- the branch is cut from `master`, with `develop` merged into it;
- the patch version is bumped in `CMakeLists.txt`, in the metainfo and in the
  Flatpak manifest;
- the notes list the commits since the last tag;
- the body lists `Closes #N` for the issues resolved by the pull requests merged
  into `develop` since the last tag.

Nothing closes on `develop`. The issues close when the proposal merges into
`master`, which is the default branch and the moment the code is released.

The version is bumped on top of the merge, never before it, so the version line
never conflicts between `master` and `develop`.

A push to `develop` only refreshes the notes in the body. It does not merge
`develop` into the release branch, because that push would rebuild the same tree
a second time. The body says how far behind the branch is. To bring it up to
date, run the workflow by hand with `refresh` enabled; merging without it
releases the tree as it stands.

## One-time setup

The workflow needs a token that can trigger other workflows. A pull request
opened with `GITHUB_TOKEN` does not start CI, so its required checks would never
run and the merge would stay blocked.

1. Create a fine-grained token at
   <https://github.com/settings/personal-access-tokens/new> for this repository
   with `Contents: read and write`, `Pull requests: read and write` and
   `Workflows: read and write`.
2. Save it as the repository secret `RELEASE_TOKEN`.

`Workflows` is required because the release branch can carry changes under
`.github/workflows`. Without it the push fails with a permission error.

Without it the workflow fails immediately with a message instead of opening a
pull request that cannot be merged.

## Releasing

Open the proposal, read the diff and the notes, merge it. That is the whole
decision. `.github/workflows/release.yml` then verifies that the version agrees
in the three files, creates `vX.Y.Z` on `master`, and opens the GitHub release
with the notes from the pull request body, minus the `Closes` lines.

Close the proposal without merging to skip that release. The next push to
`develop` opens a new one.

The pull request is ready, not a draft: merging is the approval.

### Minor or major

Edit the branch before merging: rename it to `release/0.3.0`, set the same
version in `CMakeLists.txt`, add the metainfo entry, and set the Flatpak tag.
`release.yml` reads the version from the branch name, so both must agree.

### If it conflicts

The proposal merges `develop` into a branch cut from `master` when you run the
workflow with `refresh`. If the merge conflicts, the workflow stops and says so.
Resolve it on the branch, push, and the next run continues from there.

## Checks before merging

```sh
ctest --test-dir build --output-on-failure
appstreamcli validate --no-net packaging/io.github.guilhermelcosta.Catarina.metainfo.xml
desktop-file-validate build/io.github.guilhermelcosta.Catarina.desktop
```

CI runs the same commands on the branch push. A pull request from a branch in
this repository does not rebuild; its checks come from that push. Fork pull
requests run the same jobs in `pull-request.yml`, gated on the fork.

Any merge method is allowed and no signature is required. A squash merge keeps
`master` linear; the tag always points at the merge commit, and `release.yml`
refuses to tag if `master` moved in the meantime.

## After the release

Merging `master` back into `develop` is optional. It only brings the version
bump and keeps `git describe` accurate on `develop`; the next proposal computes
the next version from `master`, so nothing depends on it.

For the Flathub submission manifest, add the tag commit:

```sh
git rev-list -n 1 v0.2.1
```

Copy `packaging/io.github.guilhermelcosta.Catarina.yml` to the top level of the
`flathub/flathub` submission branch and add:

```yaml
        tag: v0.2.1
        commit: <output of git rev-list -n 1 v0.2.1>
```

## Hotfix

Cut `fix/<slug>` from `master`, open the pull request against `master`, merge it,
then merge `master` back into `develop`. The next regular release carries the
same history.

## Manual fallback

If the workflow is unavailable, do what it does by hand: branch from `master`,
merge `develop`, bump the three files, push, and open the pull request. A tag is
never reused and never force-pushed. If the source changes after a tag, cut a new
patch release.
