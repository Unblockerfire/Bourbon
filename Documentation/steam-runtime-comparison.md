# Disposable Steam runtime comparison

This procedure is for an affected Intel Mac only. It does not touch a Bourbon
bottle, BourbonWine installation, or any production service.

1. Copy the current BourbonWine runtime and the untouched original Gcenx
   `wine-devel-11.16-osx64` bundle to two separate, read-only locations.
2. Create two new, explicitly disposable prefixes outside `~/Library`:
   `~/Desktop/BourbonWine-Steam-Compare-current` and
   `~/Desktop/BourbonWine-Steam-Compare-gcenx`.
3. For each engine, use the same SteamSetup.exe, `WINEPREFIX`, Windows version,
   command arguments, and captured stdout/stderr. Do not set Bourbon app
   compatibility overrides.
4. Record `wine --version`, engine bundle hash, host architecture, Wine process
   table, and the first WineDbg/stack-overflow output. Redact home-directory
   components before sharing logs.
5. Compare only the resulting crash boundary. Do not replace BourbonWine or
   upload either engine as part of this experiment.

Interpretation: matching failures implicate the upstream/macOS Wine boundary;
a BourbonWine-only failure implicates packaging/configuration; a Bourbon-only
failure implicates managed bottle or launch configuration.
