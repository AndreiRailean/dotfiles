---
name: file-inbox
description: Use when the user needs to give you files or folders that live on another machine (their laptop or phone), or when you need to hand files back to them.
---

# File inbox

> The session owns one inbox, hands the user one command, and watches for the
> `.done` marker that command writes last.

Each session gets its **own** inbox, because several sessions run on one
machine at once and a shared folder lets them take each other's files. The
user's command ends by writing `.done`, so a half-copied folder never looks
finished, and the session watches for it in the background, so the user never
has to come back and say "sent".

## 1. Work out how this machine receives files

Check in this order and take the first that matches:

| Check | Route |
|---|---|
| `grep -qi microsoft /proc/version` | **WSL.** No transfer: the user saves into a Windows folder and you read it under `/mnt/c/Users/<name>/…`. Give them the Windows path and skip to step 4. |
| `uname -s` is `Darwin` and `$SSH_CONNECTION` is empty | **The user's own Mac.** No transfer: create the inbox (step 2) and give them the path to drag files into. |
| `tailscale status --self --peers=false` succeeds | **Tailnet.** The host is its second column (`awk 'NR==1{print $2}'`). |
| `$SSH_CONNECTION` is set | **Plain SSH.** Its third field is an address the user's side has already reached; offer it and ask whether they use an SSH alias instead. |
| none of these | Ask the user how they reach this machine. Give them the inbox path meanwhile. |

The user is `whoami`. Check `command -v rsync`: rsync over SSH needs it on
**both** ends, so without it here the command uses `scp`.

## 2. Create the inbox

```sh
mkdir -p ~/inbox
mktemp -d "$HOME/inbox/$(basename "$(git -C <your working directory> rev-parse --show-toplevel 2>/dev/null || echo <your working directory>)").XXXX"
```

The printed path is this session's inbox for the rest of the conversation.
Shell variables do not survive between commands, so write that literal path
into every later command; below, `<inbox>` stands for it. Other sessions' inboxes
share the prefix, so the printed path is the only way to tell yours. Reuse it
for later transfers in the same session rather than creating another.

## 3. Hand the user one command

Write it out in full with the real host, user and inbox, so it pastes as-is.
The user replaces only the source path (dragging a folder into Terminal fills
it in):

```sh
scp -r <source> <user>@<host>:<inbox>/ && ssh <user>@<host> touch <inbox>/.done
```

With rsync on this machine, offer `rsync -a <source> <user>@<host>:<inbox>/`
in place of the `scp -r` half; it resumes an interrupted copy. Keep the
`&& ssh … touch` half either way: it runs only if the copy succeeded.

**From a phone**, on the tailnet route only: Share → Tailscale → the host.
Taildrop delivers into one machine-wide queue, so collect with
`tailscale file get --wait --conflict=rename <inbox>` and treat what arrives
as finished (Taildrop withholds a file until it is complete). Files you did not
ask for are another session's: move them to `~/inbox/unclaimed/` and say so.

Say in the same reply that you are watching the inbox and will start as soon
as the copy finishes.

## 4. Watch for `.done`

Start the watch in the same turn as the reply, before the reply text, since the
reply ends your turn. Run it as a background command (`run_in_background`,
with the longest timeout it allows):

```sh
until [ -e <inbox>/.done ]; do sleep 5; done
```

When it fires, list what arrived (`find <inbox> -type f ! -name .done` with
sizes), show the user, and start work in the same turn: the list lets the
person who knows what they sent catch a missing file without you waiting on
them. Zero-byte files are the exception: they are the usual sign of a broken
source, so name them and ask before going on.

If the watch times out with no `.done`, the copy failed or never ran. Tell the
user, repeat the same command, and start a new watch on the same inbox.

## Sending files back: the outbox

Put results in `~/outbox/<the same name as the inbox>/` and give the user the
pull command, written out in full:

```sh
scp -r <user>@<host>:<outbox> ~/Downloads/
```

## When the work is done

The inbox and outbox are scratch. Once the task they served is finished, ask
the user, then remove both.
