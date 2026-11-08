# Technical narration

Read this aloud after the spoken intro in `handoff/STORY.md`, or on its own. Do not read the operator sheet. No commands are spoken.

Listener: someone who heard the one-minute intro, or could have. They know it is a practice bank with planted laundering schemes on a chart. They do not know the host, the schema, or how the pieces fit. Explain a term the first time, then use it.

About three minutes. Voice is xAI `sal`.

## Say this

You just heard the short version. A practice bank, planted laundering schemes, shown back on a chart. This is the same bank. Now the parts get their names. Three pieces, one machine.

The first piece is the generator. IBM AMLSim, AML for anti-money laundering, is a simulator. It invents a bank, accounts and the payments between them, then plants laundering patterns into that traffic and writes down exactly which payments it planted. That record is the ground truth. This run used AMLSim's 1K parameter set. It produced 1,446 accounts and 121,457 transactions. Sixty-five of those transactions carry the planted mark. The generator calls each planted scheme an alert. There are ten alerts, and 73 account memberships across them.

The second piece is the database. Apache Cloudberry, version 2.2.0, incubating, built from the Apache source tarball. Cloudberry is a PostgreSQL-family database that spreads one table across several worker processes called segments. Here it runs its small demo layout: one coordinator, the process that takes your query and hands out the work; a standby coordinator; three primary segments, the workers that each hold a slice of the data; and three mirror segments, one copy of each primary. All eight are processes on this one host, not separate machines.

Inside the database the bank sits in a schema named aml. A schema is a named folder of tables. Four tables: accounts, transactions, alert members, and one more, tx count, which this talk does not touch. Two views. A view is a saved query that behaves like a table. Planted schemes by shape feeds the pie. Payments per simulated day feeds the bar. One thing about that bar: the simulator has no calendar. It counts steps, and this demo calls each step a simulated day. No weekends, no holidays, every day alike.

The third piece is the screen. Apache Superset, version 6.1.0, built from the source tag. Cloudberry speaks the PostgreSQL protocol, so Superset connects with the stock PostgreSQL driver. Nothing custom. The dashboard title is the sentence from the intro: Practice bank, planted laundering schemes. Pie on top, bar below.

Now the three shapes. The chart says Into one. The generator calls that fan-in: many payments into a single account. Three alerts. The chart says Out to many. The generator calls that fan-out: one account paying many others. Three alerts. The chart says Comes back. The generator calls that a cycle: the money leaves and returns. Four alerts. Three, three, and four make ten.

Here is one of the four. Alert six, a Comes back. Six accounts. Account 348 is the one the generator marks as the main account. Follow the labels. 348 paid 796. 796 paid 128. 128 paid 1264. 1264 paid 154. 154 paid 244. 244 paid 348. Six transfers, and the loop closes. Now follow the simulated days. They are 145, 146, 148, 152, and 155, and they are not in ring order. The payment back into 348 lands on day 152. Two of the hops that feed it land on day 155. The ring is a set of labeled edges, not six payments on six tidy days.

What this cut is not. No model ran. No rule fired. The query behind the pie counts labels the generator wrote before the load. Ten is an input, not a finding.

## Do not say

Amounts. Ports. How you logged in. The build hash. fsync. The start_step and end_step columns. That this layout is production. The next chapter. Anything from the driver's sheet that is not in the section above.
