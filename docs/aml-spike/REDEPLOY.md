# Redeploy the AML spike from scratch

This is the source of the spoken demo and the chapter order. The build is `feat/aml-spike` in this repository. Do not treat a running host as the source of truth.

## Build

On a rocky9 Cloudberry engineering host, with the demo cluster already up:

```
./assemble.sh -b aml-spike-bom.yaml --run
```

Run one component with `-c <name>`. Do not re-run `amlsim` generate unless the bank should be replaced.

Signed pins:

- Cloudberry and PXF: `apache-cloudberry-pxf-2.2.0-incubating` and the Cloudberry 2.2.0-incubating source already used for the cluster
- Polaris 1.8.0
- Kafka 4.4.0 source
- Flink 2.1.3 source

Flink 2.1.3 was built with Apache Maven 3.10.0 on PATH. The release notes name 3.8.6. That exact pin is not what this host used, and the root build passed with 3.10.0. Maven 4 is a release candidate and is not the default.

## Story

Read `ARC.md` for the order. Spoken files:

- `STORY.md` and `TECHNICAL.md` are chapter 0
- `CHAPTER1.md` and `CHAPTER1-TECHNICAL.md` are chapter 1
- `CHAPTER2.md` and `CHAPTER2-TECHNICAL.md` are the live payments
- `CHAPTER3.md` and `CHAPTER3-TECHNICAL.md` are the earlier version. The station is `stations/core/versions/show.sh`. It asks the file table for the version before the 205 and for the latest. Verified earlier picture: 121,457, Ordinary 121,392, Planted 65. Latest stays 121,662. Do not delete the new payments to show the earlier picture.

- `CHAPTER4.md` and `CHAPTER4-TECHNICAL.md` are the watch. The station is `stations/core/watch/score.sh`. It searches for a ring of at least five accounts closing within 15 simulated days, without the planted marks, then scores. Verified: 10,183 rings named, 3 planted rings found, 1 planted ring missed, 10,171 named rings were not a planted scheme.

- `CHAPTER5.md` and `CHAPTER5-TECHNICAL.md` are the second look. A second machine runs a second instance of the same database and reads the same file directory through PXF. Verified count: 121,662. Ordinary 121,592. Planted 70. It does not show the earlier version, and it cannot run the watch. Do not copy the install from the first machine. Build Cloudberry and PXF on the second machine, then run the count. The PXF start step installs the extension on each primary, not only the coordinator.

The previous file prefixes stay. A deploy sets `LAKE_PREFIX` to a new single path segment. Publish refuses a prefix that already has Parquet. Do not delete the old objects unless that delete is named.

Two machines: the launcher environment `rl9-aml-spike` with `vm_count` 2. Both use the rocky9 Cloudberry engineering image. The image Maven pin is Apache Maven 3.10.0. Narrations in this directory are the spoken source. Do not regenerate them.

Do not speak kafka_fdw or SeaTunnel. Do not speak a calendar date. Do not say warehouse. A mark stays planted until the watch is scored.
