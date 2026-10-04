## Budget for this repo

- The factory runs **at most 3 Software Engineers** in parallel for this repo.
- **At most one Simulator job** runs at a time on the machine.
  A lock enforces it (see below).
- **Never a second Simulator on this Mac.** On 2026-09-28, the prompter decided that no design may boot or keep a second Simulator running on this Mac, for any reason: a faster job, a Simulator for QA, a Simulator for `make run`, or the second job slot (doc-3, "no second Simulator on this Mac"; doc-1, section "Testing").
  Why: the boot of a second Simulator next to a booted one, even with no job running, already takes the Mac to an unsafe load (234 to 333, TASK-106, see below).
  A boot with no other Simulator booted measured lower (about 125 to 157, TASK-84 and the QA of TASK-92).
  This is a closed decision, not a trial on pause.
  Only the prompter, in person, can open it again, and only with a new reason (for example, a different Mac).
  Never propose, build or measure a new design with a second Simulator.
  This also covers the two iPhone sizes: every job and every `make run`, `make run SMALL=1` included, uses one shared Simulator at a time (TASK-119, see "The shared Simulator").

Why one Simulator job: on 2026-09-26, each worktree booted its own iOS Simulator, and seven Simulators ran at once on the 8-core Mac.
The load average went above 600, and the prompter could not work.

Why not two Simulator jobs: TASK-62 added a second Simulator slot, for a second job next to the first one, only when at least 25% of the CPU is idle.
It was measured on 2026-09-27 on the real Simulators.
The CPU check works at the start.
But once the second Simulator runs, the CPU is 0% idle for the whole job.
The 1-minute load average went from 44 to 257 in one run, and from 22 to 286 in another (8-core Mac).
The job in slot 2 took 2 to 3.5 minutes instead of about 46 seconds alone: about 3 times slower.
So the gain is not clear, and the risk is the one of 2026-09-26.
The prompter kept the code of the second slot, but off (2026-09-27).
On 2026-09-28, after TASK-106 (below), the prompter decided against the second slot on this Mac: it stays off.
TASK-63 records how long the jobs wait and run.
Its numbers are not a reason to try two jobs again on this Mac.

**The code of the second slot (decided against on this Mac):** `ios/scripts/sim-lock.sh` keeps the code of a second slot, but off (`slots=${RATP_SIM_SLOTS:-1}`).
It is not a trial that an agent or a task can run.
Never change this line, and never add `RATP_SIM_SLOTS=2` to a command.
Only the prompter, in person, can decide to turn it on again, and only with a new reason (for example, a different Mac).
For that case only, this is how the code works.
With `slots=${RATP_SIM_SLOTS:-2}`, a job takes a free slot (slot 1 first).
It runs next to another job only when at least 25% of the CPU is idle (`min_idle_percent` in the same file, or `RATP_SIM_MIN_IDLE_PERCENT` for one command).
Slot 2 uses its own Simulators (`RATP-Shared-2`, `RATP-Shared-Small-2`) and its own lock (`/tmp/ratp-sim.lock.2`), so two jobs never see the data of each other.
A change to two slots must also change this section, "The shared Simulator" and `ios/README.md`.
To go back to one job, change the line back, then run `make simulator-delete` once, to delete the Simulators of slot 2.

Why QA has no Simulator of its own: a QA session keeps the lock while QA explores the app (12 to 19 minutes each on 2026-09-27), and the other jobs wait for it.
TASK-84 measured a QA Simulator next to the shared one before it built anything (2026-09-27, 8-core Mac, 16 GB).
The Mac was quiet before (load 5, CPU 66 to 74% idle).
A full `make e2e` ran on `RATP-Shared`, and a QA session booted `RATP-Shared-QA` 20 seconds after the job took the lock, then opened the app.
The 1-minute load average went from 13 to 106 during the boot, then to 326 about 15 seconds after the app opened.
The CPU was 0% idle for about 90 seconds.
The load logger, which writes a line every 5 seconds, wrote nothing twice for about 30 seconds: the Mac did not answer.
A safety check then shut down the QA Simulator.
The tests passed, but they took 221 seconds instead of 133 to 152 seconds alone.
This is above the level of the second slot trial (257 to 286), for which the prompter kept the second slot off.
So the QA Simulator was not shipped: QA uses the shared Simulator and its lock, like every job.
Limits of the measurement: one run, only the cold case (the QA Simulator boots during the job), and no CPU per process.
The warm case (the QA Simulator booted before the job) was not run, so as not to freeze the Mac again.
The script of the measurement is `ios/scripts/timing/qa-load-check.sh`.
It boots a second Simulator outside the lock, so it never runs on this Mac (see "Never a second Simulator on this Mac").
It stays only to measure on another Mac, when the prompter asks for it.
It deletes `RATP-Shared-QA` when it ends.

Why no second Simulator at all: TASK-106 tried a Simulator of its own for `make run`, apart from the Simulator of the jobs, and measured it on 2026-09-28 (8-core Mac, 16 GB).
Its boot never ran next to a job: `RATP-Shared` was booted and idle, and no job ran.
The first boot of the new Simulator took the 1-minute load average to 333, and the Mac did not answer for about 64 seconds.
Two minutes later, a normal `make run SMALL=1` took the load to 234.
It was a cold boot of the existing `RATP-Shared-Small` next to the booted `RATP-Shared`, with no job (the scripts of TASK-92 kept the other size booted then), so it was not a boot alone.
During the first boot, the Mac used 5.5 to 5.7 GB of swap (6.4 of its 7 GB on the day of the decision, doc-3).
A boot with no other Simulator booted measured lower: about 125 (TASK-84) to 157 (the QA of TASK-92).
So the boot of a second Simulator next to a booted one, even with no job (234 to 333), reaches the levels of TASK-62 (257 to 286, two jobs at once) and TASK-84 (326, a QA Simulator next to a job), and it is close to the freeze of 2026-09-26.
For this reason, the prompter decided against every design with a second Simulator on this Mac, and TASK-106 was closed.

Why 3 Software Engineers: the cap was 2 after that day.
Two checks now protect the Mac, so the prompter set it back to 3 (2026-09-26).
The factory starts a new agent only when at least 25% of the CPU is idle.
The Simulator lock and the shared Simulator keep the Simulator jobs to one at a time.
