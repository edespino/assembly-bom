# Chapter 1, technical narration

Speak this aloud after the chapter 1 intro, or on its own. Do not speak the operator sheet. No commands are spoken. The chart is on screen; speak its titles exactly as they appear.

Listener: someone who heard the chapter 1 intro, or could have. They know the history sits in files and the database looks at them there. They do not know the formats, the catalog, or the bridge. Explain a term the first time, then use it.

About three minutes. Voice is xAI `sal`.

## Say this

You heard the short version: the practice bank's history sits in files, and the database shows it from there. Here are the parts.

Start with where the files sit. Object storage is a service that keeps files as named objects in a bucket. No disks to mount, no database in front of it. The bank's payments are there now, written as Parquet. Parquet is an open file format for tables: the columns are stored together, and the schema travels inside each file, so any engine that speaks Parquet can open it.

A pile of Parquet files is not yet a table. Iceberg makes it one. An Iceberg table is a small set of metadata files that list which Parquet files belong to the table, what the columns are, and which version is current. The Iceberg table for the payments names the files in the bucket.

Something has to keep track of which Iceberg tables exist. That is the catalog. The catalog here is Apache Polaris, version 1.8.0, built from the signed source release. Polaris holds the table's name and points at its metadata.

Now the database side. Apache Cloudberry is the same database from the first minute. It reaches outside itself through PXF, version 2.2.0-incubating, also built from the signed source. PXF is a bridge. Cloudberry defines an external table, a table whose rows live somewhere else, and PXF fetches those rows when a query asks for them. Here is the one thing to be exact about. PXF opens the Parquet files in the bucket directly. It does not ask the catalog. Polaris and the Iceberg table name the files; the query path in this cut goes straight to the files themselves.

So there are two tables holding the same payments. The heap table is the plain table inside the database, loaded in the first minute. The external table points at the files. Count both. The heap table returned 121,457 payments. The external table over the files returned 121,457. The same number from both places. Nothing dropped on the way out, nothing duplicated.

That is what the screen shows. The dashboard is titled History, where it sits. The chart is titled Planted and ordinary, from the history files. It is built from the external table, so the slices come from the files, not from the heap. Two slices. Ordinary, 121,392. Planted, 65. The 65 are the planted marks, the same ten schemes from the first minute, counted by payment. The planted slice is a sliver: sixty-five out of 121,457.

What this cut is not. The files are not the database's own storage. The database is one engine looking at them. And the catalog is not on the query path. The database went to the files.

The sentence to keep: the practice bank's history sits in files, and the database shows it from where it sits.

## Do not say

Ports. The dashboard address. The word read. Step. Any calendar date. fsync. AML on any title. That the database queried the catalog. How the files got there. The next chapter. Anything from the driver's sheet that is not in the section above.
