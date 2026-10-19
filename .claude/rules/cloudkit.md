---
paths:
  - "Shared/Services/Persistence.swift"
  - "Shared/Services/SharingService.swift"
  - "Shared/Services/ShareInvite.swift"
  - "Shared/Services/CommunityPhotos.swift"
  - "Shared/Models/KeyringModel.swift"
  - "scripts/cloudkit-schema/**"
---
# CloudKit

## Schema tool
`scripts/cloudkit-schema` is a Mac app that compiles the real model and `ShareInvite`. It signs manually with the
"Keyring schema Mac dev" profile (created through the ASC API for Mac device `ZVSHJG3R5Q`), because Xcode has no
Apple ID session and API-key auth cannot mint Mac development profiles.

```sh
xcodegen generate --spec scripts/cloudkit-schema/project.yml
xcodebuild -project scripts/cloudkit-schema/KeyringCloudSchema.xcodeproj -scheme KeyringCloudSchema \
  -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/NativeCloudSchema -quiet build
open -W --stdout /tmp/keyring-schema.log build/NativeCloudSchema/Build/Products/Debug/KeyringCloudSchema.app --args --initialize-development
```

Flags: none (dry run), `--initialize-development`, `--verify-share` (creates `cloudkit.share`), `--public-types`
(creates `OwnerPhoto` and `PhotoReport`; the app stopped using both when community photos were removed on 2026-10-17). Always launch through `open`, never the bare executable (Core Data's
CloudKit scheduler is unreachable from a shell process).

## Production
`initializeCloudKitSchema` does not create `cloudkit.share`; run `--verify-share` in Development before deploying,
or every real invite fails in Production with "Cannot create new type cloudkit.share". Public DB indexes needed:
`OwnerPhoto.modelKey` queryable, `OwnerPhoto.createdTimestamp` sortable (deployed to Production 2026-10-16), `recordName` queryable on both. Deploy
Development to Production in CloudKit Console after any model change, before uploading a build that
writes the new fields (Production rejects unknown fields and the export stalls for everyone). Never
reset Production. `ServiceEntry.kindRaw` and `recallCampaign` were added and deployed to Production 2026-10-16 (build 4).
Added 2026-10-17 and deployed to Production the same day (build 5): Vehicle
`soldDate`, `soldPrice`, `auxMeterName`, `auxReading`, `auxReadingDate`, `storedSince`, `storedUntil`, `yearlyUse`;
MaintenanceTask `usesAuxMeter`; ServiceEntry `auxReading`; MeterReading `isAux`.
Fill-ups added 2026-10-17 and deployed to Production the same day (build 6): ServiceEntry
`fuelVolume`, `fuelUnitPrice`, `fuelGrade`, `fuelPartial`.
Enthusiast fields added 2026-10-19 and deployed to Production the same day (build 15): Vehicle `auxMeterRaw`,
`profileJSON` and the `documents` relation (Attachment `vehicle`); MaintenanceTask `auxInterval`, `triggerRaw`;
ServiceEntry `detailsJSON`; Attachment `name`; Valuation `kindRaw`. The schema tool timed out that day (cloudd's
requests to gateway.icloud.com hung), so they were added by hand in Console: a String attribute is `CD_<name>`
STRING plus `CD_<name>_ckAsset` ASSET, a Double is DOUBLE, a to-one relationship is `CD_<name>` STRING with no asset.
The schema tool compiles `VehicleProfile.swift` and `Format.swift` now; add any file the model starts to reference. `profileJSON` (`VehicleProfile`) and `detailsJSON` (`EntryDetails`) are JSON so new traits,
parts or measurement fields need no schema change; keep unknown values when decoding.

## Sharing
One `CKShare` per garage, `publicPermission = .readWrite` so a link or QR joins anyone (contact-only invites fail when
the Apple ID differs from the address). `SharingService.waitForFirstExport` must finish before sharing.
