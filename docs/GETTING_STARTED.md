# Getting started — a guide for complete beginners

This guide assumes **you have never written code, opened a terminal, or installed a
programming language before.** If you can follow a recipe, you can run crucible.
Budget about 30 minutes, most of which is the computer downloading things while you
wait.

Already comfortable with a command line? Skip this and read the
["Quick start" in the README](../README.md#quick-start) instead.

> **Heads up:** crucible is the most involved of the three sibling projects to set
> up, because the molecular-simulation world it lives in is genuinely complex. This
> guide gets you to a **working, click-through demo** without any of the hardest
> parts (no API keys, no chemistry engines). Those are clearly marked "advanced" at
> the end, and you can ignore them at first.

---

## What crucible does

You give crucible a scientific paper (or a few notes describing a molecular-dynamics
experiment), and it turns that into a **runnable simulation recipe** — checking every
step so you don't waste expensive computer time on a broken setup. The part you'll
interact with is a friendly **notebook** in your web browser.

---

## A few words you'll see

- **Terminal**: a text window where you type commands instead of clicking. Opened in
  Step 1.
- **Julia**: the programming language crucible is written in. You won't write Julia —
  you just need it installed.
- **`juliaup`**: the official installer that puts Julia on your computer and keeps it
  updated.
- **Pluto notebook**: crucible's user interface. It looks like a document in your web
  browser where each section runs and shows results. This is what you'll actually use.
- **Repository** (or "repo"): the folder of code that *is* crucible.

When you see a gray box, type that line into your terminal and press Enter. Type one
line at a time.

---

## Step 1 — Open a terminal

**On Windows:** press the Windows key, type `powershell`, click **Windows
PowerShell**.

**On macOS:** press `Cmd` + `Space`, type `terminal`, press Enter.

**On Linux:** open your terminal (often `Ctrl` + `Alt` + `T`).

---

## Step 2 — Install Julia

Copy the line for your system, paste it into the terminal, and press Enter.

**On Windows (PowerShell):**
```powershell
winget install julia -s msstore
```
*(If that doesn't work, go to <https://julialang.org/install/> in your browser and
follow the Windows instructions there.)*

**On macOS or Linux:**
```bash
curl -fsSL https://install.julialang.org | sh
```
When it asks questions, just press Enter to accept the defaults.

When it finishes, **close the terminal window completely and open a new one**
(repeat Step 1) so your computer notices Julia. Check it worked:

```bash
julia --version
```
You should see something like `julia version 1.11.x` (anything 1.10 or newer is
fine). If you see "command not found", see [Troubleshooting](#troubleshooting).

---

## Step 3 — Download crucible

Pick **one**:

**Option A — download a Zip (easiest):** find the **Download ZIP** button on the
crucible project page in your browser, unzip it somewhere memorable like your
Desktop, then move into it in the terminal:
```bash
cd ~/Desktop/crucible
```
(`cd` means "change directory" — go into this folder.)

**Option B — using `git`:**
```bash
git clone <the-crucible-repository-url>
cd crucible
```

Confirm you're in the right place:
```bash
ls
```
You should see names like `README.md`, `Project.toml`, and `src`.

---

## Step 4 — Install crucible's pieces

From inside the crucible folder, run this single line:

```bash
julia --project -e 'using Pkg; Pkg.instantiate()'
```

In plain English: "Julia, set up everything this project needs." The **first time**,
this downloads a lot and can take **5–15 minutes** — this is normal. You'll get your
prompt back when it's done. (It's safe to walk away while it works.)

---

## Step 5 — Open the notebook (the fun part)

Run:

```bash
julia --project -e 'using Pluto; Pluto.run(notebook="src/ui/notebook.jl")'
```

After a short wait, **your web browser opens automatically** to the crucible
notebook. (If it doesn't, the terminal prints a web address like
`http://localhost:1234/?secret=…` — copy that whole line into your browser.)

Scroll through the notebook from the top. It walks through crucible's process as
numbered sections — turning a description of an experiment into a checked,
ready-to-run simulation recipe. Everything here works **without any API key**, using
built-in example data.

To stop crucible later: go back to the terminal window and press `Ctrl` + `C`.

🎉 **You're running crucible.**

---

## Prefer the command line? A no-notebook demo

If you'd rather see crucible work as plain text commands, this end-to-end demo also
needs no API key (it uses recorded example data):

```bash
bin/crucible help
bin/crucible walkthrough notes "AMBER ff14SB / TIP3P / 300K / 100 ns NPT"
```
*(On Windows, `bin/crucible` won't run directly in PowerShell. Stick with the
notebook in Step 5, or run crucible inside WSL / a Linux-like shell.)*

---

## What next

- **Try your own experiment description.** In the notebook, or in the `walkthrough`
  command above, replace the quoted text with a description of a simulation you care
  about.
- **Read a friendlier tour.** [`docs/USER_PROFILES.md`](USER_PROFILES.md) points you
  to a short guide written for *your* background (grad student, instructor, and so
  on). The [`docs/GLOSSARY.md`](GLOSSARY.md) explains the science terms.
- **The CLI cheatsheet:** [`docs/QUICK_REFERENCE.md`](QUICK_REFERENCE.md).

---

## (Optional, advanced) Running real simulations

The demo above *plans and checks* simulations. To actually *run* the chemistry,
crucible hands its recipe to a simulation engine — **OpenMM** (via Python) or
**Molly** (Julia). And to use a live AI to read real PDFs, you need an API key.
**Both are well beyond a first run — skip them until you're comfortable.**

- **An AI reader:** set an `ANTHROPIC_API_KEY` environment variable. Without it,
  crucible quietly uses recorded example data (which is what this guide relied on).
- **The OpenMM engine:** needs Python plus `pip install openmm`. This pulls in the
  scientific-Python stack and is genuinely fiddly — see the
  ["GPU acceleration"](../README.md#gpu-acceleration) and
  ["Reproducible builds via Docker"](../README.md#reproducible-builds-via-docker)
  sections of the README, which a more experienced person can help you through.

If you only ever want to *plan and validate* simulations and read the output
recipes, you never need this section at all.

---

## Troubleshooting

**"command not found: julia" (or "not recognized")**
You didn't open a fresh terminal after installing Julia in Step 2. Close every
terminal window, open a new one, and try `julia --version` again.

**"No such file or directory" after a `cd` command**
The folder path doesn't match where you actually unzipped crucible. Find the folder
in your file browser, check its exact name, and adjust. Names are case-sensitive on
Mac and Linux.

**Step 4 seems frozen / nothing is happening**
The first `Pkg.instantiate()` is genuinely slow (downloading and compiling). As long
as the terminal hasn't returned an error, let it run — 15 minutes is normal on a
first install.

**The browser didn't open in Step 5**
Look in the terminal for a line starting with `http://localhost:` and copy the whole
thing (including the `?secret=…` part) into your browser's address bar.

**I'm stuck / saw a scary red error**
Copy the full error and the command you ran, and ask for help (a colleague or an AI
assistant). Red text is normal and almost always fixable — it's the computer telling
you exactly what it needs.
