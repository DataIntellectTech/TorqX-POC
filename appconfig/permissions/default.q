/ app permission rules for the TorqX-POC demo stack, loaded into every process after the
/ framework tier (kdbx-modules/di/torq/permissions/default.q) when [permissions] enabled=true.
/ -
/ Two kinds of user:
/   torqx  - the identity every process connects AS. di.torq.servers reads it from
/            appconfig/passwords/default.txt and appends it to each outbound connection, so
/            without this user the stack cannot talk to itself.
/   trader - a human user, read-only on trade and quote, to demonstrate the gateway path.

pm:use`di.permissions;

/ --- the inter-process identity -------------------------------------------------------------
/ must match appconfig/passwords/default.txt
pm[`adduser][`torqx;`local;`md5;md5"torqxpass"];
pm[`assignrole][`torqx;`systemuser];
pm[`addtogroup][`torqx;`systemuser];

/ torqx is also a superuser, for the same reason TorQ makes its gateway an `administrator`
/ ("it cannot properly permission without total access", TorQ config/permissions/default.q
/ l.111): some framework calls are expressions the model cannot express a narrow grant for.
/ The idb's read of the wdb is the clearest case - TorQ's idb.q l.70 and di.torq.proc.idb both
/ send (each;value;`.wdb.savedir`...), and the check falls to `$string(first e)`, which for a
/ .q keyword is the lambda's source (`k){x'y}`) rather than `each`. No grant can match it, so
/ the systemuser grants in the framework tier are not sufficient on their own.
/ Least privilege is demonstrated by the `trader` user below, not by this one.
pm[`addrole][`superuser;"unrestricted - see the comment above"];
pm[`grantfunction][pm`ALL;`superuser;{1b}];
pm[`assignrole][`torqx;`superuser];
pm[`addgroup][`superuser;"unrestricted data access"];
pm[`grantaccess][pm`ALL;`superuser;`read];
pm[`grantaccess][pm`ALL;`superuser;`write];
pm[`addtogroup][`torqx;`superuser];

/ this demo's tables - the framework tier grants only its own (heartbeat, logmsg)
pm[`grantaccess][`trade;`systemuser;`read];
pm[`grantaccess][`trade;`systemuser;`write];
pm[`grantaccess][`quote;`systemuser;`read];
pm[`grantaccess][`quote;`systemuser;`write];
pm[`grantaccess][`packets;`systemuser;`read];
pm[`grantaccess][`packets;`systemuser;`write];

/ --- a read-only human user -----------------------------------------------------------------
/ connect as: h:hopen`::5306:trader:traderpass
pm[`addrole][`reader;"read-only queries through the gateway"];
pm[`grantfunction][`select;`reader;{1b}];
/ the gateway entry points, or a client's async request is refused before it reaches the
/ gateway's own check - and because the refusal happens on the async handler there is no reply,
/ so the client blocks on its deferred-sync read rather than seeing an error
pm[`grantfunction][`.gw.asyncexec;`reader;{1b}];
pm[`grantfunction][`.gw.asyncexecjpt;`reader;{1b}];
pm[`addgroup][`readers;"read access to trade and quote"];
pm[`grantaccess][`trade;`readers;`read];
pm[`grantaccess][`quote;`readers;`read];

pm[`adduser][`trader;`local;`md5;md5"traderpass"];
pm[`assignrole][`trader;`reader];
pm[`addtogroup][`trader;`readers];

/ --- a user with WRITE on one table only ------------------------------------------------------
/ connect as: h:hopen`:localhost:5304:writer:writerpass
/ `select` is granted as a FUNCTION because query[] gates every free-form query on it, including
/ update and delete; the read/write split then comes from the access table per table.
pm[`addrole][`writer;"may read and write trade, read quote"];
pm[`grantfunction][`select;`writer;{1b}];
pm[`addgroup][`writers;"write access to trade only"];
pm[`grantaccess][`trade;`writers;`read];
pm[`grantaccess][`trade;`writers;`write];
pm[`grantaccess][`quote;`writers;`read];

pm[`adduser][`writer;`local;`md5;md5"writerpass"];
pm[`assignrole][`writer;`writer];
pm[`addtogroup][`writer;`writers];
