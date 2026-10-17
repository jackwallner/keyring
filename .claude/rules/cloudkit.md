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
(creates `OwnerPhoto` and `PhotoReport`). Always launch through `open`, never the bare executable (Core Data's
CloudKit scheduler is unreachable from a shell process).

## Production
`initializeCloudKitSchema` does not create `cloudkit.share`; run `--verify-share` in Development before deploying,
or every real invite fails in Production with "Cannot create new type cloudkit.share". Public DB indexes needed:
`OwnerPhoto.modelKey` queryable, `OwnerPhoto.creationDate` sortable, `recordName` queryable on both. Deploy
Development to Production in CloudKit Console after any model change. Never reset Production.

## Sharing
One `CKShare` per garage, `publicPermission = .readWrite` so a link or QR joins anyone (contact-only invites fail when
the Apple ID differs from the address). `SharingService.waitForFirstExport` must finish before sharing.
