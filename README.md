# Drive Stats

A Mac app that shows how full your disks are, tracks it over time, finds what's using the space, and suggests what to delete.

- **Overview**: available, used, and purgeable space for each disk, plus a chart of startup disk usage over time. While the app is open it records a snapshot at most once an hour, in `~/Library/Application Support/Drive Stats/history.json`.
- **Explore**: scan your home folder, the whole disk, or any folder, then drill into folders by size.
- **Recommendations**: caches, Xcode leftovers, project build folders (`node_modules`, `.build`, `target`, `.venv`, and more), installers, old downloads, large files you haven't opened in 3 months, and apps you haven't opened in 6. Each one is labeled Safe to delete, Rebuildable, or Review first. Selected items go to the Trash, so you can put them back.
- **Downloads**: sorts what's in Downloads into things easy to download again (installers, apps, zipped apps, archives already unzipped), things to look at, and things to keep (photos, documents, and anything from email, judged by the download metadata macOS saves). Only the first group comes pre-selected.
- **Trash**: how much is in the Trash and what's biggest, with a button that asks Finder to empty it.

## Build and run

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
./build.sh            # builds build/Drive Stats.app
./build.sh --install  # also copies it to /Applications
```

Give it Full Disk Access (System Settings ▸ Privacy & Security ▸ Full Disk Access). Without it, macOS asks for permission folder by folder during a scan, and some folders can't be read.

The build is signed ad hoc, so macOS may forget the Full Disk Access grant after each rebuild. To keep it, set `DRIVESTATS_TEAM` to your Apple Developer team ID; `build.sh` then signs with your Apple Development certificate.

## Tests

```sh
./test.sh
```

The rules for what to suggest live in `Sources/Core/Recommender.swift`. The scanner, recommender, and history store in `Sources/Core` have no UI dependencies and are what the tests cover.

The app icon is drawn in code: `swift make-icon.swift Sources/App/Assets.xcassets/AppIcon.appiconset`.
