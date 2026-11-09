# Chapter 3, technical narration

## Say this

You heard the short version: the files still say what the bank had before the new payments, and what it has now. Here is how one set of files gives two answers.

Start with what a version is. In chapter 2, the two hundred and five new payments were committed to the history files as one new version. A commit does not rewrite the files that were there. It writes new files for the new payments, then writes a new record that says which files, old and new, make up the table now. The record from before the commit is kept, and it still names only the older files. So the history has two records: one from before the new payments, one from after. Iceberg is the format that keeps those records, the list of which files belong to each version.

That is where the two pictures come from. The database asked that record for the earlier version, and it returned the files as they stood before the commit: 121,392 ordinary, 65 planted, 121,457 in all. Then it asked for the latest version, and it returned the files with the new payments included: 121,592 ordinary, 70 planted, 121,662 in all. Same files in the bucket. Two lists. Two answers.

Be exact about the source. Neither count came from the table inside the database. Both came from the files, chosen by version. The chart is titled Before and after, from the files, and the title is literal.

Nothing was deleted. The two hundred and five payments are still there. The older files are still there too, because the earlier record still points at them. Asking for the earlier version does not undo the commit. It is a question, not a rollback.

The difference between the two pictures is the arithmetic from chapter 2. 121,662 less 121,457 is 205. 70 less 65 is 5. Those five planted marks were written by the simulator, and they still belong to a ring that was on the chart before they arrived. No rule fired. No model ran.

One thing about time. The simulator has no calendar, so the versions are not dated; they are ordered. Before the new payments, and after. That is the honest question this chapter can answer: not what the bank had on a date, but what the files said at a version.

What this cut is not. It is not a backup. It is not a second copy. It is one set of files, a record of what belonged at each version, and a database that can ask for either.

The sentence to keep: the practice bank's files still say what the bank had before the new payments, and they also say what it has now.

## Operator note, not spoken

About three minutes. Voice is xAI `sal`. Titles are kept as they appear on screen. Expected numbers: before 121,392 / 65 / 121,457; after 121,592 / 70 / 121,662. If a live number differs, say the live number. Iceberg is named once in the spoken text; Kafka, Flink, Polaris, PXF, and Cloudberry are not named. Do not say: warehouse, read, sleep, today, tonight, a weekday, detected, a snapshot id, 720, a calendar date, or that the database table was the source of the two counts.
