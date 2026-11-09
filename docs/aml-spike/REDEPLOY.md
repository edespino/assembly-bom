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

Do not speak kafka_fdw or SeaTunnel. Do not speak a calendar date. Do not say warehouse. A mark stays planted until the watch is scored.
