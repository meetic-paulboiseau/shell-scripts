# Sync Artifacts Between Artifactory Instances

Simple POSIX shell script to sync non-SNAPSHOT artifacts (eg. `.tar.gz`) from a source Artifactory Storage API path to a destination Artifactory UI path.

---

## Quick usage

```sh
./sync-artifacts.sh \
  --source "https://source/artifactory/api/storage/repo/path" \
  --source-user "alice" \
  --source-token "<SOURCE_TOKEN>" \
  --dest "https://dest/ui/repos/tree/General/repo/path" \
  --dest-user "bob" \
  --dest-token "<DEST_TOKEN>" \
  --no-dry-run
```

Replace `<SOURCE_TOKEN>` and `<DEST_TOKEN>` with real tokens before running.

---

## Options

| Flag                           | Description                                              |
|--------------------------------|----------------------------------------------------------|
| --source                       | Source Artifactory Storage API URL (required)            |
| --dest                         | Destination Artifactory UI URL (required when uploading) |
| --source-user / --source-token | Source credentials (optional)                            |
| --dest-user / --dest-token     | Destination credentials (optional)                       |
| --output                       | Temp directory (default: `backup`)                       |
| --limit                        | Process only first N folders                             |
| --no-dry-run                   | Perform uploads (default is dry-run)                     |
| -h, --help                     | Show help                                                |

---

## Behavior

- Skips folders with `SNAPSHOT` (case-insensitive).
- Only files ending with `.tar.gz` are downloaded and considered for upload.
- By default the script runs in dry-run mode and prints upload targets.
- Prefer scoped tokens; avoid embedding long-lived credentials.

<details>
<summary>Example (with placeholders)</summary>

```sh
./sync-artifacts.sh \
  --source "https://artifact.meetic.ilius.net/artifactory/api/storage/php-local-packages/ilius/php-pay-dictionary" \
  --source-user "p.boiseau" \
  --source-token "<SOURCE_TOKEN>" \
  --dest "https://artifactory-dal.i.mct360.com/ui/repos/tree/General/e2p-php-composer/ilius/php-pay-dictionary" \
  --dest-user "n3m3s1s" \
  --dest-token "<DEST_TOKEN>" \
  --no-dry-run
```

</details>
