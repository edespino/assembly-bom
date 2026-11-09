# Chapter 5, technical narration

## Say this

You heard the short version: a second database looked at the same files, without a copy, and the count matched. Here is what is on the second machine and what it did.

The second machine. It runs a second instance of the same database as the first, Apache Cloudberry, not a different kind. It was not compiled again on that machine. It runs the same built database as the first. Same database, second machine, second instance.

The bridge. It looked at the files through the same kind of bridge the first database uses, PXF, pointed at the same directory in the same private bucket. The bridge opens the Parquet files where they sit and returns rows. For this count, the second database did not copy the payments into its own tables. It asked, the bridge opened the files, the rows came back, and the count was taken.

The result. Payments: 121,662. Ordinary: 121,592. Planted: 70. Those are the three rows on the chart titled The same files, from the second database. They match the first database's count from the files, to the payment. Same files, two databases, one number. That is chapter 1's proof, from a second machine.

What this shows. The files are the history, and the history did not move. A second team, or an examiner, with their own database, looked at the bank's history where it sits. No export, no transfer, no second copy to reconcile. The second database did not go through the first one. It went to the files.

Two limits, exactly. First, this is the latest pile. The bridge opens a directory of files, not a named version. The second database shows 121,662. It cannot show the earlier version, 121,457, that chapter 3 showed; that picture came from the version record, and the bridge does not consult it. Second, the second database cannot run the watch from chapter 4. The files do not carry who paid whom, and a ring is nothing but who paid whom. The second database can see what the bank has. It cannot trace a ring from these files.

What this cut is not. Not a replica. Nothing was synchronized. Not a migration. Nothing was moved. Not a different product proving the format is open; it is the same database, twice, proving the files are shared. One set of files, two databases, one number.

The sentence to keep: a second database looked at the same files of the practice bank, without a copy, and the count matched.

## Operator note, not spoken

About three minutes. Voice is xAI `sal`. Titles are kept as they appear on screen. Rows in order: Payments 121662; Ordinary 121592; Planted 70. If a live number differs, say the live number, and say whether it still matches the first database's file count. Cloudberry and PXF are each named once in the spoken text. The second instance is stated once as the same database, not a different kind. Do not say: warehouse, read, sleep, today, tonight, a weekday, a snapshot id, 720, a calendar date, that the second database can show 121,457, that it can run the watch, or that the catalog was consulted.
