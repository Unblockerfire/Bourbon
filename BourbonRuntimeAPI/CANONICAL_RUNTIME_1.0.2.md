# Canonical BourbonWine 1.0.2 deployment

Source artifact: the `bourbon-corrected-runtime-33564471567-1` artifact from
[macOS Validation run 33564471567](https://github.com/Unblockerfire/Bourbon/actions/runs/33564471567).
It was produced by the macOS 14 CI runtime preparation job using
`Scripts/prepare-diagnostic-runtime.sh` and must be copied byte-for-byte.

| Item | Value |
| --- | --- |
| Upload filename and R2 object key | `BourbonWine-1.0.2-macOS-x86_64.tar.gz` |
| Archive SHA-256 | `6e070803fb5d1f9f92152b82ec6a1dab4cb82bcc1bc719663dda4a492875fce8` |
| Runtime version | `1.0.2` |
| Wine version | `wine-11.16` |
| Manifest runtime version | `1.0.2` |
| Marker version | `1.0.2` |
| Version marker object key | `BourbonWineVersion-1.0.2.plist` |
| Version marker SHA-256 | `b3867feab175a8db79e6d1a4c355124d10a12cd47c44ff2bd32c8eede8edb3f0` |

The marker object is the unmodified `Libraries/BourbonWineVersion.plist`
extracted from that archive. The archive itself includes `Libraries/Wine/bin/wine`,
`Libraries/Wine/bin/wineserver`, `Libraries/Wine/lib/wine/x86_64-unix/ntdll.so`,
`Libraries/Wine/lib/libvulkan.1.dylib`, `Libraries/BourbonWineRuntime.json`, and
`Libraries/BourbonWineVersion.plist`.

After R2 credentials are provided, upload both objects, compare remote and local
SHA-256 values, then deploy this API configuration as one revision. The resulting
`/runtime/latest` response has this unsigned metadata shape (the two URLs are
short-lived R2 signed URLs):

```json
{
  "version": "1.0.2",
  "wineVersion": "wine-11.16",
  "archiveName": "BourbonWine-1.0.2-macOS-x86_64.tar.gz",
  "sha256": "6e070803fb5d1f9f92152b82ec6a1dab4cb82bcc1bc719663dda4a492875fce8",
  "plistUrl": "<signed URL for BourbonWineVersion-1.0.2.plist>",
  "archiveUrl": "<signed URL for BourbonWine-1.0.2-macOS-x86_64.tar.gz>",
  "expiresInSeconds": 300
}
```

Do not deploy this configuration until the matching R2 objects are present and
verified. Do not update production Bourbon release or update-channel metadata.
