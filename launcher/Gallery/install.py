"""How capture.sh installs the gallery on a simulator it has just booted.

The screenshots take a Mac of their own (screens.yml), where they boot the
iPad for the first time, and on GitHub's Macs the gallery's install that
follows can go unanswered for minutes: in the full test pass 43659377514, on
15 November, the iPad booted in 109 s, then in 141 s when run again, and
both times `simctl install` had no answer in 300 s, when the same iPad
installed the gallery at once a minute later, for its own scenarios. The 80
sized scenarios, which come first, got no screen.

So capture.sh tries the install once more, a minute after a first try that
went unanswered or failed, and gives the simulator up only when the second
fails too.
"""

from __future__ import annotations

import time

# How long a try may take, and the pause before the second.
SECONDS = 300
PAUSE = 60


def install(run, failure, udid, app, name, say=print, sleep=time.sleep):
    """Installs APP on the simulator UDID, called NAME, with RUN, capture.sh's,
    which raises FAILURE when a command fails or does not answer in time; once
    more PAUSE seconds later when the first try failed, saying so with SAY."""
    try:
        run("xcrun", "simctl", "install", udid, str(app), timeout=SECONDS)
        return
    except failure as error:
        say(f"::warning::{name}: {error}; once more in {PAUSE} s", flush=True)
    sleep(PAUSE)
    run("xcrun", "simctl", "install", udid, str(app), timeout=SECONDS)
