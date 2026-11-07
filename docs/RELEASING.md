# Releasing Catarina

The branch model is `develop` -> `release/x.y.z` -> `master`. Feature branches
target `develop`; `master` is the source of truth and the only branch that gets
release tags.

## Prepare the release branch

```sh
git switch develop
git pull origin develop
git switch -c release/0.2.1
```

On the release branch:

1. Bump `project(catarina VERSION ...)` in `CMakeLists.txt`.
2. Add the matching `<release version="..." date="...">` entry to
   `packaging/io.github.guilhermelcosta.Catarina.metainfo.xml`.
3. Set `tag:` in `packaging/io.github.guilhermelcosta.Catarina.yml` to the new
   tag (`v0.2.1`). Leave `commit:` out of the repository copy; Flathub reviewers
   require it in the submission copy.
4. Update `README.md` or `packaging/FLATHUB.md` only when their facts changed.
5. Run:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure
appstreamcli validate --no-net packaging/io.github.guilhermelcosta.Catarina.metainfo.xml
desktop-file-validate build/io.github.guilhermelcosta.Catarina.desktop
```

Commit and push:

```sh
git add CMakeLists.txt packaging README.md
git commit -m "chore(release): 0.2.1"
git push -u origin release/0.2.1
```

CI runs on the release branch and opens a draft pull request to `master`. Mark
it ready only after the release notes and the checks are final.

## Tag and release

When the release pull request is merged, `.github/workflows/release.yml` verifies
the version in `CMakeLists.txt` and the metainfo file, creates `vX.Y.Z` on
`master`, and opens the GitHub release.

`master` requires signed commits. Use the GitHub **squash** merge for the
`release/x.y.z` pull request (GitHub signs the squash commit), or sign the
release commits locally with `git commit -S`. A local unsigned merge into
`master` is blocked by the ruleset.

If the first release needs a manual start, run the workflow by hand:

```sh
gh workflow run release.yml -f version=0.2.1
```

A tag is never reused and never force-pushed. If the source changes after a tag,
cut a new patch release.

## After the release

Merge `master` back into `develop` so the next feature branch starts from the
released code.

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
