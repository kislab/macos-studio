## OS Studio 1.8.5 — Mac maintenance

New section **Extras › Mac maintenance**:

- **Repair Spotlight & LaunchServices:** Rebuilds the LaunchServices database, resets the Spotlight index and restarts Dock, Finder and the menu bar. Helps with wrong “Open With” entries, missing icons or when Spotlight finds nothing.
- **Delete old Time Machine backups:** Lists the computers on a Time Machine drive (Mac OS Extended, folder `Backups.backupdb`) with their number of backups. After confirmation the selected computer is deleted, with progress and freed space. You can cancel between two backups.

Both tools run in Terminal with your admin password. Listing and deleting backups needs Full Disk Access for OS Studio and Terminal.

Universal for Intel and Apple silicon, macOS 13 or later. Build 55.
