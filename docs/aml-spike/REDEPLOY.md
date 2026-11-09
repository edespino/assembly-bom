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
- Chapter 2 landing is `stations/core/stream/land.sh`. It publishes 205 payments, 200 ordinary and 5 planted, through the Kafka built from source. The Flink job built from the Flink 2.1.3 source reads that topic and lands the rows. The same rows are committed once as a new Iceberg version. Verified file count after that commit: 121,662. Ordinary 121,592. Planted 70. Do not re-run the landing unless a new version is intended.

Chapter 2 narration is written after that count is on the chart. Do not speak kafka_fdw or SeaTunnel. Do not speak a calendar date. Do not say warehouse. A mark stays planted until the watch is scored.
