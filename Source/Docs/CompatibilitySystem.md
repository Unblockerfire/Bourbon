# Installer Compatibility System

Bourbon runs all imported Windows apps through `CompatibilityManager` before launching Wine.

The flow is:

1. `InstallerDetectionService` inspects the file extension, PE metadata, and installer signature strings.
2. `CompatibilityManager` builds a `CompatibilityContext` for the bottle and asks registered rules for a strategy.
3. A `CompatibilityStrategy` may prepare a safer launch target, such as extracting an embedded app payload.
4. `Wine.runProgram` launches the returned `CompatibilityLaunchPlan`.

Launch code should not contain application-specific workarounds. Add future compatibility behavior by registering
new `CompatibilityRule` values in `CompatibilityRuleRegistry.defaultRules`, or by feeding the same registry from a
local or remote compatibility database later.

Current built-in rule:

- `embedded-electron-archive`: detects Electron installers with embedded `app-64.7z` or `app-32.7z` payloads, extracts
  them into the bottle compatibility cache, and launches the real executable from the extracted app folder.

Prepared payloads are cached under each bottle:

```text
<Bottle>/BourbonCompatibilityCache/<installer-name-size-modified>/
```

This keeps workaround artifacts isolated to the same bottle model that already owns Windows settings, registry,
dependencies, and app files.

