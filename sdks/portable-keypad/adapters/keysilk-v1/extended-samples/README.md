# KeySilk Extended Samples

This directory stores factory-compatible extended-record samples.

Generate a sample after using the factory app to download a setting to the
device, then reading the config back:

```powershell
node tools\keysilk-cli.js read analysis\factory_after_download.bin
node tools\keysilk-cli.js extended-sample analysis\factory_after_download.bin scene2_key2_a
```

Each JSON file records non-empty `extended.*` records found in the raw config.
These samples are used to learn how to create missing extended records without
depending on the factory app.
