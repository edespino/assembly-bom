# Chapter 2, technical narration

## Say this

You heard the short version: new payments arrived at the practice bank, the files grew, and the chart shows the larger count. Here is the path they took.

Where new payments come from. The same simulator as the first minute, IBM AMLSim, AML for anti-money laundering, wrote them. Five of the new ones carry the planted mark the simulator wrote, and they belong to a ring that was on the chart before they arrived. The simulator has no calendar, so the arrival you watched is the demo's own clock, not a date in the data.

The live path. Two pieces. Kafka, a log that holds messages in the order they were written, and Flink, a stream processor that takes each payment off that log and writes it into the database as it arrives. The log carries. The processor lands. Two hundred and five payments went down that path and landed in the database. Two hundred ordinary, five planted.

The second landing. The same two hundred and five were committed to the history files as one new version. Iceberg, the table format from chapter 1 that names the files, is what keeps the versions. A commit adds a version; it does not rewrite the files that were there. So the history now has a before and an after.

Now the counts, which are the proof. Before: 121,457 payments in the files. 121,392 ordinary, 65 planted. Arrived: 205. 200 ordinary, 5 planted. After the commit, the files hold 121,662. 121,592 ordinary, 70 planted. The arithmetic closes: 121,457 plus 205 is 121,662, and 65 plus 5 is 70.

The chart on screen, Planted and ordinary, from the history files, is built from the files the same way as chapter 1. It returned 121,662. The Planted slice shows 70. That is the count moving. The proof is the count moving, not a version id.

What this cut is not. No rule fired. No model ran. The five planted marks arrived with their payments, written by the simulator before the payments were ever sent. Nothing was found here.

The sentence to keep: new payments arrived at the practice bank, the files grew, and the chart you know shows the larger count.

## Operator note, not spoken

About three minutes. Voice is xAI `sal`. Speak the titles exactly as they appear on screen. Counts: before 121,457 (Ordinary 121,392, Planted 65); arrived 205 (200 ordinary, 5 planted); after the commit 121,662 (Ordinary 121,592, Planted 70). If a live number differs, say the live number. Kafka, Flink, and Iceberg are each named once in the spoken text; do not add kafka_fdw or SeaTunnel. Do not say: warehouse, read, 720, a version id, a calendar date, or AML on any title.
