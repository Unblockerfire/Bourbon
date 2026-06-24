# PROTECTRED Backup

This folder exists so the Whisky Reboot work can be restored after a machine reset.

The source tree is committed at the repository root. The generated WhiskyWine runtime
archive is too large for GitHub as a single file, so it is stored here in split parts:

```text
PROTECTRED/SikarugirWhiskyWine/Libraries.tar.gz.part-aa
PROTECTRED/SikarugirWhiskyWine/Libraries.tar.gz.part-ab
PROTECTRED/SikarugirWhiskyWine/Libraries.tar.gz.part-ac
PROTECTRED/SikarugirWhiskyWine/Libraries.tar.gz.part-ad
```

To restore the archive after cloning:

```sh
PROTECTRED/SikarugirWhiskyWine/reassemble-libraries.sh
```

That recreates:

```text
build/SikarugirWhiskyWine/Libraries.tar.gz
```
