# Greenhouse

SwiftUI + Core Data + CloudKit sharing. Two people in one household, separate
Apple IDs, installed through TestFlight. Releases are small and frequent; use
the `point-release` skill for each one.

## This repo is public

Never commit API keys, real household data (ZIP codes, photos, names), or
anything from the household's devices, tests included. Tests use public
reference ZIPs (84043, 84101).

## Commands

| What | Command |
|---|---|
| Checks (xcodegen + unit tests on a simulator) | `~/.claude/skills/ship/scripts/checks.sh` |
| Debug build on the plugged-in iPhone | `./install.sh --launch` (phone unlocked) |
| Wait for the CloudKit schema upload | `scripts/schema-status.sh` |
| Archive + upload to TestFlight | `scripts/testflight.sh` (build number = timestamp) |
| Version | `MARKETING_VERSION` in `project.yml` |

## Model changes need a schema deploy

The model is built in code (`Model/GreenhouseModel.swift`). Any new entity,
attribute or relationship changes `GreenhouseModel.fingerprint`, and then:

1. `./install.sh --launch`, with the phone unlocked and the app opened. The
   debug build uploads the Development schema.
2. `scripts/schema-status.sh` until it reports the new upload.
3. The owner deploys Development → Production in the CloudKit Console
   **before** anyone installs the TestFlight build.

Every attribute must be optional or have a default, and every relationship
optional with an inverse (CloudKit rules, see the header of GreenhouseModel).
No model change → no deploy step, so say so in the release report.

## Gotchas learned the hard way

- **Rows must observe what they show.** A row that displays a related object
  (photo, milestone, project) takes it as `@ObservedObject`, and plant views use
  `.redrawsOnRelatedChanges(plant)` (extend its type list for new related
  entities). Otherwise edits show stale text until the page is rebuilt (v1.2.1,
  v1.3.10).
- **Don't put `.toolbar`/`.onChange` on a List `Section`.** A section applies
  its modifiers to the header and each row separately, so a keyboard Done
  button showed up twice (v1.3.11). Attach them to the field itself.
- **Forms set `@State` in `init`**, not `onAppear`, or date pickers show stale
  dates.
- **Navigation:** in a NavigationStack, don't mix `NavigationLink(destination:)`
  with value links pushed on top of it. Use value links + `navigationDestination`
  for anything that links onward (v1.3.4).
- **Never derive persistent UI from set order or "oldest/newest" on the fly.**
  Store the choice (`coverPhotoID`) and break sort ties by uuid, or it drifts
  between launches and phones (v1.3.8).
- **Simulator screenshots need a signed build** (`-allowProvisioningUpdates
  -derivedDataPath .build/SimSigned`); a `CODE_SIGNING_ALLOWED=NO` build crashes
  in CloudKit at launch. Launch with `-demoData YES -openTab N`. The simulator
  can't drive into detail pages, so say which screens weren't seen.
- **Brand-new ZIPs** aren't in the USDA map, CLGeocoder or zippopotam; the
  "Use my location" fallback is what works.
- **Words:** the user-facing word is "Combine", never "staple" (the code still
  says `staple`). Split is no longer offered (v1.3.9); cuttings replace it.
